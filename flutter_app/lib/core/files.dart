/// 课程文件与文件夹。
///
/// 与桌面端 `src/core/files.ts` 一一对应，行为必须一致
/// （有同样的单元测试兜底）。
///
/// 磁盘路径约定：根目录 / 学期 / 课程 / Canvas 子文件夹... / 文件名
library;

/// Canvas 里的文件夹。
class CanvasFolder {
  const CanvasFolder({
    required this.id,
    required this.name,
    this.fullName = '',
    this.parentFolderId,
    this.filesCount = 0,
    this.foldersCount = 0,
    this.position,
  });

  final int id;
  final String name;
  final String fullName;
  final int? parentFolderId;
  final int filesCount;
  final int foldersCount;

  /// Canvas 自己的排序位，按它排才能得到「第一章、第二章」而不是拼音序。
  final int? position;

  factory CanvasFolder.fromJson(Map<String, dynamic> json) => CanvasFolder(
        id: _num(json['id']),
        name: _str(json['name'], '未命名文件夹'),
        fullName: _str(json['full_name']),
        parentFolderId: json['parent_folder_id'] == null ? null : _num(json['parent_folder_id']),
        filesCount: _num(json['files_count']),
        foldersCount: _num(json['folders_count']),
        position: json['position'] == null ? null : _num(json['position']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'full_name': fullName,
        'parent_folder_id': parentFolderId,
        'files_count': filesCount,
        'folders_count': foldersCount,
        'position': position,
      };
}

/// Canvas 里的一个文件。
class CanvasFile {
  const CanvasFile({
    required this.id,
    this.folderId,
    required this.displayName,
    this.filename = '',
    this.contentType = '',
    required this.url,
    this.size = 0,
    this.createdAt = '',
    this.updatedAt = '',
    this.locked = false,
    this.hidden = false,
  });

  final int id;
  final int? folderId;
  final String displayName;
  final String filename;
  final String contentType;

  /// 带 verifier 的限时下载地址，必须来自本轮接口响应，不能缓存复用。
  final String url;
  final int size;
  final String createdAt;
  final String updatedAt;
  final bool locked;
  final bool hidden;

  factory CanvasFile.fromJson(Map<String, dynamic> json) => CanvasFile(
        id: _num(json['id']),
        folderId: json['folder_id'] == null ? null : _num(json['folder_id']),
        displayName: _str(json['display_name']).isNotEmpty
            ? _str(json['display_name'])
            : (_str(json['filename']).isNotEmpty ? _str(json['filename']) : 'file-${_num(json['id'])}'),
        filename: _str(json['filename']),
        // Canvas 这个字段写作 "content-type"（带连字符）。
        contentType: _str(json['content-type']).isNotEmpty
            ? _str(json['content-type'])
            : _str(json['content_type']),
        url: _str(json['url']).isNotEmpty ? _str(json['url']) : _str(json['download_url']),
        size: _num(json['size']),
        createdAt: _str(json['created_at']),
        updatedAt: _str(json['updated_at']).isNotEmpty ? _str(json['updated_at']) : _str(json['modified_at']),
        locked: json['locked'] == true || json['locked_for_user'] == true,
        hidden: json['hidden'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'folder_id': folderId,
        'display_name': displayName,
        'filename': filename,
        'content-type': contentType,
        'url': url,
        'size': size,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'locked': locked,
        'hidden': hidden,
      };
}

/// 目录树节点，界面与下载都基于它。
class FileNode {
  FileNode({
    required this.kind,
    required this.name,
    required this.path,
    this.size,
    this.contentType,
    this.position,
    this.file,
    List<FileNode>? children,
  }) : children = children ?? <FileNode>[];

  /// 'folder' 或 'file'。
  final String kind;
  final String name;

  /// 相对课程根目录的路径。构建树时会被原地补上，所以不是 final——
  /// 节点一旦挂到父节点下，替换对象会让父节点里的引用失效。
  String path;
  final int? size;
  final String? contentType;
  final int? position;
  final CanvasFile? file;
  final List<FileNode> children;

  bool get isFolder => kind == 'folder';

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'name': name,
        'path': path,
        if (size != null) 'size': size,
        if (contentType != null) 'content_type': contentType,
        if (position != null) 'position': position,
        if (file != null) 'file': file!.toJson(),
        'children': children.map((c) => c.toJson()).toList(),
      };

  factory FileNode.fromJson(Map<String, dynamic> json) => FileNode(
        kind: _str(json['kind'], 'file'),
        name: _str(json['name']),
        path: _str(json['path']),
        size: json['size'] == null ? null : _num(json['size']),
        contentType: json['content_type'] as String?,
        position: json['position'] == null ? null : _num(json['position']),
        file: json['file'] == null
            ? null
            : CanvasFile.fromJson((json['file'] as Map).cast<String, dynamic>()),
        children: ((json['children'] as List?) ?? const [])
            .map((c) => FileNode.fromJson((c as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// 一门课的文件与文件夹（扁平列表）。
class CourseFiles {
  const CourseFiles({required this.folders, required this.files});

  final List<CanvasFolder> folders;
  final List<CanvasFile> files;
}

int _num(Object? v) => v is num && v.isFinite ? v.toInt() : 0;

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

// ---------------------------------------------------------------------------
// 文件名净化
// ---------------------------------------------------------------------------

/// Windows 保留的设备名，不能作为文件名。
const Set<String> _reservedNames = {
  'con', 'prn', 'aux', 'nul',
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

final RegExp _illegalChars = RegExp(r'[\\/:*?"<>|\x00-\x1f]');
final RegExp _whitespace = RegExp(r'\s+');
final RegExp _trailingDotsSpaces = RegExp(r'[. ]+$');

/// 把一个路径段净化成各平台都能用的名字。
///
/// Android 用的是 ext4/f2fs，限制比 Windows 少，但外置存储与
/// 用戶再拷贝到电脑时仍会遇到同样的问题，所以规则与桌面端保持一致。
String sanitizeSegment(String raw) {
  var name = raw.trim();
  name = name.replaceAll(_illegalChars, '_');
  name = name.replaceAll(_whitespace, ' ').trim();
  name = name.replaceAll(_trailingDotsSpaces, '');

  if (name.length > 120) {
    final dot = name.lastIndexOf('.');
    if (dot > 0 && name.length - dot <= 12) {
      final ext = name.substring(dot);
      name = name.substring(0, 120 - ext.length) + ext;
    } else {
      name = name.substring(0, 120);
    }
  }

  if (name.isEmpty) return '_';

  final dot = name.indexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  if (_reservedNames.contains(stem.toLowerCase())) name = '_$name';

  return name;
}

/// 净化一整条相对路径（按 '/' 分段）。
String sanitizePath(String relativePath) => relativePath
    .split('/')
    .where((s) => s.isNotEmpty && s != '.' && s != '..')
    .map(sanitizeSegment)
    .join('/');

/// 在同一目录内去重：重名的第二个变成 `名字 (2).ext`，以此类推。
///
/// 比较时忽略大小写——文件可能被拷到 Windows 或 macOS 上，
/// 那里 `A.pdf` 与 `a.pdf` 会互相覆盖。
List<String> dedupePaths(List<String> paths) {
  final used = <String>{};
  final out = <String>[];

  for (final p in paths) {
    final slash = p.lastIndexOf('/');
    final dir = slash < 0 ? '' : p.substring(0, slash + 1);
    final base = slash < 0 ? p : p.substring(slash + 1);

    // 只有非隐藏文件（点不在开头）才拆扩展名。
    final dot = base.lastIndexOf('.');
    final hasExt = dot > 0;
    final stem = hasExt ? base.substring(0, dot) : base;
    final ext = hasExt ? base.substring(dot) : '';

    var candidate = p;
    var n = 2;
    while (used.contains(candidate.toLowerCase())) {
      candidate = '$dir$stem ($n)$ext';
      n += 1;
    }

    used.add(candidate.toLowerCase());
    out.add(candidate);
  }
  return out;
}

/// 自然序比较：把名字里的数字当数字比。
///
/// 这样 `第2章` 排在 `第10章` 前面。中文数字（一、二）不在此列，
/// 那要靠 Canvas 的 position。
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final ax = re.allMatches(a).map((m) => m.group(0)!).toList();
  final bx = re.allMatches(b).map((m) => m.group(0)!).toList();

  for (var i = 0; i < ax.length && i < bx.length; i++) {
    final an = RegExp(r'^\d+$').hasMatch(ax[i]);
    final bn = RegExp(r'^\d+$').hasMatch(bx[i]);
    if (an && bn) {
      final d = int.parse(ax[i]) - int.parse(bx[i]);
      if (d != 0) return d;
    } else {
      final c = ax[i].compareTo(bx[i]);
      if (c != 0) return c;
    }
  }
  return ax.length - bx.length;
}

// ---------------------------------------------------------------------------
// 目录树
// ---------------------------------------------------------------------------

/// 由扁平的文件夹与文件列表构建树。
///
/// 用 parentFolderId 串层级，而不是解析 fullName——
/// 后者带本地化的根名（"course files" / "课程文件"），解析起来不可靠。
FileNode buildFileTree(List<CanvasFolder> folders, List<CanvasFile> files) {
  final byId = <int, FileNode>{};
  final root = FileNode(kind: 'folder', name: '', path: '', children: []);

  for (final f in folders) {
    byId[f.id] = FileNode(
      kind: 'folder',
      name: sanitizeSegment(f.name),
      path: '',
      position: f.position,
      children: [],
    );
  }

  final parentOf = <int, int?>{for (final f in folders) f.id: f.parentFolderId};

  String pathOf(int id, [int depth = 0]) {
    final node = byId[id];
    if (node == null) return '';
    if (node.path.isNotEmpty) return node.path;
    // 正常数据不会有环；万一有也不能把递归撑爆。
    if (depth > 64) {
      node.path = node.name;
      return node.path;
    }
    final parent = parentOf[id];
    final parentPath = (parent != null && byId.containsKey(parent)) ? pathOf(parent, depth + 1) : '';
    // 必须原地改：这个对象可能已经挂在父节点的 children 里了。
    node.path = parentPath.isNotEmpty ? '$parentPath/${node.name}' : node.name;
    return node.path;
  }

  for (final f in folders) {
    pathOf(f.id);
    final node = byId[f.id]!;
    final parent = f.parentFolderId;
    final bucket = (parent != null && byId.containsKey(parent)) ? byId[parent]! : root;
    bucket.children.add(node);
  }

  for (final file in files) {
    final folder = file.folderId != null ? byId[file.folderId] : null;
    final name = sanitizeSegment(
      file.displayName.isNotEmpty
          ? file.displayName
          : (file.filename.isNotEmpty ? file.filename : 'file-${file.id}'),
    );
    final parentPath = folder?.path ?? '';
    (folder ?? root).children.add(FileNode(
      kind: 'file',
      name: name,
      path: parentPath.isNotEmpty ? '$parentPath/$name' : name,
      size: file.size,
      contentType: file.contentType,
      file: file,
      children: [],
    ));
  }

  // 目录在前；文件夹按 Canvas 的 position 排，文件按自然序排。
  void sortNode(FileNode n) {
    n.children.sort((a, b) {
      if (a.kind != b.kind) return a.isFolder ? -1 : 1;
      if (a.isFolder) {
        final ap = a.position;
        final bp = b.position;
        if (ap != null && bp != null && ap != bp) return ap - bp;
        if (ap != null && bp == null) return -1;
        if (ap == null && bp != null) return 1;
      }
      return naturalCompare(a.name, b.name);
    });
    for (final c in n.children) {
      sortNode(c);
    }
  }

  sortNode(root);
  return root;
}

/// 把树摊平成文件列表（下载时用）。
List<FileNode> flattenFiles(FileNode node) {
  final out = <FileNode>[];
  void walk(FileNode n) {
    if (!n.isFolder) out.add(n);
    for (final c in n.children) {
      walk(c);
    }
  }

  walk(node);
  return out;
}

/// 统计目录下的文件数与总字节数。
({int count, int bytes}) treeStats(FileNode node) {
  final files = flattenFiles(node);
  return (count: files.length, bytes: files.fold(0, (s, f) => s + (f.size ?? 0)));
}

// ---------------------------------------------------------------------------
// 磁盘路径
// ---------------------------------------------------------------------------

/// 一个待下载项：相对根目录的路径 + 文件本身。
class DownloadTarget {
  const DownloadTarget({required this.relativePath, required this.file});

  final String relativePath;
  final CanvasFile file;
}

/// 算出「学期 / 课程 / 子文件夹 / 文件名」这条相对路径。
List<DownloadTarget> planDownloadPaths(
  String termName,
  String courseName,
  List<({String folderPath, String fileName, CanvasFile file})> entries,
) {
  final term = sanitizeSegment(termName);
  final course = sanitizeSegment(courseName);

  final raws = entries.map((e) {
    final folder = sanitizePath(e.folderPath);
    final base = '$term/$course';
    return folder.isNotEmpty ? '$base/$folder/${e.fileName}' : '$base/${e.fileName}';
  }).toList();

  final uniqued = dedupePaths(raws);
  return [
    for (var i = 0; i < entries.length; i++)
      DownloadTarget(relativePath: uniqued[i], file: entries[i].file),
  ];
}

/// 人类可读的字节数。
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  var value = bytes.toDouble();
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i += 1;
  }
  final text = (value >= 100 || i == 0) ? value.round().toString() : value.toStringAsFixed(1);
  return '$text ${units[i]}';
}
