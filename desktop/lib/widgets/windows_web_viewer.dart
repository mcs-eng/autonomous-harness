import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

/// The Windows viewer owns its native surface for exactly as long as its pane.
/// No host objects, filesystem mappings, or page-to-app command bridge are added.
class WindowsWebViewer extends StatefulWidget {
  const WindowsWebViewer({
    super.key,
    required this.uri,
    required this.brightness,
    required this.backgroundColor,
    required this.reload,
    required this.fallbackBuilder,
  });

  final Uri uri;
  final Brightness brightness;
  final Color backgroundColor;
  final int reload;
  final Widget Function(String title, String detail, VoidCallback retry)
  fallbackBuilder;

  @override
  State<WindowsWebViewer> createState() => _WindowsWebViewerState();
}

class _WindowsWebViewerState extends State<WindowsWebViewer> {
  WebviewController? _controller;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  int _generation = 0;
  bool _ready = false;
  bool _loading = true;
  String? _failure;
  String _failureTitle = 'Viewer unavailable';
  String? _downloadNotice;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  bool _current(int generation) => mounted && generation == _generation;

  Future<void> _release() async {
    final controller = _controller;
    _controller = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    try {
      await controller?.dispose();
    } catch (_) {
      // Closing a pane must remain possible even after a native engine failure.
    }
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    await _release();
    if (!_current(generation)) return;
    setState(() {
      _ready = false;
      _loading = true;
      _failure = null;
      _downloadNotice = null;
    });
    try {
      if (await WebviewController.getWebViewVersion() == null) {
        if (!_current(generation)) return;
        _fail(
          'Microsoft Edge WebView2 Runtime is missing. Install it, then '
          'retry, or open this viewer in your browser.',
        );
        return;
      }
      if (!_current(generation)) return;
      final controller = _controller = WebviewController();
      await controller.initialize();
      if (!_current(generation)) return;
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await controller.setDefaultContextMenusEnabled(true);
      await controller.setBackgroundColor(widget.backgroundColor);
      if (!_current(generation)) return;
      _subscriptions.addAll([
        controller.loadingState.listen((state) {
          if (!_current(generation)) return;
          setState(() {
            _loading = state == LoadingState.loading;
            if (_loading) _failure = null;
          });
          if (state == LoadingState.navigationCompleted) _stampTheme();
        }),
        controller.onLoadError.listen((error) {
          if (!_current(generation) ||
              error == WebErrorStatus.operationCanceled) {
            return;
          }
          _fail(
            'The page could not be loaded. Check that its harness is '
            'running, then retry.',
            title: 'Waiting for the viewer',
          );
        }),
        controller.onDownloadEvent.listen((event) {
          if (!_current(generation)) return;
          if (event.kind == WebviewDownloadEventKind.downloadStarted ||
              event.kind == WebviewDownloadEventKind.downloadCompleted) {
            setState(() {
              _downloadNotice =
                  event.kind == WebviewDownloadEventKind.downloadStarted
                  ? 'The embedded browser is downloading a file…'
                  : 'The embedded browser saved your download.';
            });
          }
        }),
      ]);
      setState(() => _ready = true);
      // Mount the widget (including its permission handler) before navigating.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_current(generation)) unawaited(_navigate());
      });
    } catch (_) {
      if (!_current(generation)) return;
      _fail(
        'The embedded browser could not start. Retry or open this viewer '
        'in your browser.',
      );
    }
  }

  void _fail(String detail, {String title = 'Viewer unavailable'}) {
    setState(() {
      _loading = false;
      _failure = detail;
      _failureTitle = title;
    });
  }

  Future<void> _navigate() async {
    final controller = _controller;
    if (!_ready || controller == null) return;
    final generation = _generation;
    final uri = widget.uri;
    setState(() {
      _loading = true;
      _failure = null;
      _downloadNotice = null;
    });
    try {
      // Reopening the pane URL also recovers from an off-page navigation.
      await controller.loadUrl(uri.toString());
    } catch (_) {
      if (_current(generation) && widget.uri == uri) {
        _fail(
          'The page could not be loaded. Retry or open it in your browser.',
        );
      }
    }
  }

  void _stampTheme() {
    if (!_ready) return;
    final theme = widget.brightness == Brightness.dark ? 'dark' : 'light';
    unawaited(
      _controller
          ?.executeScript(
            "document.documentElement.setAttribute('data-theme','$theme')",
          )
          .catchError((_) => null),
    );
  }

  void _retry() => unawaited(_ready ? _navigate() : _initialize());

  @override
  void didUpdateWidget(WindowsWebViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.uri != oldWidget.uri || widget.reload != oldWidget.reload) {
      // Never navigate from an update before Webview.initState has installed
      // its permission handler. An initialization in flight loads the latest URL.
      final generation = _generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_current(generation) && (_ready || !_loading)) _retry();
      });
    } else if (widget.brightness != oldWidget.brightness) {
      _stampTheme();
    }
  }

  @override
  void dispose() {
    ++_generation;
    unawaited(_release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (_ready)
        Webview(
          _controller!,
          permissionRequested: (_, _, _) => WebviewPermissionDecision.deny,
        ),
      if (_failure != null)
        ColoredBox(
          color: widget.backgroundColor,
          child: widget.fallbackBuilder(_failureTitle, _failure!, _retry),
        )
      else if (_loading)
        const Align(
          alignment: Alignment.topCenter,
          child: LinearProgressIndicator(minHeight: 2),
        ),
      if (_downloadNotice != null && _failure == null)
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: widget.backgroundColor,
            child: ListTile(
              dense: true,
              title: Text(_downloadNotice!),
              trailing: IconButton(
                tooltip: 'Dismiss download notice',
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => setState(() => _downloadNotice = null),
              ),
            ),
          ),
        ),
    ],
  );
}
