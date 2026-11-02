import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/model/settings/display_copy_button.dart';
import 'package:open_authenticator/model/settings/storage_type.dart';
import 'package:open_authenticator/model/settings/theme.dart';
import 'package:open_authenticator/utils/platform.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

/// The prefix upstream puts before every key in debug builds, which tests run as.
const String _prefix = 'flutterDebug.';

void main() {
  late Platform platform;

  setUp(() {
    platform = currentPlatform;
    // Android reads the platform-agnostic preferences, which the in-memory store replaces.
    currentPlatform = .android;
  });

  tearDown(() => currentPlatform = platform);

  /// Replaces the preferences with [data], and returns a fresh container.
  ProviderContainer containerWith(Map<String, Object> data) {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData(data);
    ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  /// Reads what is stored under [key], prefix included.
  Future<Object?> stored(String key) async =>
      (await SharedPreferencesAsyncPlatform.instance!.getPreferences(const GetPreferencesParameters(filter: PreferencesFilters()), const SharedPreferencesOptions()))[key];

  group('SettingsEntry', () {
    test('returns the default value while nothing is stored', () async {
      ProviderContainer container = containerWith({});

      expect(await container.read(displayCopyButtonSettingsEntryProvider.future), isTrue);
    });

    test('reads the stored value, under the prefixed key', () async {
      ProviderContainer container = containerWith({'${_prefix}displayCopyButton': false});

      expect(await container.read(displayCopyButtonSettingsEntryProvider.future), isFalse);
    });

    test('saves a new value, which a fresh start reads back', () async {
      ProviderContainer container = containerWith({});
      container.listen(displayCopyButtonSettingsEntryProvider, (previous, next) {});
      await container.read(displayCopyButtonSettingsEntryProvider.future);

      await container.read(displayCopyButtonSettingsEntryProvider.notifier).changeValue(false);

      expect(container.read(displayCopyButtonSettingsEntryProvider).value, isFalse);
      expect(await stored('${_prefix}displayCopyButton'), isFalse);
      ProviderContainer restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      expect(await restarted.read(displayCopyButtonSettingsEntryProvider.future), isFalse);
    });
  });

  group('EnumSettingsEntry', () {
    test('stores an enum by its name', () async {
      ProviderContainer container = containerWith({});
      container.listen(themeSettingsEntryProvider, (previous, next) {});
      await container.read(themeSettingsEntryProvider.future);

      await container.read(themeSettingsEntryProvider.notifier).changeValue(ThemeMode.dark);

      expect(await stored('${_prefix}theme'), 'dark');
    });

    test('falls back to the default on an unknown stored name', () async {
      ProviderContainer container = containerWith({'${_prefix}theme': 'sepia', '${_prefix}storageType': 'shared'});

      expect(await container.read(themeSettingsEntryProvider.future), ThemeMode.system);
      expect(await container.read(storageTypeSettingsEntryProvider.future), StorageType.shared);
    });

    test('keeps TOTPs on this device by default', () async {
      ProviderContainer container = containerWith({});

      expect(await container.read(storageTypeSettingsEntryProvider.future), StorageType.localOnly);
    });
  });
}
