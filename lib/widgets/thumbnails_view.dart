import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Page thumbnails grid used to jump around the document.
class ThumbnailsView extends StatelessWidget {
  const ThumbnailsView({
    super.key,
    required this.document,
    required this.currentPage,
    required this.onOpenPage,
  });

  /// `null` while the document is still loading.
  final PdfDocument? document;
  final int currentPage;
  final void Function(int pageNumber) onOpenPage;

  @override
  Widget build(BuildContext context) {
    final PdfDocument? document = this.document;
    if (document == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final int pageCount = document.pages.length;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.66,
      ),
      itemCount: pageCount,
      itemBuilder: (BuildContext context, int index) {
        final int pageNumber = index + 1;
        final bool selected = pageNumber == currentPage;
        return InkWell(
          onTap: () => onOpenPage(pageNumber),
          child: Column(
            children: <Widget>[
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: selected ? scheme.primary : scheme.outlineVariant,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: PdfPageView(
                    document: document,
                    pageNumber: pageNumber,
                    maximumDpi: 72,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text('$pageNumber', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        );
      },
    );
  }
}
