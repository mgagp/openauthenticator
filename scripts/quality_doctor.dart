// The doctor-curated pass (#114): runs pinned analyzers on this fork's own code, then curates their
// output into one report under build/quality/. Punctual and report-only: it is not a CI gate, and it
// exits 0 whatever it finds.
//
// Usage (from the repository root):
//   scripts/with-env.sh dart scripts/quality_doctor.dart [--config config/quality/doctor.json] [--skip semgrep,jscpd]
//
// Needs: Dart (always), Node for jscpd, a JDK for Detekt, Docker for Semgrep. A missing one is
// reported as skipped. Details: docs/code-quality.md.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:hashlib/hashlib.dart';

import 'quality/curator.dart';

/// The pinned dart_code_linter version.
const String dartCodeLinterVersion = '4.4.4';

/// The pinned jscpd version.
const String jscpdVersion = '4.0.5';

/// The pinned Semgrep image (1.166.0).
const String semgrepImage = 'semgrep/semgrep@sha256:c180f0c93a17b420c0af5006214a29d3c747c5459c732b740191adf657dd0068';

/// The pinned Detekt jars from Maven Central, with their SHA-256.
const Map<String, String> detektJars = {
  'https://repo1.maven.org/maven2/io/gitlab/arturbosch/detekt/detekt-cli/1.23.8/detekt-cli-1.23.8-all.jar': '3afe89a11120303c73c9bdda3d8fe558dd9070a6937d27819ddc04b275381245',
  'https://repo1.maven.org/maven2/io/gitlab/arturbosch/detekt/detekt-formatting/1.23.8/detekt-formatting-1.23.8.jar': 'a18a3f680d232ad746ccec3d5a251776ce39131b395c455b92e1bb0a9e8fb6ba',
};

Future<void> main(List<String> arguments) async {
  ArgParser parser = ArgParser()
    ..addOption('config', defaultsTo: 'config/quality/doctor.json')
    ..addMultiOption('skip', allowed: ['dart_code_linter', 'jscpd', 'detekt', 'semgrep']);
  ArgResults args = parser.parse(arguments);
  String root = Directory.current.path;
  Map<String, dynamic> config = jsonDecode(File(args['config'] as String).readAsStringSync()) as Map<String, dynamic>;
  List<Suppression> suppressions = _readSuppressions(config['suppressions'] as String);
  Directory output = Directory(config['outputDirectory'] as String);
  Directory raw = Directory('${output.path}/raw');
  if (raw.existsSync()) {
    raw.deleteSync(recursive: true);
  }
  raw.createSync(recursive: true);

  Map<String, String> statuses = {};
  List<Finding> findings = await _runAnalyzers(
    {
      'dart_code_linter': () => _dartCodeLinter(config['dart'] as Map<String, dynamic>, raw, root),
      'jscpd': () => _jscpd(config['duplication'] as Map<String, dynamic>, raw, root),
      'detekt': () => _detekt(config['kotlin'] as Map<String, dynamic>, output, raw, root),
      'semgrep': () => _semgrep(config['semgrep'] as Map<String, dynamic>, raw, root),
    },
    skipped: args['skip'] as List<String>,
    statuses: statuses,
  );
  CuratedReport report = curate(findings, suppressions);
  _writeReports(report, output: output, title: 'Doctor-curated report: ${config['name']}', statuses: statuses);
  String counts = Priority.values.map((priority) => '${report.at(priority).length} ${priority.label}').join(', ');
  stdout.writeln('${report.findings.length} findings kept ($counts): ${output.path}/doctor.curated.md');
}

/// Reads the suppressions file. Exits with code 2 when an entry has no reason.
List<Suppression> _readSuppressions(String path) {
  try {
    return [
      for (Object? entry in jsonDecode(File(path).readAsStringSync())['suppressions'] as List<dynamic>) Suppression.fromJson(entry as Map<String, dynamic>),
    ];
  } on FormatException catch (ex) {
    stderr.writeln(ex.message);
    exit(2);
  }
}

/// Runs each analyzer not in [skipped], records its status in [statuses], and returns all findings.
Future<List<Finding>> _runAnalyzers(Map<String, Future<List<Finding>> Function()> analyzers, {required List<String> skipped, required Map<String, String> statuses}) async {
  List<Finding> findings = [];
  for (MapEntry<String, Future<List<Finding>> Function()> analyzer in analyzers.entries) {
    if (skipped.contains(analyzer.key)) {
      statuses[analyzer.key] = 'skipped (--skip)';
      continue;
    }
    stdout.writeln('Running ${analyzer.key}...');
    try {
      List<Finding> found = await analyzer.value();
      findings.addAll(found);
      statuses[analyzer.key] = 'ran: ${found.length} raw findings';
    } on _Unavailable catch (ex) {
      statuses[analyzer.key] = 'skipped: ${ex.reason}';
    }
    stdout.writeln('  ${statuses[analyzer.key]}');
  }
  return findings;
}

/// Writes the curated report as Markdown and JSON in [output].
void _writeReports(CuratedReport report, {required Directory output, required String title, required Map<String, String> statuses}) {
  File('${output.path}/doctor.curated.md').writeAsStringSync(renderMarkdown(report, title: title, date: DateTime.now(), tools: statuses));
  File('${output.path}/doctor.curated.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'tools': statuses,
      'rawCount': report.rawCount,
      'findings': [for (Finding finding in report.findings) finding.toJson()],
      'suppressed': [
        for (MapEntry<Suppression, int> entry in report.suppressed.entries) {'label': entry.key.label, 'count': entry.value, 'reason': entry.key.reason},
      ],
    }),
  );
}

/// An analyzer that cannot run here, and why.
class _Unavailable implements Exception {
  /// Why.
  final String reason;

  /// Creates a new unavailable instance.
  const _Unavailable(this.reason);
}

/// Runs [executable], and throws [_Unavailable] when it cannot start.
Future<ProcessResult> _run(String executable, List<String> arguments) async {
  try {
    return await Process.run(executable, arguments, runInShell: Platform.isWindows);
  } on ProcessException catch (ex) {
    throw _Unavailable('$executable cannot start (${ex.message})');
  }
}

/// Reads the JSON report an analyzer wrote at [path], or explains what went wrong.
Map<String, dynamic> _readReport(String path, ProcessResult result) {
  File file = File(path);
  if (!file.existsSync()) {
    String error = '${result.stderr}${result.stdout}'.trim().split('\n').last;
    throw _Unavailable('no report (exit ${result.exitCode}: $error)');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Complexity, nesting, size and parameters of the Dart code, with dart_code_linter run as a global
/// tool, so the app's dependencies stay unchanged.
Future<List<Finding>> _dartCodeLinter(Map<String, dynamic> config, Directory raw, String root) async {
  String dart = Platform.resolvedExecutable;
  ProcessResult list = await _run(dart, ['pub', 'global', 'list']);
  if (!'${list.stdout}'.contains('dart_code_linter $dartCodeLinterVersion')) {
    ProcessResult activate = await _run(dart, ['pub', 'global', 'activate', 'dart_code_linter', dartCodeLinterVersion]);
    if (activate.exitCode != 0) {
      throw const _Unavailable('cannot activate dart_code_linter $dartCodeLinterVersion');
    }
  }
  String report = '${raw.path}/dart_code_linter.json';
  Map<String, dynamic> thresholds = config['thresholds'] as Map<String, dynamic>;
  ProcessResult result = await _run(dart, [
    'pub',
    'global',
    'run',
    'dart_code_linter:metrics',
    'analyze',
    ...(config['paths'] as List<dynamic>).cast<String>(),
    '--reporter=json',
    '--json-path=$report',
    '--exclude=${config['exclude']}',
    '--no-fatal-warnings',
    '--no-congratulate',
    for (MapEntry<String, dynamic> threshold in thresholds.entries) '--${threshold.key}=${threshold.value}',
  ]);
  return readDartMetrics(_readReport(report, result), root: root);
}

/// Repeated blocks, with jscpd run through npx.
Future<List<Finding>> _jscpd(Map<String, dynamic> config, Directory raw, String root) async {
  String directory = '${raw.path}/jscpd';
  ProcessResult result = await _run('npx', [
    '--yes',
    'jscpd@$jscpdVersion',
    ...(config['paths'] as List<dynamic>).cast<String>(),
    '--min-tokens',
    '${config['minTokens']}',
    '--reporters',
    'json',
    '--output',
    directory,
    '--silent',
  ]);
  return readDuplication(_readReport('$directory/jscpd-report.json', result), root: root, longBlock: config['longBlockLines'] as int);
}

/// Design and formatting of the Kotlin code, with Detekt and its ktlint rules, downloaded once and
/// checked against their pinned SHA-256.
Future<List<Finding>> _detekt(Map<String, dynamic> config, Directory output, Directory raw, String root) async {
  Directory tools = Directory('${output.path}/tools')..createSync(recursive: true);
  List<String> jars = [
    for (MapEntry<String, String> jar in detektJars.entries) await _pinnedDownload(jar.key, jar.value, tools),
  ];
  String? javaHome = Platform.environment['JAVA_HOME'];
  String java = javaHome == null ? 'java' : '$javaHome${Platform.pathSeparator}bin${Platform.pathSeparator}java';
  String report = '${raw.path}/detekt.sarif';
  ProcessResult result = await _run(java, [
    '-jar',
    jars.first,
    '--input',
    (config['paths'] as List<dynamic>).join(','),
    '--config',
    config['config'] as String,
    '--build-upon-default-config',
    '--plugins',
    jars.last,
    '--report',
    'sarif:$report',
  ]);
  return readSarif(_readReport(report, result), root: root, tool: 'detekt');
}

/// Returns the path of [url] in [directory], downloaded if missing, and checked against [sha256Hex].
Future<String> _pinnedDownload(String url, String sha256Hex, Directory directory) async {
  File file = File('${directory.path}/${url.split('/').last}');
  if (file.existsSync() && sha256.hex(file.readAsBytesSync()) == sha256Hex) {
    return file.path;
  }
  HttpClient client = HttpClient();
  try {
    HttpClientResponse response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != 200) {
      throw _Unavailable('download failed (${response.statusCode}): $url');
    }
    await response.pipe(file.openWrite());
  } on SocketException catch (ex) {
    throw _Unavailable('download failed (${ex.message})');
  } finally {
    client.close();
  }
  if (sha256.hex(file.readAsBytesSync()) != sha256Hex) {
    file.deleteSync();
    throw _Unavailable('checksum mismatch: $url');
  }
  return file.path;
}

/// The project's own rules (secrets in logs, plain HTTP), with Semgrep in Docker, since it has no
/// native Windows build.
Future<List<Finding>> _semgrep(Map<String, dynamic> config, Directory raw, String root) async {
  ProcessResult info = await _run('docker', ['info', '--format', '{{.ServerVersion}}']);
  if (info.exitCode != 0) {
    throw const _Unavailable('Docker is not running');
  }
  String rules = File(config['rules'] as String).absolute.path;
  String report = '${raw.path}/semgrep.json';
  ProcessResult result = await _run('docker', [
    'run',
    '--rm',
    '-v',
    '$root:/src',
    '-v',
    '${File(rules).parent.path}:/rules',
    semgrepImage,
    'semgrep',
    'scan',
    '--config',
    '/rules/${rules.split(Platform.pathSeparator).last}',
    '--metrics=off',
    '--quiet',
    '--json',
    '--output',
    '/src/${report.replaceAll('\\', '/')}',
    for (Object? path in config['paths'] as List<dynamic>) '/src/$path',
  ]);
  return readSemgrep(_readReport(report, result));
}
