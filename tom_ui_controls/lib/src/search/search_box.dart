import 'package:flutter/material.dart';

/// A simple search box widget reusable across editors.
///
/// Shows a text field with search/clear icons, plus optional buttons for
/// navigation (next/previous) and replace functionality.
class SearchBox extends StatefulWidget {
  const SearchBox({
    super.key,
    required this.onSearch,
    this.onReplace,
    this.onNext,
    this.onPrevious,
    this.showReplace = false,
    this.showNavigation = true,
    this.hintText = 'Search…',
    this.matchCount,
    this.currentMatch,
  });

  final ValueChanged<String> onSearch;
  final void Function(String search, String replace)? onReplace;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final bool showReplace;
  final bool showNavigation;
  final String hintText;
  final int? matchCount;
  final int? currentMatch;

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  final _searchController = TextEditingController();
  final _replaceController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon:
                      _searchController.text.isNotEmpty
                          ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              widget.onSearch('');
                            },
                          )
                          : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                style: theme.textTheme.bodySmall,
                onChanged: widget.onSearch,
              ),
            ),
            if (widget.matchCount != null) ...[
              const SizedBox(width: 4),
              Text(
                '${widget.currentMatch ?? 0}/${widget.matchCount}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (widget.showNavigation) ...[
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                onPressed: widget.onPrevious,
                tooltip: 'Previous (Shift+F3)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                onPressed: widget.onNext,
                tooltip: 'Next (F3)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
              ),
            ],
          ],
        ),
        if (widget.showReplace) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _replaceController,
                  decoration: InputDecoration(
                    hintText: 'Replace…',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.find_replace, size: 18),
                onPressed:
                    widget.onReplace != null
                        ? () => widget.onReplace!(
                          _searchController.text,
                          _replaceController.text,
                        )
                        : null,
                tooltip: 'Replace',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
