<#
.SYNOPSIS
    在 Windows 上构建 Android release APK。

.DESCRIPTION
    封装了四个坑，一条命令搞定：

    1. Gradle 发行包走腾讯云镜像（官方源在国内会被重定向到被墙的 CDN）；
    2. **在纯 ASCII 路径下构建** —— 本仓库路径含「杂」字，Dart 的 AOT 工具
       gen_snapshot 会把路径错误解码成「锟斤拷」，导致 release 构建必失败；
    3. 关掉 Kotlin 增量编译（Windows 上会因文件锁写盘失败）；
    4. 把产物拷回项目里，方便取用。

    首次运行会复制整个工程到 ASCII 路径（排除构建缓存），之后复用。

.EXAMPLE
    pwsh flutter_app/tool/build_android.ps1
    pwsh flutter_app/tool/build_android.ps1 -JavaHome D:\jdk-17 -AndroidSdk D:\android-sdk
#>

[CmdletBinding()]
param(
    # JDK 17 所在目录
    [string]$JavaHome = 'D:\jdk-17',

    # Android SDK 所在目录（需含 cmdline-tools/latest、platforms;android-36、build-tools;36.0.0）
    [string]$AndroidSdk = 'D:\android-sdk',

    # 纯 ASCII 的构建工作目录。路径里不能有中文或空格。
    [string]$BuildRoot = 'D:\build\fudan_elearning',

    # 是否强制重新复制工程
    [switch]$FreshCopy
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot          # flutter_app/
$distDir = Join-Path $projectRoot 'dist'

function Assert-Path {
    param([string]$Path, [string]$What)
    if (-not (Test-Path $Path)) { throw "$What 不存在：$Path" }
}

Assert-Path $JavaHome 'JDK 目录'
Assert-Path $AndroidSdk 'Android SDK 目录'
Assert-Path (Join-Path $AndroidSdk 'build-tools\36.0.0') 'build-tools;36.0.0'

if ($BuildRoot -match '[^\x00-\x7F]') {
    throw "构建目录必须是纯 ASCII 路径，当前为：$BuildRoot"
}

# --- 环境 -------------------------------------------------------------------
$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:Path = "$JavaHome\bin;$AndroidSdk\platform-tools;$env:Path"
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'PATH 里找不到 flutter，请先把 Flutter SDK 的 bin 目录加进 PATH。'
}

# --- 复制到 ASCII 路径 ------------------------------------------------------
$needsCopy = $FreshCopy -or -not (Test-Path (Join-Path $BuildRoot 'pubspec.yaml'))
if ($needsCopy) {
    Write-Host "复制工程到 ASCII 路径：$BuildRoot"
    New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
    & robocopy $projectRoot $BuildRoot /E /NFL /NDL /NJH /NJS /NP `
        /XD build .dart_tool .gradle .idea .cxx dist `
        /XF '*.iml' | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy 失败，退出码 $LASTEXITCODE" }

    # 增量编译在 Windows 上会因文件锁写盘失败。
    Add-Content -Path (Join-Path $BuildRoot 'android\gradle.properties') `
        -Value "`nkotlin.incremental=false" -Encoding utf8
} else {
    Write-Host "复用已有构建目录：$BuildRoot（改动源码后如需同步，加 -FreshCopy）"
}

# --- 构建 -------------------------------------------------------------------
Push-Location $BuildRoot
try {
    Write-Host "开始构建 release APK ..."
    $sw = [Diagnostics.Stopwatch]::StartNew()

    # 原生命令（flutter.bat）会把「Flutter assets will be downloaded from ...」
    # 这类提示写到 stderr。在 $ErrorActionPreference='Stop' 下，
    # PowerShell 会把任何 stderr 输出当成终止性错误，于是构建明明在跑却报错。
    # 所以这里临时放宽，改看退出码。
    $ErrorActionPreference = 'Continue'
    & flutter build apk --release
    $buildExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($buildExit -ne 0) { throw "flutter build apk 失败，退出码 $buildExit" }
    $sw.Stop()

    $apk = Join-Path $BuildRoot 'build\app\outputs\flutter-apk\app-release.apk'
    Assert-Path $apk 'APK 产物'

    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
    $target = Join-Path $distDir 'fudan-elearning.apk'
    Copy-Item $apk $target -Force

    $sizeMb = [math]::Round((Get-Item $target).Length / 1MB, 1)
    Write-Host ""
    Write-Host "构建完成，用时 $([math]::Round($sw.Elapsed.TotalMinutes,1)) 分钟"
    Write-Host "APK：$target  ($sizeMb MB)"
    Write-Host "安装：adb install `"$target`"，或直接传到手机上点开"
} finally {
    Pop-Location
}
