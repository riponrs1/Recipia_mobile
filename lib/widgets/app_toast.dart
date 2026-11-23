import 'dart:async';
import 'package:flutter/material.dart';

enum AppToastType { success, error, info }

/// Top-floating pill toast that never collides with the keyboard or bottom bars
/// and always auto-dismisses cleanly (even when an Undo action is present).
class AppToast {
  static OverlayEntry? _currentEntry;
  static Timer? _timer;

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }

  static void success(BuildContext context, String message,
      {Duration duration = const Duration(milliseconds: 2600)}) {
    show(context, message, type: AppToastType.success, duration: duration);
  }

  static void error(BuildContext context, String message,
      {Duration duration = const Duration(milliseconds: 3200)}) {
    show(context, message, type: AppToastType.error, duration: duration);
  }

  static void info(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    show(
      context,
      message,
      type: AppToastType.info,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration ??
          Duration(milliseconds: actionLabel != null ? 4200 : 2800),
    );
  }

  static void show(
    BuildContext context,
    String message, {
    AppToastType type = AppToastType.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 2800),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    dismiss();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _TopToastWidget(
        message: message,
        type: type,
        actionLabel: actionLabel,
        onAction: () {
          dismiss();
          onAction?.call();
        },
        onDismiss: dismiss,
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
    _timer = Timer(duration, () {
      if (_currentEntry == entry) dismiss();
    });
  }
}

class _TopToastWidget extends StatefulWidget {
  final String message;
  final AppToastType type;
  final String? actionLabel;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  const _TopToastWidget({
    required this.message,
    required this.type,
    required this.onAction,
    required this.onDismiss,
    this.actionLabel,
  });

  @override
  State<_TopToastWidget> createState() => _TopToastWidgetState();
}

class _TopToastWidgetState extends State<_TopToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ac, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    _ac.forward();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  Color get _bgColor {
    switch (widget.type) {
      case AppToastType.success:
        return const Color(0xFF1F7A45);
      case AppToastType.error:
        return const Color(0xFFC0392B);
      case AppToastType.info:
        return const Color(0xFF1E1916);
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case AppToastType.success:
        return Icons.check_rounded;
      case AppToastType.error:
        return Icons.error_outline_rounded;
      case AppToastType.info:
        return widget.actionLabel != null
            ? Icons.delete_outline_rounded
            : Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top + 10;
    return Positioned(
      top: topPad,
      left: 16,
      right: 16,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _fade,
              child: Dismissible(
                key: ValueKey(widget.message + widget.type.name),
                direction: DismissDirection.up,
                onDismissed: (_) => widget.onDismiss(),
                child: Material(
                  color: Colors.transparent,
                  child: GestureDetector(
                    onTap: widget.actionLabel == null ? widget.onDismiss : null,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
                      decoration: BoxDecoration(
                        color: _bgColor,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x38000000),
                            blurRadius: 22,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(_icon, size: 14, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              widget.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                          ),
                          if (widget.actionLabel != null) ...[
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: widget.onAction,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  widget.actionLabel!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
