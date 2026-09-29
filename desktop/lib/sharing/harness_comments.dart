import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../terminal/terminal_text.dart';
import '../widgets/terminal_text_action.dart';
import '../ws/ws_conn.dart';

typedef CommentAction = Future<Map<String, dynamic>> Function(
  String action,
  Map<String, dynamic> payload,
);

/// One discussion UI for the owner and observers. Authorization is always repeated by the owner.
class HarnessComments extends StatefulWidget {
  const HarnessComments({
    super.key,
    required this.manage,
    this.updates,
    this.onSignIn,
  });
  final CommentAction manage;
  final Listenable? updates;
  final VoidCallback? onSignIn;
  @override
  State<HarnessComments> createState() => _HarnessCommentsState();
}

class _HarnessCommentsState extends State<HarnessComments> {
  final _text = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true, _refreshing = false, _busy = false, _canComment = false;
  int _revision = 0;
  String? _error, _postId, _postText;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.updates?.addListener(_refresh);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void didUpdateWidget(HarnessComments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updates != widget.updates) {
      oldWidget.updates?.removeListener(_refresh);
      widget.updates?.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.updates?.removeListener(_refresh);
    _text.dispose();
    super.dispose();
  }

  String _message(Object error) =>
      error is WsRequestFailure && error.detail != null
      ? error.detail!
      : 'Could not reach the owner. Your draft is saved here; try again.';
  void _accept(Map<String, dynamic> data) {
    if (data['error'] != null) {
      throw WsRequestFailure(
        responseType: 'comments',
        code: '${data['error']}',
        detail: data['detail'] as String?,
      );
    }
    _comments = [
      for (final c in data['comments'] as List? ?? [])
        Map<String, dynamic>.from(c as Map),
    ];
    _canComment = data['canComment'] == true;
    _loading = false;
  }

  void _refresh() {
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_refreshing || _busy) return;
    _refreshing = true;
    final revision = _revision;
    try {
      final data = await widget.manage('comments', {});
      if (mounted && revision == _revision) {
        setState(() {
          _accept(data);
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() {
          _loading = false;
          _error = _message(error);
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  static String _uuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _act(String action, Map<String, dynamic> payload) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _revision++;
      _error = null;
    });
    try {
      final data = await widget.manage(action, payload);
      if (mounted) {
        setState(() {
          _accept(data);
          if (action == 'comment_post') {
            _text.clear();
            _postId = null;
            _postText = null;
          }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _post() {
    final text = _text.text.trim();
    if (text.isEmpty || !_canComment || _busy) return;
    if (_postText != text) {
      _postText = text;
      _postId = _uuid();
    }
    unawaited(_act('comment_post', {'id': _postId, 'text': text}));
  }

  @override
  Widget build(BuildContext context) {
    final cell = terminalCellSizeOf(context);
    final style = terminalContentStyle(
      color: DefaultTextStyle.of(context).style.color,
    );
    return DefaultTextStyle(
      style: style,
      child: Padding(
        padding: EdgeInsets.all(cell.width * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Comments${_comments.isEmpty ? '' : ' (${_comments.length})'}',
            ),
            SizedBox(height: cell.height),
            Expanded(
              child: _loading
                  ? const Text('Loading comments…')
                  : _comments.isEmpty
                  ? const Text('Start the conversation.')
                  : ListView.separated(
                      itemCount: _comments.length,
                      separatorBuilder: (_, _) => SizedBox(height: cell.height),
                      itemBuilder: (context, index) {
                        final c = _comments[index];
                        final date = DateTime.tryParse('${c['createdAt']}')
                            ?.toLocal();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${c['authorName']}',
                                    overflow: TextOverflow.ellipsis,
                                    style: style.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (date != null)
                                  Text(
                                    '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                                  ),
                                if (c['canDelete'] == true)
                                  TerminalTextAction(
                                    label: 'Remove',
                                    onPressed: _busy
                                        ? null
                                        : () => _act('comment_remove', {
                                            'id': c['id'],
                                          }),
                                  ),
                              ],
                            ),
                            SelectionArea(
                              child: Text('${c['text']}', style: style),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            SizedBox(height: cell.height),
            if (_canComment) ...[
              TextField(
                key: const Key('comment-input'),
                controller: _text,
                readOnly: _busy,
                style: style,
                minLines: 1,
                maxLines: 3,
                maxLength: 4000,
                decoration: InputDecoration(
                  hintText: 'Leave a comment…',
                  hintStyle: style,
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TerminalTextAction(
                  label: _busy ? 'Saving…' : 'Comment',
                  onPressed: _busy || _text.text.trim().isEmpty ? null : _post,
                ),
              ),
            ] else if (widget.onSignIn != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TerminalTextAction(
                  label: 'Sign in to comment',
                  onPressed: widget.onSignIn,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
