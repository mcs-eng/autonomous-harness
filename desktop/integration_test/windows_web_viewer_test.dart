// Real WebView2, served only fictional local HTML. No Harness home or daemon.
// Run: flutter test integration_test/windows_web_viewer_test.dart -d windows
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/widgets/windows_web_viewer.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows viewer renders, retargets, reloads and releases its page',
    (tester) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) async {
        ++requests;
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '<!doctype html><html><body style="background:#182126;color:white">'
          '<h1>Viewer fixture ${request.uri.path}</h1><input id="input" aria-label="Viewer input">'
          '</body></html>',
        );
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      Future<void> mount(String path, {int reload = 0}) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WindowsWebViewer(
              uri: Uri.parse('http://127.0.0.1:${server.port}/$path'),
              brightness: Brightness.dark,
              backgroundColor: Colors.black,
              reload: reload,
              fallbackBuilder: (title, detail, retry) =>
                  Text('$title: $detail'),
            ),
          ),
        ),
      );
      Future<WebviewController> waitFor(String path) async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.byType(Webview).evaluate().isEmpty) {
            continue;
          }
          final controller = tester
              .widget<Webview>(find.byType(Webview))
              .controller;
          final content = await controller.executeScript(
            'document.body.innerText',
          );
          if (content.toString().contains('Viewer fixture /$path')) {
            return controller;
          }
        }
        fail('Native viewer did not render $path');
      }

      await mount('first');
      final first = await waitFor('first');
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        await first.executeScript(
          "document.documentElement.getAttribute('data-theme')",
        ),
        'dark',
      );
      await mount('second');
      final second = await waitFor('second');
      expect(identical(first, second), isTrue);
      final beforeReload = requests;
      await mount('second', reload: 1);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (requests == beforeReload && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(requests, greaterThan(beforeReload));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    },
    skip: !Platform.isWindows,
  );
}
