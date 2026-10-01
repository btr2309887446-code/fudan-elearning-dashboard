/// 课程文件：浏览 + 下载。
///
/// 交互与桌面端一致：
///  - 点文件夹行展开/收起；
///  - 点文件名直接下载这一个；
///  - 勾选框多选，出现「下载选中」；
///  - 「下载本课全部」整门课打包。
library;

import 'package:flutter/material.dart';

import '../core/files.dart';
import '../platform/downloads.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'widgets.dart';

class FilesSection extends StatefulWidget {
  const FilesSection({super.key, required this.state, required this.courseId});

  final AppState state;
  final int courseId;

  @override
  State<FilesSection> createState() => _FilesSectionState();
}

class _FilesSectionState extends State<FilesSection> {
  FileNode? _tree;
  bool _loading = true;
  String? _error;
  final Set<String> _expanded = {''};
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tree = await widget.state.loadCourseFiles(widget.courseId, force: force);
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _loading = false;
        // 默认展开第一层，让用户立刻看到内容。
        _expanded
          ..clear()
          ..add('')
          ..addAll(tree.children.where((c) => c.isFolder).map((c) => c.path));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _download({List<int>? ids}) async {
    setState(() => _error = null);
    try {
      final result = await widget.state.downloadCourseFiles(widget.courseId, fileIds: ids);
      if (!mounted) return;
      if (result != null && result.failed == 0) setState(() => _selected.clear());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _toggleFolder(String path) {
    setState(() {
      if (_expanded.contains(path)) {
        _expanded.remove(path);
      } else {
        _expanded.add(path);
      }
    });
  }

  void _toggleNode(FileNode node, bool select) {
    final ids = node.isFolder
        ? flattenFiles(node).where((f) => f.file != null).map((f) => f.file!.id)
        : [node.file!.id];
    setState(() {
      for (final id in ids) {
        if (select) {
          _selected.add(id);
        } else {
          _selected.remove(id);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = widget.state;
    final tree = _tree;
    final progress = state.downloadProgress;
    final stats = tree == null ? null : treeStats(tree);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SectionHeader(
                  '课程文件',
                  trailing: stats == null
                      ? null
                      : Text(
                          '${stats.count} 个文件 · ${formatBytes(stats.bytes)}',
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                ),
              ),
              if (state.downloading)
                TextButton(
                  onPressed: state.cancelDownload,
                  child: const Text('取消下载'),
                )
              else
                FilledButton.tonal(
                  onPressed: (_loading || stats == null || stats.count == 0)
                      ? null
                      : () => _download(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text('下载本课全部', style: TextStyle(fontSize: 13)),
                ),
            ],
          ),
          if (progress != null && state.downloading) _progressBar(context, progress, p),

          if (_selected.isNotEmpty && !state.downloading)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.10),
                border: Border.all(color: p.accent),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已选 ${_selected.length} 个文件',
                      style: TextStyle(color: p.accent, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text('清空'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _download(ids: _selected.toList()),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('下载选中', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),

          if (_loading) const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('正在读取文件列表…', style: TextStyle(fontSize: 13)),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: TextStyle(color: p.bad, fontSize: 13)),
            ),

          if (!_loading && tree != null && tree.children.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('这门课还没有上传任何文件。', style: TextStyle(color: p.muted, fontSize: 13)),
            ),

          if (!_loading && tree != null && tree.children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final child in tree.children) _node(child, 0, p),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _progressBar(BuildContext context, DownloadProgress progress, AppPalette p) {
    final percent = progress.bytesTotal > 0
        ? (progress.bytesReceived / progress.bytesTotal).clamp(0.0, 1.0)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  progress.currentName.isEmpty ? '准备中…' : '正在下载：${progress.currentName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: p.textDim, fontWeight: FontWeight.w500),
                ),
              ),
              Text(
                '${progress.completed + progress.skipped} / ${progress.total}',
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 5,
              backgroundColor: p.border,
              valueColor: AlwaysStoppedAnimation(p.accent),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${formatBytes(progress.bytesReceived)} / ${formatBytes(progress.bytesTotal)}',
            style: TextStyle(fontSize: 11.5, color: p.muted),
          ),
        ],
      ),
    );
  }

  Widget _node(FileNode node, int depth, AppPalette p) {
    final state = widget.state;
    final ids = node.isFolder
        ? flattenFiles(node).where((f) => f.file != null).map((f) => f.file!.id).toList()
        : [node.file!.id];
    final allSelected = ids.isNotEmpty && ids.every(_selected.contains);
    final someSelected = !allSelected && ids.any(_selected.contains);
    final isOpen = _expanded.contains(node.path);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: node.isFolder
              ? () => _toggleFolder(node.path)
              : (state.downloading ? null : () => _download(ids: [node.file!.id])),
          child: Padding(
            padding: EdgeInsets.fromLTRB(4 + depth * 16.0, 7, 4, 7),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Checkbox(
                    value: allSelected,
                    tristate: false,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: state.downloading ? null : (_) => _toggleNode(node, !allSelected),
                  ),
                ),
                if (someSelected)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text('·', style: TextStyle(color: p.accent, fontSize: 16)),
                  ),
                Icon(
                  node.isFolder
                      ? (isOpen ? Icons.folder_open : Icons.folder)
                      : _iconFor(node.contentType),
                  size: 17,
                  color: node.isFolder ? p.accent : p.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: node.isFolder ? FontWeight.w600 : FontWeight.w400,
                      color: p.text,
                    ),
                  ),
                ),
                Text(
                  node.isFolder
                      ? '${flattenFiles(node).length} 个'
                      : formatBytes(node.size ?? 0),
                  style: TextStyle(fontSize: 11.5, color: p.muted),
                ),
              ],
            ),
          ),
        ),
        if (node.isFolder && isOpen)
          for (final child in node.children) _node(child, depth + 1, p),
      ],
    );
  }

  IconData _iconFor(String? contentType) {
    final t = contentType ?? '';
    if (t.startsWith('image/')) return Icons.image_outlined;
    if (t.startsWith('video/')) return Icons.movie_outlined;
    if (t.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (t.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (t.contains('zip') || t.contains('compressed')) return Icons.folder_zip_outlined;
    if (t.contains('word') || t.contains('document')) return Icons.description_outlined;
    if (t.contains('sheet') || t.contains('excel')) return Icons.table_chart_outlined;
    if (t.contains('presentation') || t.contains('powerpoint')) return Icons.slideshow_outlined;
    return Icons.insert_drive_file_outlined;
  }
}
