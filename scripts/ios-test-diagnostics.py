"""Export readable XCTest results and app crash stacks on a Mac runner."""

import json
from pathlib import Path
import subprocess
import sys
import zipfile

source = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
output.mkdir(parents=True, exist_ok=True)
bundles = list(source.rglob("*.xcresult"))
if not bundles and (source / "Info.plist").exists():
    bundles = [source]
for index, bundle in enumerate(bundles):
    target = output / str(index)
    target.mkdir(exist_ok=True)
    for kind in ("summary", "tests"):
        result = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", kind, "--path", str(bundle)], capture_output=True, text=True)
        (target / f"{kind}.json").write_text(result.stdout or result.stderr)
        if kind == "summary":
            print(result.stdout[:14000])
    subprocess.run(["xcrun", "xcresulttool", "export", "diagnostics", "--path", str(bundle), "--output-path", str(target / "diagnostics")], check=False)
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle), "--output-path", str(target / "attachments")], check=False)

for archive in list(output.rglob("*.zip")):
    destination = archive.with_suffix("")
    with zipfile.ZipFile(archive) as zipped:
        for item in zipped.infolist():
            resolved = (destination / item.filename).resolve()
            if not resolved.is_relative_to(destination.resolve()):
                raise ValueError("Unsafe diagnostic archive path")
        zipped.extractall(destination)

reports = []
for path in sorted(output.rglob("*")):
    if not path.is_file():
        continue
    print(f"EXPORTED_FILE {path.relative_to(output)} ({path.stat().st_size} bytes)")
    if path.suffix in (".crash", ".txt", ".log") and path.stat().st_size < 10_000_000:
        raw = path.read_text(errors="replace")
        markers = ("Fatal error", "Assertion failed", "Terminating app", "Exception Type:", "Last Exception Backtrace", "AttributeGraph")
        if "NativeRunner" in raw and any(marker in raw for marker in markers):
            print(f"CRASH_TEXT {path.relative_to(output)}\n{raw[:24000]}")
for path in output.rglob("*.ips"):
    if "NativeRunner" not in path.name:
        continue
    raw = path.read_text(errors="replace")
    try:
        _, end = json.JSONDecoder().raw_decode(raw)
        payload = json.loads(raw[end:]) if raw[end:].strip() else json.loads(raw)
    except ValueError:
        continue
    if payload.get("procName") != "NativeRunner":
        continue
    images = payload.get("usedImages", [])
    report = {"file": str(path.relative_to(output)), "exception": payload.get("exception"), "termination": payload.get("termination"), "asi": payload.get("asi")}
    frames = payload.get("lastExceptionBacktrace") or payload.get("threads", [{}])[payload.get("faultingThread", 0)].get("frames", [])
    report["frames"] = [{"symbol": frame.get("symbol"), "offset": frame.get("imageOffset"), "image": images[frame["imageIndex"]].get("name") if frame.get("imageIndex", -1) in range(len(images)) else None} for frame in frames[:60]]
    reports.append(report)
    print(json.dumps(report, ensure_ascii=False, indent=2))
(output / "app-crashes.json").write_text(json.dumps(reports, ensure_ascii=False, indent=2))
