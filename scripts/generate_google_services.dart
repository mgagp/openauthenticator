// Writes the gitignored Firebase client files from the options in the upstream-tracked
// lib/model/migrator/firebase_options.dart: android/app/google-services.json (the Google Services
// Gradle plugin refuses to build without it) and ios/Runner/GoogleService-Info.plist and
// macos/Runner/GoogleService-Info.plist (both Xcode projects list them as resources, so Xcode
// refuses to build without them). Upstream keeps these files out of the repository.
//
// Usage (from the repository root): scripts/with-env.sh dart scripts/generate_google_services.dart
import 'dart:convert';
import 'dart:io';

/// The Android application id declared in android/app/build.gradle.kts.
const String packageName = 'app.openauthenticator';

void main() {
  File optionsFile = File('lib/model/migrator/firebase_options.dart');
  if (!optionsFile.existsSync()) {
    stderr.writeln('error: ${optionsFile.path} not found; run from the repository root.');
    exit(1);
  }
  String source = optionsFile.readAsStringSync();
  writeGoogleServicesJson(readOptions(source, 'android', ['apiKey', 'appId', 'messagingSenderId', 'projectId', 'storageBucket']));
  for (String platform in ['ios', 'macos']) {
    writeGoogleServiceInfoPlist(platform, readOptions(source, platform, ['apiKey', 'appId', 'messagingSenderId', 'projectId', 'storageBucket', 'iosBundleId']));
  }
}

/// Reads the [platform] block of firebase_options.dart, and checks it has every [required] field.
Map<String, String> readOptions(String source, String platform, List<String> required) {
  RegExpMatch? block = RegExp('static const FirebaseOptions $platform = FirebaseOptions\\(([^)]*)\\)').firstMatch(source);
  if (block == null) {
    stderr.writeln('error: no $platform FirebaseOptions found.');
    exit(1);
  }
  Map<String, String> options = {
    for (RegExpMatch field in RegExp(r"(\w+): '([^']*)'").allMatches(block.group(1)!)) field.group(1)!: field.group(2)!,
  };
  for (String key in required) {
    if (!options.containsKey(key)) {
      stderr.writeln('error: $platform FirebaseOptions has no $key.');
      exit(1);
    }
  }
  return options;
}

/// Writes android/app/google-services.json.
void writeGoogleServicesJson(Map<String, String> options) {
  Map<String, Object> googleServices = {
    'project_info': {
      'project_number': options['messagingSenderId']!,
      'project_id': options['projectId']!,
      'storage_bucket': options['storageBucket']!,
    },
    'client': [
      {
        'client_info': {
          'mobilesdk_app_id': options['appId']!,
          'android_client_info': {'package_name': packageName},
        },
        'oauth_client': [],
        'api_key': [
          {'current_key': options['apiKey']!},
        ],
        'services': {
          'appinvite_service': {'other_platform_oauth_client': []},
        },
      },
    ],
    'configuration_version': '1',
  };
  File output = File('android/app/google-services.json');
  output.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(googleServices)}\n');
  stdout.writeln('Wrote ${output.path} (project ${options['projectId']}, package $packageName).');
}

/// Writes <platform>/Runner/GoogleService-Info.plist, in the format the Firebase console downloads.
void writeGoogleServiceInfoPlist(String platform, Map<String, String> options) {
  Map<String, Object> values = {
    'API_KEY': options['apiKey']!,
    'GCM_SENDER_ID': options['messagingSenderId']!,
    'PLIST_VERSION': '1',
    'BUNDLE_ID': options['iosBundleId']!,
    'PROJECT_ID': options['projectId']!,
    'STORAGE_BUCKET': options['storageBucket']!,
    'IS_ADS_ENABLED': false,
    'IS_ANALYTICS_ENABLED': false,
    'IS_APPINVITE_ENABLED': true,
    'IS_GCM_ENABLED': true,
    'IS_SIGNIN_ENABLED': true,
    'GOOGLE_APP_ID': options['appId']!,
  };
  StringBuffer plist = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">')
    ..writeln('<plist version="1.0">')
    ..writeln('<dict>');
  values.forEach((key, value) {
    plist.writeln('\t<key>$key</key>');
    plist.writeln(value is bool ? '\t<${value ? 'true' : 'false'}/>' : '\t<string>${const HtmlEscape().convert(value as String)}</string>');
  });
  plist
    ..writeln('</dict>')
    ..writeln('</plist>');
  File output = File('$platform/Runner/GoogleService-Info.plist');
  output.writeAsStringSync(plist.toString());
  stdout.writeln('Wrote ${output.path} (project ${options['projectId']}, bundle ${options['iosBundleId']}).');
}
