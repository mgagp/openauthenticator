// Drives a local EzKey clean-start stack for on-device tests (#16): creates enrollment invitations
// for the Open Authenticator lab integration, auth attempts for any enrollment, and runs the
// live-stack test.
//
// Usage (from the repository root, with the stack up):
//   scripts/with-env.sh dart scripts/ezkey_lab.dart invite [--name <enrollment name>]
//   scripts/with-env.sh dart scripts/ezkey_lab.dart attempt <enrollmentId> [--title ...] [--message ...] [--challenge] [--no-wait]
//   scripts/with-env.sh dart scripts/ezkey_lab.dart e2e [--device emulator-5554] [--test integration_test/ezkey/enrollment_ui_test.dart]
//
// Admin API calls need a bearer token: the script logs in as the clean-start administrator and
// approves that login itself through the stack's Demo Device web UI (lab only). The token and one
// API key per integration are cached under the gitignored build/ezkey-lab/ (secrets: never commit or
// print them). Endpoints come from EZKEY_ADMIN_API, EZKEY_INTEGRATION_API and EZKEY_DEMO_DEVICE.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;

/// The lab integration code (created on first use).
const String integrationCode = 'oa-lab';

/// Where cached secrets go.
final Directory stateDirectory = Directory('build/ezkey-lab');

/// The Admin API base URL.
final Uri adminApi = Uri.parse(Platform.environment['EZKEY_ADMIN_API'] ?? 'http://localhost:9080');

/// The Integration API base URL.
final Uri integrationApi = Uri.parse(Platform.environment['EZKEY_INTEGRATION_API'] ?? 'http://localhost:7080');

/// The Demo Device base URL.
final Uri demoDevice = Uri.parse(Platform.environment['EZKEY_DEMO_DEVICE'] ?? 'http://localhost:8083');

/// The clean-start administrator.
final String adminUsername = Platform.environment['EZKEY_ADMIN_USERNAME'] ?? 'admin.docker';

/// The name of the administrator's enrollment on the Demo Device.
final String adminEnrollmentName = Platform.environment['EZKEY_ADMIN_ENROLLMENT_NAME'] ?? 'Admin Docker';

Future<void> main(List<String> arguments) async {
  ArgParser parser = ArgParser()
    ..addCommand('invite', ArgParser()..addOption('name', defaultsTo: 'Open Authenticator lab'))
    ..addCommand(
      'attempt',
      ArgParser()
        ..addOption('title', defaultsTo: 'Sign in to Open Authenticator Lab')
        ..addOption('message', defaultsTo: 'Lab auth attempt from scripts/ezkey_lab.dart')
        ..addFlag('challenge', help: 'Require the user to type the attempt challenge.')
        ..addFlag('wait', defaultsTo: true, help: 'Wait for the device decision.'),
    )
    ..addCommand(
      'e2e',
      ArgParser()
        ..addOption('device', defaultsTo: 'emulator-5554')
        ..addOption('test', defaultsTo: 'integration_test/ezkey/live_stack_test.dart'),
    );
  ArgResults args = parser.parse(arguments);
  ArgResults? command = args.command;
  try {
    switch (command?.name) {
      case 'invite':
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(await invite(command!['name'] as String)));
      case 'attempt':
        int enrollmentId = int.parse(command!.rest.single);
        Map<String, dynamic> attempt = await createAttempt(enrollmentId, title: command['title'] as String, message: command['message'] as String, challenge: command['challenge'] as bool);
        stdout.writeln(jsonEncode({'authAttemptId': attempt['authAttemptId'], 'authAttemptChallenge': attempt['authAttemptChallenge']}));
        if (command['wait'] as bool) {
          stdout.writeln('status: ${await waitForAttempt(attempt)}');
        }
      case 'e2e':
        exit(await e2e(command!['device'] as String, command['test'] as String));
      default:
        stderr.writeln('usage: dart scripts/ezkey_lab.dart <invite|attempt|e2e> ...\n${parser.usage}');
        exit(64);
    }
  } on LabException catch (ex) {
    stderr.writeln('error: ${ex.message}');
    exit(1);
  } finally {
    _client.close();
  }
}

/// Creates an enrollment invitation on the lab integration. Returns the QR code content, the
/// enrollment id and the 6-digit enrollment code.
Future<Map<String, Object>> invite(String name) async {
  int integrationId = await labIntegrationId();
  Map<String, dynamic> created = await adminRequest('POST', '/api/v1/enrollments', {'integrationId': integrationId, 'name': name, 'authAttemptChallengeRequired': false});
  int enrollmentId = created['enrollmentId'] as int;
  Map<String, dynamic> details = await adminRequest('GET', '/api/v1/enrollments/$enrollmentId');
  return {
    'enrollmentId': enrollmentId,
    'enrollmentChallenge': '${created['enrollmentChallenge']}'.padLeft(6, '0'),
    'code': jsonEncode({'enrollmentId': enrollmentId, 'enrollmentProofToken': details['enrollmentProofToken']}),
  };
}

/// Creates an auth attempt for [enrollmentId] through the Integration API, with an API key of the
/// enrollment's own integration. The result also holds that `integrationId`, for [waitForAttempt].
Future<Map<String, dynamic>> createAttempt(int enrollmentId, {required String title, required String message, bool challenge = false}) async {
  int integrationId = (await adminRequest('GET', '/api/v1/enrollments/$enrollmentId'))['integrationId'] as int;
  Map<String, Object?> body = {'enrollmentId': enrollmentId, 'challengeRequested': challenge, 'contextTitle': title, 'contextMessage': message};
  http.Response response = await _send('POST', integrationApi.resolve('/api/v1/auth-attempts'), body, await integrationAuthorization(integrationId));
  if (response.statusCode == 401) {
    // The cached API key belongs to a previous stack (clean start): make a new one.
    response = await _send('POST', integrationApi.resolve('/api/v1/auth-attempts'), body, await integrationAuthorization(integrationId, refresh: true));
  }
  return {..._json(response, 'create auth attempt'), 'integrationId': integrationId};
}

/// Waits until the device decided [attempt] (from [createAttempt]), or it expired, and returns its status.
Future<String> waitForAttempt(Map<String, dynamic> attempt, {Duration timeout = const Duration(seconds: 120)}) async {
  DateTime deadline = DateTime.now().add(timeout);
  while (true) {
    Map<String, dynamic> json = _json(
      await _send('GET', integrationApi.resolve('/api/v1/auth-attempts/${attempt['authAttemptId']}/wait?timeout=20&polling=1'), null, await integrationAuthorization(attempt['integrationId'] as int)),
      'wait for auth attempt',
    );
    String status = json['status'] as String? ?? 'UNKNOWN';
    if (json['completed'] == true || DateTime.now().isAfter(deadline)) {
      return status;
    }
  }
}

/// Runs the live-stack [testPath] on [device]: invites, starts the test, creates the auth attempt
/// once the device has enrolled, and saves a screenshot under build/ezkey-lab/screens/ for each
/// `EZKEY_LAB_SCREEN <name>` line the test prints. Returns the test's exit code.
Future<int> e2e(String device, String testPath) async {
  // Names are unique per integration among active enrollments, so each run gets its own.
  Map<String, Object> invitation = await invite('Open Authenticator e2e ${DateTime.now().toIso8601String().substring(0, 19)}');
  int enrollmentId = invitation['enrollmentId'] as int;
  stdout.writeln('invitation: enrollment $enrollmentId');
  Process test = await Process.start(Platform.isWindows ? 'flutter.bat' : 'flutter', [
    'test',
    testPath,
    '-d',
    device,
    '--dart-define=EZKEY_LAB_ENROLLMENT_CODE=${invitation['code']}',
    '--dart-define=EZKEY_LAB_ENROLLMENT_CHALLENGE=${invitation['enrollmentChallenge']}',
  ]);
  Directory screens = Directory('${stateDirectory.path}/screens')..createSync(recursive: true);
  test.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    stdout.writeln(line);
    RegExpMatch? screen = RegExp(r'EZKEY_LAB_SCREEN (\S+)').firstMatch(line);
    if (screen != null) {
      Process.run('adb', [
        '-s',
        device,
        'exec-out',
        'screencap',
        '-p',
      ], stdoutEncoding: null).then((result) => File('${screens.path}/${screen.group(1)}.png').writeAsBytesSync(result.stdout as List<int>));
    }
  });
  test.stderr.transform(utf8.decoder).listen(stderr.write);
  bool exited = false;
  Future<int> exitCode = test.exitCode.whenComplete(() => exited = true);

  // The build and install take a few minutes; then the device binds and verifies.
  DateTime deadline = DateTime.now().add(const Duration(minutes: 15));
  while (!exited && DateTime.now().isBefore(deadline)) {
    Map<String, dynamic> enrollment = await adminRequest('GET', '/api/v1/enrollments/$enrollmentId');
    if (enrollment['enrollmentStatus'] == 'VERIFIED') {
      Map<String, dynamic> attempt = await createAttempt(enrollmentId, title: 'Sign in to Open Authenticator Lab', message: 'e2e auth attempt');
      stdout.writeln('auth attempt ${attempt['authAttemptId']} created');
      stdout.writeln('auth attempt status: ${await waitForAttempt(attempt)}');
      break;
    }
    await Future.any([exitCode, Future.delayed(const Duration(seconds: 3))]);
  }
  int result = await exitCode;
  // The device only forgets its enrollment locally: revoke it on the server too.
  await adminRequest('POST', '/api/v1/enrollments/$enrollmentId/revoke?reason=${Uri.encodeQueryComponent('ezkey_lab.dart e2e cleanup')}');
  stdout.writeln('enrollment $enrollmentId revoked');
  return result;
}

/// Returns the lab integration id, creating the integration when it does not exist yet.
Future<int> labIntegrationId() async {
  Map<String, dynamic> page = await adminRequest('GET', '/api/v1/integrations?size=100');
  for (Map<String, dynamic> integration in (page['content'] as List).cast<Map<String, dynamic>>()) {
    if (integration['code'] == integrationCode) {
      return integration['id'] as int;
    }
  }
  Map<String, dynamic> created = await adminRequest('POST', '/api/v1/integrations', {
    'code': integrationCode,
    'name': 'Open Authenticator Lab',
    'description': 'Third-party authenticator lab (openauthenticator fork, issue #16)',
  });
  return created['id'] as int;
}

/// Sends an authenticated Admin API request, logging in again once if the cached token is refused.
Future<Map<String, dynamic>> adminRequest(String method, String path, [Object? body]) async {
  http.Response response = await _send(method, adminApi.resolve(path), body, 'Bearer ${await adminToken()}');
  if (response.statusCode == 401) {
    response = await _send(method, adminApi.resolve(path), body, 'Bearer ${await adminToken(refresh: true)}');
  }
  return _json(response, '$method $path');
}

/// Returns a cached Admin API token, or logs in and approves the login on the Demo Device.
Future<String> adminToken({bool refresh = false}) async {
  File cache = File('${stateDirectory.path}/admin-token.json');
  if (!refresh && cache.existsSync()) {
    Map<String, dynamic> cached = jsonDecode(cache.readAsStringSync());
    if (DateTime.parse(cached['expiresAt'] as String).isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return cached['token'] as String;
    }
  }
  Map<String, dynamic> login = _json(await _send('POST', adminApi.resolve('/api/v1/admin/auth/login'), {'username': adminUsername, 'challengeRequested': false, 'nonBlocking': true}), 'admin login');
  if (login['status'] != 'pending') {
    throw LabException('admin login: expected a pending attempt, got ${login['status']}');
  }
  Future<http.Response> wait = _send('POST', adminApi.resolve('/api/v1/admin/auth/passwordless-wait'), {'authAttemptId': login['authAttemptId'], 'waiterSecret': login['waiterSecret']});
  await approveOnDemoDevice(login['authAttemptId'] as int);
  Map<String, dynamic> result = _json(await wait, 'admin passwordless-wait');
  if (result['success'] != true) {
    throw LabException('admin login was not approved (${result['status']})');
  }
  stateDirectory.createSync(recursive: true);
  cache.writeAsStringSync(jsonEncode({'token': result['token'], 'expiresAt': result['expiresAt']}));
  return result['token'] as String;
}

/// Approves [authAttemptId] on the administrator's Demo Device enrollment, through its web form.
Future<void> approveOnDemoDevice(int authAttemptId) async {
  String home = (await _demoDeviceGet('/phone/ezkey')).body;
  RegExpMatch? card = RegExp('data-enrollment-id="(\\d+)">(?:(?!</a>)[\\s\\S])*?<span>${RegExp.escape(adminEnrollmentName)}</span>').firstMatch(home);
  if (card == null) {
    throw LabException('no "$adminEnrollmentName" enrollment on the Demo Device ($demoDevice/phone/ezkey)');
  }
  String authPath = '/phone/ezkey/enrollments/${card.group(1)}/auth';
  // The Demo Device claims the pending attempt when the page is opened; it can take a moment to appear.
  for (int i = 0; i < 20; i++) {
    String page = (await _demoDeviceGet(authPath)).body;
    String? attemptId = RegExp(r'name="authAttemptId" value="(\d+)"').firstMatch(page)?.group(1);
    String? proofToken = RegExp(r'name="authAttemptProofToken" value="([^"]+)"').firstMatch(page)?.group(1);
    if (attemptId == '$authAttemptId' && proofToken != null) {
      http.Response response = await _client.post(
        demoDevice.resolve('$authPath/respond'),
        headers: {'Cookie': _demoDeviceCookie ?? ''},
        body: {'authAttemptId': attemptId, 'authAttemptProofToken': proofToken, 'approved': 'true'},
      );
      if (!response.body.contains('demo-device-result-success')) {
        throw LabException('the Demo Device did not confirm the approval (HTTP ${response.statusCode})');
      }
      return;
    }
    await Future.delayed(const Duration(seconds: 1));
  }
  throw LabException('auth attempt $authAttemptId never showed up on the Demo Device');
}

/// Returns the integration API `Authorization` header for [integrationId], creating an API key when needed.
Future<String> integrationAuthorization(int integrationId, {bool refresh = false}) async {
  File cache = File('${stateDirectory.path}/api-key-$integrationId.json');
  if (refresh || !cache.existsSync()) {
    Map<String, dynamic> key = await adminRequest('POST', '/api/v1/api-keys', {'integrationId': integrationId, 'description': 'scripts/ezkey_lab.dart'});
    stateDirectory.createSync(recursive: true);
    cache.writeAsStringSync(jsonEncode({'integrationKey': key['integrationKey'], 'secretKey': key['secretKey']}));
  }
  Map<String, dynamic> key = jsonDecode(cache.readAsStringSync());
  return 'Basic ${base64.encode(utf8.encode('${key['integrationKey']}:${key['secretKey']}'))}';
}

/// A lab step that failed. Messages never contain tokens or secrets.
class LabException implements Exception {
  /// Creates a new lab exception.
  const LabException(this.message);

  /// What went wrong.
  final String message;
}

final http.Client _client = http.Client();

/// The Demo Device session cookie (it keeps the claimed attempt in the HTTP session).
String? _demoDeviceCookie;

Future<http.Response> _demoDeviceGet(String path) async {
  http.Response response = await _client.get(demoDevice.resolve(path), headers: {'Cookie': _demoDeviceCookie ?? ''});
  String? setCookie = response.headers['set-cookie'];
  if (setCookie != null) {
    _demoDeviceCookie = setCookie.split(';').first;
  }
  return response;
}

Future<http.Response> _send(String method, Uri uri, Object? body, [String? authorization]) async {
  http.Request request = http.Request(method, uri)..headers['Accept'] = 'application/json';
  if (authorization != null) {
    request.headers['Authorization'] = authorization;
  }
  if (body != null) {
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(body);
  }
  try {
    return await http.Response.fromStream(await _client.send(request).timeout(const Duration(seconds: 120)));
  } on Exception catch (ex) {
    throw LabException('$method $uri failed: ${ex.runtimeType} (is the stack up?)');
  }
}

Map<String, dynamic> _json(http.Response response, String what) {
  if (response.statusCode < 200 || response.statusCode >= 300) {
    Object? type;
    try {
      type = (jsonDecode(response.body) as Map)['type'];
    } on Object catch (_) {}
    throw LabException('$what: HTTP ${response.statusCode}${type == null ? '' : ' ($type)'}');
  }
  return response.body.isEmpty ? {} : jsonDecode(response.body) as Map<String, dynamic>;
}
