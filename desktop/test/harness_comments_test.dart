import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/sharing/harness_comments.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;

void main() {
  Future<void> show(
    WidgetTester tester,
    CommentAction manage, {
    VoidCallback? signIn,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: grid.buildAppTheme(brightness: Brightness.dark),
      home: Scaffold(
        body: HarnessComments(manage: manage, onSignIn: signIn),
      ),
    ),
  );

  testWidgets('public guests can read and sign in but cannot post', (
    tester,
  ) async {
    var signIns = 0;
    await show(
      tester,
      (_, _) async => {
        'canComment': false,
        'comments': [
          {
            'id': 'one',
            'authorName': 'Alice',
            'text': 'Looks good 👋',
            'canDelete': false,
          },
        ],
      },
      signIn: () => signIns++,
    );
    await tester.pump();
    expect(find.text('Looks good 👋'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('[ Remove ]'), findsNothing);
    await tester.tap(find.text('[ Sign in to comment ]'));
    expect(signIns, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'failed posting retains the draft and id; retry, broadcast refresh and removal work',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      var comments = <Map<String, dynamic>>[];
      var fail = true;
      await show(tester, (action, payload) async {
        if (action == 'comment_post') {
          requests.add(payload);
          if (fail) {
            fail = false;
            throw StateError('offline');
          }
          comments = [
            {
              'id': payload['id'],
              'authorName': 'Alice',
              'text': payload['text'],
              'canDelete': true,
            },
          ];
        }
        if (action == 'comment_remove') comments = [];
        return {'canComment': true, 'comments': comments};
      });
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('comment-input')),
        'Hello team',
      );
      await tester.pump();
      await tester.tap(find.text('[ Comment ]'));
      await tester.pump();
      expect(find.textContaining('Your draft is saved'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Hello team',
      );
      await tester.tap(find.text('[ Comment ]'));
      await tester.pump();
      expect(requests, hasLength(2));
      expect(requests[0]['id'], requests[1]['id']);
      expect(find.text('Hello team'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.tap(find.text('[ Remove ]'));
      await tester.pump();
      expect(find.text('Hello team'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
