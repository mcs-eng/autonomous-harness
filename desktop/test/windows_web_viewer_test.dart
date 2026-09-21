import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/widgets/windows_web_viewer.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const plugin = MethodChannel('io.jns.webview.win');
  const native = MethodChannel('io.jns.webview.win/1');
  const events = MethodChannel('io.jns.webview.win/1/events');
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String? version;
  Completer<Map<String, int>>? initialization;

  Future<void> event(String type, Object value) async {
    await messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'type': type,
        'value': value,
      }),
      (_) {},
    );
  }

  Future<void> mount(
    WidgetTester tester, {
    String path = '/first',
    int reload = 0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 600,
          height: 400,
          child: WindowsWebViewer(
            uri: Uri.parse('http://127.0.0.1:1234$path'),
            brightness: Brightness.dark,
            backgroundColor: Colors.black,
            reload: reload,
            fallbackBuilder: (title, detail, retry) => Column(
              children: [
                Text(title),
                Text(detail),
                TextButton(onPressed: retry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  setUp(() {
    version = '123.0';
    initialization = null;
    calls.clear();
    messenger.setMockMethodCallHandler(plugin, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getWebViewVersion':
          return version;
        case 'initialize':
          return initialization == null
              ? {'textureId': 1}
              : await initialization!.future;
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(events, (_) async => null);
  });

  tearDown(() {
    for (final channel in [plugin, native, events]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets(
    'missing runtime offers recovery without creating a native view',
    (tester) async {
      version = null;
      await mount(tester);
      expect(
        find.textContaining('WebView2 Runtime is missing'),
        findsOneWidget,
      );
      expect(calls.where((call) => call.method == 'initialize'), isEmpty);
      version = '123.0';
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byType(Webview), findsOneWidget);
      expect(
        calls.where((call) => call.method == 'loadUrl').last.arguments,
        endsWith('/first'),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    },
  );

  testWidgets(
    'loads latest URL after initialization and denies browser permissions',
    (tester) async {
      initialization = Completer<Map<String, int>>();
      await mount(tester);
      await mount(tester, path: '/latest');
      initialization!.complete({'textureId': 1});
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(calls.where((call) => call.method == 'initialize'), hasLength(1));
      expect(
        calls.where((call) => call.method == 'loadUrl').map((c) => c.arguments),
        everyElement('http://127.0.0.1:1234/latest'),
      );
      final view = tester.widget<Webview>(find.byType(Webview));
      for (final permission in WebviewPermissionKind.values) {
        expect(
          await view.permissionRequested!('http://127.0.0.1', permission, true),
          WebviewPermissionDecision.deny,
        );
      }
      expect(
        calls
            .where((call) => call.method == 'setPopupWindowPolicy')
            .single
            .arguments,
        WebviewPopupWindowPolicy.deny.index,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    },
  );

  testWidgets(
    'load failures retry, theme stamps, and canceled loads stay quiet',
    (tester) async {
      await mount(tester);
      await event('onLoadError', WebErrorStatus.cannotConnect.index);
      await tester.pump();
      expect(find.text('Waiting for the viewer'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await event('onLoadError', WebErrorStatus.operationCanceled.index);
      await event(
        'loadingStateChanged',
        LoadingState.navigationCompleted.index,
      );
      await tester.pump();
      expect(find.text('Waiting for the viewer'), findsNothing);
      expect(calls.where((call) => call.method == 'loadUrl'), hasLength(2));
      expect(
        calls.where((call) => call.method == 'executeScript').last.arguments,
        contains("'data-theme','dark'"),
      );
      await mount(tester, path: '/next', reload: 1);
      expect(
        calls.where((call) => call.method == 'loadUrl').last.arguments,
        endsWith('/next'),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(calls.where((call) => call.method == 'dispose'), hasLength(1));
    },
  );

  testWidgets(
    'closing during initialization releases the native view without navigation',
    (tester) async {
      initialization = Completer<Map<String, int>>();
      await mount(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      initialization!.complete({'textureId': 1});
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(calls.where((call) => call.method == 'loadUrl'), isEmpty);
      expect(calls.where((call) => call.method == 'dispose'), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
