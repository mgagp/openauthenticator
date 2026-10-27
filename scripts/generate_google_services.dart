// Writes the gitignored android/app/google-services.json from the Android options in the
// upstream-tracked lib/model/migrator/firebase_options.dart. The Google Services Gradle plugin
// refuses to build without that file; upstream keeps it out of the repository.
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
  RegExpMatch? block = RegExp(r'static const FirebaseOptions android = FirebaseOptions\(([^)]*)\)').firstMatch(optionsFile.readAsStringSync());
  if (block == null) {
    stderr.writeln('error: no Android FirebaseOptions found in ${optionsFile.path}.');
    exit(1);
  }
  Map<String, String> options = {
    for (RegExpMatch field in RegExp(r"(\w+): '([^']*)'").allMatches(block.group(1)!)) field.group(1)!: field.group(2)!,
  };
  for (String key in ['apiKey', 'appId', 'messagingSenderId', 'projectId', 'storageBucket']) {
    if (!options.containsKey(key)) {
      stderr.writeln('error: Android FirebaseOptions has no $key.');
      exit(1);
    }
  }
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
