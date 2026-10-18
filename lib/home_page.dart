import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'pdf_files.dart';
import 'reader_page.dart';
import 'store.dart';
import 'toc.dart';
import 'utils.dart';
import 'widgets/brand_mark.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _importing = false;

  /// Picks a PDF, asks which subject it is, then adds it to the shelf.
  Future<void> _addBook() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final PlatformFile? picked = await FilePicker.pickFile(
        dialogTitle: '选择要加入书架的 PDF',
        type: FileType.custom,
        allowedExtensions: <String>['pdf'],
      );
      if (picked == null || !mounted) return;
      final String? subject = await _askSubject();
      if (subject == null || !mounted) return;
      final String localPath = await PdfImporter.importPlatformFile(picked);
      if (!mounted) return;
      final String title = pdfTitle(picked.name);
      await AppStore.instance.addBook(
        path: localPath,
        title: title,
        subject: subject,
      );
      if (!mounted) return;
      await _openFile(
        localPath,
        fallbackTitle: title,
        subject: subject,
      );
    } catch (error) {
      _showMessage('添加失败：$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// Asks which of the curated subjects the book belongs to.
  Future<String?> _askSubject() {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('这本电子书是哪一科？'),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              '选择后会自动套用该科目的完整目录',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          ...kSubjects.map(
            (TocSubject subject) => SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(subject.id),
              child: Row(
                children: <Widget>[
                  Icon(
                    subject.id == kSubjectNone
                        ? Icons.description_outlined
                        : Icons.menu_book_outlined,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(subject.label)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFile(
    String path, {
    String? fallbackTitle,
    int initialPage = 1,
    String subject = kSubjectNone,
    int pageOffset = 0,
  }) async {
    final String title = fallbackTitle ?? pdfTitle(path);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ReaderPage(
          filePath: path,
          title: title,
          initialPage: initialPage,
          subject: subject,
          pageOffset: pageOffset,
        ),
      ),
    );
  }

  Future<void> _changeSubject(ShelfBook book) async {
    final String? subject = await _askSubject();
    if (subject == null) return;
    await AppStore.instance.addBook(
      path: book.path,
      title: book.title,
      subject: subject,
      totalPages: book.totalPages,
    );
  }

  Future<void> _confirmRemove(ShelfBook book) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('从书架移除'),
        content: Text('将移除《${book.title}》，并删除应用内的本地副本。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await AppStore.instance.removeBook(book.path);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: <Widget>[
            const BrandMark(),
            const SizedBox(width: 10),
            Text('408真题系统', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        actions: <Widget>[
          ListenableBuilder(
            listenable: AppStore.instance,
            builder: (BuildContext context, Widget? child) {
              return PopupMenuButton<ThemeMode>(
                icon: const Icon(Icons.brightness_6),
                tooltip: '外观',
                initialValue: AppStore.instance.themeMode,
                onSelected: (ThemeMode mode) =>
                    AppStore.instance.setThemeMode(mode),
                itemBuilder: (BuildContext context) =>
                    const <PopupMenuEntry<ThemeMode>>[
                  PopupMenuItem<ThemeMode>(
                    value: ThemeMode.system,
                    child: Text('跟随系统'),
                  ),
                  PopupMenuItem<ThemeMode>(
                    value: ThemeMode.light,
                    child: Text('浅色'),
                  ),
                  PopupMenuItem<ThemeMode>(
                    value: ThemeMode.dark,
                    child: Text('深色'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _importing ? null : _addBook,
                icon: _importing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.library_add_outlined),
                label: Text(_importing ? '正在添加…' : '添加电子书到书架'),
              ),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: AppStore.instance,
              builder: (BuildContext context, Widget? child) {
                final List<ShelfBook> shelf = AppStore.instance.shelf;
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: <Widget>[
                    _SectionHeader(
                      title: '我的书架',
                      trailing: shelf.isEmpty ? null : '${shelf.length} 本',
                    ),
                    ...shelf.map(_buildBookTile),
                    if (shelf.isEmpty) const _EmptyShelf(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookTile(ShelfBook book) {
    final String progress = book.totalPages > 0
        ? '第 ${book.page} / ${book.totalPages} 页'
        : '未翻开';
    return ListTile(
      leading: const Icon(Icons.menu_book_outlined),
      title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${subjectLabel(book.subject)} · $progress',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<String>(
        tooltip: '更多',
        onSelected: (String action) {
          switch (action) {
            case 'subject':
              _changeSubject(book);
            case 'remove':
              _confirmRemove(book);
          }
        },
        itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(value: 'subject', child: Text('更改科目')),
          PopupMenuItem<String>(value: 'remove', child: Text('从书架移除')),
        ],
      ),
      onTap: () => _openFile(
        book.path,
        fallbackTitle: book.title,
        initialPage: book.page,
        subject: book.subject,
        pageOffset: book.pageOffset,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          if (trailing != null)
            Text(trailing!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        children: <Widget>[
          Icon(Icons.collections_bookmark_outlined, size: 64, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            '书架还是空的\n点击上方按钮，选择你本地的 PDF 加入书架',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
