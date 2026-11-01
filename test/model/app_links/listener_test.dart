import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/model/app_links/listener.dart';

// Characterization tests (#55): they pin upstream's link listener as it is today, before EzKey links are
// routed (harmonization H8). The listener does not filter: every link reaches its state, and the app's
// route widget (private, in `main.dart`) then handles only `openauthenticator://` and `otpauth://totp/`
// links, once each. That routing cannot be reached without the whole app, so it is not tested here.

/// The plugin's method channel (initial link).
const MethodChannel _methodChannel = MethodChannel('com.llfbandit.app_links/messages');

/// The plugin's event channel (links received while the app runs).
const EventChannel _eventChannel = EventChannel('com.llfbandit.app_links/events');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessenger messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  String? initialLink;
  MockStreamHandlerEventSink? events;
  late ProviderContainer container;

  setUp(() {
    initialLink = null;
    events = null;
    messenger.setMockMethodCallHandler(_methodChannel, (call) async => call.method == 'getInitialLink' ? initialLink : null);
    messenger.setMockStreamHandler(
      _eventChannel,
      MockStreamHandler.inline(
        onListen: (arguments, sink) => events = sink,
        onCancel: (arguments) => events = null,
      ),
    );
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
    messenger.setMockMethodCallHandler(_methodChannel, null);
    messenger.setMockStreamHandler(_eventChannel, null);
  });

  group('AppLinksListener', () {
    test('starts with the link that opened the app', () async {
      initialLink = 'otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP';

      Uri? uri = await container.read(appLinksListenerProvider.future);

      expect(uri, Uri.parse('otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP'));
    });

    test('starts with no link when the app was opened normally', () async {
      Uri? uri = await container.read(appLinksListenerProvider.future);

      expect(uri, isNull);
    });

    test('takes each link received while the app runs', () async {
      await container.read(appLinksListenerProvider.future);

      events!.success('openauthenticator://purchases/success');
      await pumpEventQueue();

      expect(container.read(appLinksListenerProvider).value, Uri.parse('openauthenticator://purchases/success'));
    });

    test('takes a manually provided link', () async {
      await container.read(appLinksListenerProvider.future);

      container.read(appLinksListenerProvider.notifier).provideLink(Uri.parse('openauthenticator://auth/provider/google'));

      expect(container.read(appLinksListenerProvider).value, Uri.parse('openauthenticator://auth/provider/google'));
    });

    test('takes a link of any other scheme as is: the route widget ignores it afterwards', () async {
      await container.read(appLinksListenerProvider.future);

      events!.success('ezkey://invitation?code=abc');
      await pumpEventQueue();

      expect(container.read(appLinksListenerProvider).value, Uri.parse('ezkey://invitation?code=abc'));
    });
  });

  group('AppLinksListener.consumeLink', () {
    test('returns true the first time a link is consumed, then false', () async {
      await container.read(appLinksListenerProvider.future);
      AppLinksListener listener = container.read(appLinksListenerProvider.notifier);
      Uri uri = Uri.parse('openauthenticator://purchases/success');

      bool first = listener.consumeLink(uri);
      bool second = listener.consumeLink(Uri.parse('openauthenticator://purchases/success'));

      expect(first, isTrue);
      expect(second, isFalse);
    });

    test('compares links by their text, so a reordered query counts as another link', () async {
      await container.read(appLinksListenerProvider.future);
      AppLinksListener listener = container.read(appLinksListenerProvider.notifier);

      listener.consumeLink(Uri.parse('otpauth://totp/alice?secret=S&issuer=Orbit'));

      expect(listener.consumeLink(Uri.parse('otpauth://totp/alice?issuer=Orbit&secret=S')), isTrue);
    });

    test('remembers the consumed links when the listener is rebuilt, so the initial link is not handled twice', () async {
      initialLink = 'openauthenticator://purchases/success';
      Uri uri = (await container.read(appLinksListenerProvider.future))!;
      container.read(appLinksListenerProvider.notifier).consumeLink(uri);

      container.invalidate(appLinksListenerProvider);
      Uri? rebuilt = await container.read(appLinksListenerProvider.future);

      expect(rebuilt, uri);
      expect(container.read(appLinksListenerProvider.notifier).consumeLink(uri), isFalse);
    });
  });
}
