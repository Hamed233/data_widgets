import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class CollectionColumn<T> extends StatelessWidget {
  const CollectionColumn({
    super.key,
    required this.source,
    required this.builder,
    required this.onChange,
    this.actions = const [CollectionAction.move, CollectionAction.delete],
  });

  final List<T> source;

  final Widget Function(BuildContext, T, {bool dragging}) builder;

  final ValueChanged<List<T>> onChange;

  final List<CollectionAction> actions;

  @override
  Widget build(BuildContext context) {
    return CollectionFlex<T>(
      source: source,
      builder: builder,
      onChange: onChange,
      actions: actions,
      direction: Axis.vertical,
    );
  }
}

class CollectionRow<T> extends StatelessWidget {
  const CollectionRow({
    super.key,
    required this.source,
    required this.builder,
    required this.onChange,
    this.actions = const [CollectionAction.move, CollectionAction.delete],
  });

  final List<T> source;

  final Widget Function(BuildContext, T, {bool dragging}) builder;

  final ValueChanged<List<T>> onChange;

  final List<CollectionAction> actions;

  @override
  Widget build(BuildContext context) {
    return CollectionFlex<T>(
      source: source,
      builder: builder,
      onChange: onChange,
      actions: actions,
      direction: Axis.horizontal,
    );
  }
}

/// A ListView that provides collection manipulation capabilities and reports visible items
class CollectionListView<T> extends StatefulWidget {
  const CollectionListView({
    super.key,
    required this.source,
    required this.builder,
    required this.onChange,
    this.onVisibleChanged,
    this.keyBuilder,
    this.actions = const [CollectionAction.move, CollectionAction.delete],
  });

  /// The data source to be displayed and manipulated
  final List<T> source;

  /// Builder function to create widgets for each item
  final Widget Function(BuildContext, T, {bool dragging}) builder;

  /// Callback when the collection is modified
  final ValueChanged<List<T>> onChange;

  /// Callback that reports which items are currently visible in the viewport
  final ValueChanged<List<Key>>? onVisibleChanged;

  /// Available actions for this collection
  final List<CollectionAction> actions;

  /// Optional function to generate keys for items
  final Key Function(T)? keyBuilder;

  @override
  State<CollectionListView> createState() => _CollectionListViewState<T>();
}

class _CollectionListViewState<T> extends State<CollectionListView<T>> {
  final ScrollController _scrollController = ScrollController();
  final Set<Key> _visibleKeys = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_checkVisibleItems);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibleItems());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_checkVisibleItems);
    _scrollController.dispose();
    super.dispose();
  }

  void _checkVisibleItems() {
    if (widget.onVisibleChanged == null) return;
    
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final viewportOffset = _scrollController.offset;
    final viewportDimension = _scrollController.position.viewportDimension;
    final visibleRange = Rect.fromLTWH(0, viewportOffset, renderBox.size.width, viewportDimension);
    
    Set<Key> newVisibleKeys = {};
    
    for (int i = 0; i < widget.source.length; i++) {
      final key = widget.keyBuilder?.call(widget.source[i]) ?? ValueKey(widget.source[i]);
      final childContext = (key as GlobalKey).currentContext;
      
      if (childContext != null) {
        final childRenderBox = childContext.findRenderObject() as RenderBox?;
        if (childRenderBox != null && childRenderBox.hasSize) {
          final childRect = Rect.fromLTWH(
            0, 
            childRenderBox.localToGlobal(Offset.zero).dy - renderBox.localToGlobal(Offset.zero).dy,
            childRenderBox.size.width,
            childRenderBox.size.height,
          );
          
          if (visibleRange.overlaps(childRect)) {
            newVisibleKeys.add(key);
          }
        }
      }
    }
    
    if (!setEquals(_visibleKeys, newVisibleKeys)) {
      _visibleKeys.clear();
      _visibleKeys.addAll(newVisibleKeys);
      widget.onVisibleChanged?.call(_visibleKeys.toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      scrollController: _scrollController,
      itemCount: widget.source.length,
      onReorder: (oldIndex, newIndex) {
        widget.onChange(_reorder(widget.source, newIndex, oldIndex));
      },
      itemBuilder: (context, index) {
        final item = widget.source[index];
        final key = widget.keyBuilder?.call(item) ?? ValueKey(item);
        
        return Dismissible(
          key: key,
          direction: widget.actions.contains(CollectionAction.delete) 
              ? DismissDirection.horizontal 
              : DismissDirection.none,
          onDismissed: (_) {
            final newList = List<T>.from(widget.source);
            newList.removeAt(index);
            widget.onChange(newList);
          },
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          secondaryBackground: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          child: widget.builder(context, item, dragging: false),
        );
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Material(
              elevation: 4.0 * animation.value,
              child: widget.builder(
                context, 
                widget.source[index],
                dragging: true,
              ),
            );
          },
          child: child,
        );
      },
    );
  }
}

class CollectionFlex<T> extends StatefulWidget {
  const CollectionFlex({
    super.key,
    required this.source,
    required this.builder,
    required this.onChange,
    required this.direction,
    this.keyBuilder,
    this.actions = const [CollectionAction.move, CollectionAction.delete],
  });

  final List<T> source;

  final Widget Function(BuildContext, T, {bool dragging}) builder;

  final ValueChanged<List<T>> onChange;

  final List<CollectionAction> actions;

  final Axis direction;

  final Key Function(T)? keyBuilder;

  @override
  State<CollectionFlex> createState() => _CollectionFlexState<T>();
}

class _CollectionFlexState<T> extends State<CollectionFlex<T>> with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  List<T> _previousSource = [];
  final Map<Key, GlobalKey<AnimatedListState>> _listKeys = {};
  
  @override
  void initState() {
    super.initState();
    _previousSource = List.from(widget.source);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  @override
  void didUpdateWidget(CollectionFlex<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Handle animations when source changes without user interaction
    if (!listEquals(_previousSource, widget.source)) {
      _handleSourceChange(oldWidget.source);
      _previousSource = List.from(widget.source);
    }
  }
  
  void _handleSourceChange(List<T> oldSource) {
    // This would implement animations for add, move, delete
    // For simplicity, we're just setting the state here
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.actions.contains(CollectionAction.delete)
        ? _buildWithSwipeDelete()
        : _buildReorderableList();
  }
  
  Widget _buildWithSwipeDelete() {
    return Flex(
      direction: widget.direction,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < widget.source.length; i++)
          Flexible(
            child: Dismissible(
              key: widget.keyBuilder?.call(widget.source[i]) ?? ValueKey(widget.source[i]),
              direction: DismissDirection.horizontal,
              onDismissed: (_) {
                final newList = List<T>.from(widget.source);
                newList.removeAt(i);
                widget.onChange(newList);
              },
              background: Container(
                color: Colors.red,
                alignment: widget.direction == Axis.horizontal 
                    ? Alignment.topCenter 
                    : Alignment.centerLeft,
                padding: const EdgeInsets.all(16.0),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              secondaryBackground: Container(
                color: Colors.red,
                alignment: widget.direction == Axis.horizontal 
                    ? Alignment.bottomCenter 
                    : Alignment.centerRight,
                padding: const EdgeInsets.all(16.0),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              child: widget.builder(context, widget.source[i], dragging: false),
            ),
          ),
      ],
    );
  }
  
  Widget _buildReorderableList() {
    return ReorderableListView(
      shrinkWrap: true,
      scrollDirection: widget.direction,
      physics: const NeverScrollableScrollPhysics(),
      onReorder: (oldIndex, newIndex) {
        widget.onChange(_reorder(widget.source, newIndex, oldIndex));
      },
      proxyDecorator: (child, index, animation) {
        // Make proxyDecorator minimal but pass dragging state to builder
        return child;
      },
      children: [
        for (final x in widget.source)
          Builder(
            key: widget.keyBuilder?.call(x) ?? ValueKey(x),
            builder: (context) {
              return widget.builder(context, x, dragging: false);
            },
          ),
      ],
    );
  }
}

enum CollectionAction {
  move,
  delete,
}

List<T> _reorder<T>(List<T> source, int newIndex, int oldIndex) {
  if (newIndex > oldIndex) {
    newIndex -= 1;
  }
  final items = List<T>.from(source);
  final item = items.removeAt(oldIndex);
  items.insert(newIndex, item);
  return items;
}
