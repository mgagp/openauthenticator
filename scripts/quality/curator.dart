// Curator of the doctor-curated pass (#114): reads the raw output of each analyzer, drops what the
// suppressions list says, merges duplicates, and ranks the rest as P1, P2 and P3.
//
// Pure Dart with no dependency on this app, so the EzKey SDK can reuse it as is.

/// How urgent a finding is.
enum Priority {
  /// Worth acting on now: a security signal, or a metric far past its threshold.
  p1,

  /// Worth acting on when the code is touched.
  p2,

  /// Information: a trend to watch, or a minor style point.
  p3;

  /// The label shown in the report.
  String get label => name.toUpperCase();

  /// One level less urgent, P3 staying P3.
  Priority get lower => this == p3 ? p3 : Priority.values[index + 1];
}

/// One signal from one analyzer, at one place.
class Finding {
  /// The analyzer: `dart_code_linter`, `jscpd`, `detekt` or `semgrep`.
  final String tool;

  /// The rule or metric, as the analyzer names it.
  final String rule;

  /// The file, relative to the repository root, with forward slashes.
  final String path;

  /// The first line, 1-based.
  final int line;

  /// The function or class, when the analyzer gives one.
  final String? symbol;

  /// What the analyzer says.
  final String message;

  /// The rank.
  final Priority priority;

  /// Creates a new finding instance.
  const Finding({
    required this.tool,
    required this.rule,
    required this.path,
    required this.line,
    required this.message,
    required this.priority,
    this.symbol,
  });

  /// Where it is, for the report.
  String get location => symbol == null ? '$path:$line' : '$path:$line ($symbol)';

  /// The JSON form of the curated report.
  Map<String, Object?> toJson() => {
    'priority': priority.label,
    'tool': tool,
    'rule': rule,
    'path': path,
    'line': line,
    'symbol': symbol,
    'message': message,
  };
}

/// A rule left out of the report, with the reason why.
class Suppression {
  /// The analyzer it applies to.
  final String tool;

  /// The rule or metric it applies to.
  final String rule;

  /// Only files whose path starts with this, when set.
  final String? pathPrefix;

  /// Only this function or class, when set.
  final String? symbol;

  /// Why the signal is not worth acting on. Required.
  final String reason;

  /// Creates a new suppression instance.
  const Suppression({
    required this.tool,
    required this.rule,
    required this.reason,
    this.pathPrefix,
    this.symbol,
  });

  /// Reads one entry of the suppressions file, and refuses an entry without a reason.
  factory Suppression.fromJson(Map<String, dynamic> json) {
    String reason = (json['reason'] as String? ?? '').trim();
    if (reason.isEmpty) {
      throw FormatException('A suppression needs a written reason: $json');
    }
    return Suppression(tool: json['tool'] as String, rule: json['rule'] as String, pathPrefix: json['path'] as String?, symbol: json['symbol'] as String?, reason: reason);
  }

  /// Whether this suppression drops [finding].
  bool matches(Finding finding) => finding.tool == tool && finding.rule == rule && (pathPrefix == null || finding.path.startsWith(pathPrefix!)) && (symbol == null || finding.symbol == symbol);

  /// The label shown in the report.
  String get label => [
    '$tool `$rule`',
    if (symbol != null) 'on `$symbol`',
    if (pathPrefix != null) 'in `$pathPrefix`',
  ].join(' ');
}

/// The curated result.
class CuratedReport {
  /// How many findings the analyzers produced.
  final int rawCount;

  /// What is left, most urgent first.
  final List<Finding> findings;

  /// How many findings each suppression dropped.
  final Map<Suppression, int> suppressed;

  /// Creates a new curated report instance.
  const CuratedReport({
    required this.rawCount,
    required this.findings,
    required this.suppressed,
  });

  /// The findings of [priority].
  List<Finding> at(Priority priority) => [
    for (Finding finding in findings)
      if (finding.priority == priority) finding,
  ];
}

/// Whether [path] is test code, where a metric matters less.
bool isTestPath(String path) => path.startsWith('test/') || path.startsWith('integration_test/');

/// Returns [path] relative to [root], with forward slashes.
String relativePath(String path, String root) {
  String normalized = path.replaceAll('\\', '/');
  if (normalized.startsWith('file:///')) {
    normalized = normalized.substring('file:///'.length);
  }
  String base = root.replaceAll('\\', '/');
  base = base.endsWith('/') ? base : '$base/';
  return normalized.toLowerCase().startsWith(base.toLowerCase()) ? normalized.substring(base.length) : normalized;
}

/// Returns the JSON object under [key] of [json], or an empty one.
Map<String, dynamic> _object(Object? json, String key) {
  Object? value = json is Map<String, dynamic> ? json[key] : null;
  return value is Map<String, dynamic> ? value : const {};
}

/// Ranks a metric level of dart_code_linter.
Priority? _metricPriority(String? level) => switch (level) {
  'alarm' => Priority.p1,
  'warning' => Priority.p2,
  'noted' => Priority.p3,
  _ => null,
};

/// Reads a dart_code_linter JSON report: one finding per metric past its threshold.
List<Finding> readDartMetrics(Map<String, dynamic> json, {required String root}) => [
  for (Map<String, dynamic> record in (json['records'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>())
    for (String kind in ['functions', 'classes'])
      for (MapEntry<String, dynamic> symbol in (record[kind] as Map<String, dynamic>? ?? {}).entries)
        ..._symbolFindings(relativePath(record['path'] as String, root), symbol.key, symbol.value as Map<String, dynamic>),
];

/// The metrics of one function or class past their threshold.
List<Finding> _symbolFindings(String path, String symbol, Map<String, dynamic> body) {
  int line = _object(_object(body, 'codeSpan'), 'start')['line'] as int? ?? 1;
  List<Finding> findings = [];
  for (Map<String, dynamic> metric in (body['metrics'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>()) {
    Priority? priority = _metricPriority(metric['level'] as String?);
    if (priority != null) {
      findings.add(
        Finding(
          tool: 'dart_code_linter',
          rule: metric['metricsId'] as String,
          path: path,
          line: line,
          symbol: symbol,
          message: '${metric['metricsId']} ${metric['value']} (${metric['level']})',
          priority: isTestPath(path) ? priority.lower : priority,
        ),
      );
    }
  }
  return findings;
}

/// Reads a jscpd JSON report. A long block repeated in app code is P2, anything else P3.
List<Finding> readDuplication(Map<String, dynamic> json, {required String root, int longBlock = 15}) => [
  for (Map<String, dynamic> duplicate in (json['duplicates'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>())
    () {
      Map<String, dynamic> first = duplicate['firstFile'] as Map<String, dynamic>;
      Map<String, dynamic> second = duplicate['secondFile'] as Map<String, dynamic>;
      String path = relativePath(first['name'] as String, root);
      int lines = duplicate['lines'] as int;
      return Finding(
        tool: 'jscpd',
        rule: 'duplicate-${duplicate['format']}',
        path: path,
        line: first['start'] as int,
        message: '$lines lines also at ${relativePath(second['name'] as String, root)}:${second['start']}',
        priority: lines >= longBlock && !isTestPath(path) ? Priority.p2 : Priority.p3,
      );
    }(),
];

/// Reads a SARIF report, as Detekt writes it. Formatting rules are P3.
List<Finding> readSarif(Map<String, dynamic> json, {required String root, required String tool}) => [
  for (Map<String, dynamic> run in (json['runs'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>())
    for (Map<String, dynamic> result in (run['results'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>()) _sarifFinding(result, root: root, tool: tool),
];

/// One SARIF result.
Finding _sarifFinding(Map<String, dynamic> result, {required String root, required String tool}) {
  List<dynamic> locations = result['locations'] as List<dynamic>? ?? [];
  Map<String, dynamic> location = locations.isEmpty ? {} : (locations.first as Map<String, dynamic>)['physicalLocation'] as Map<String, dynamic>? ?? {};
  String rule = result['ruleId'] as String? ?? 'unknown';
  return Finding(
    tool: tool,
    rule: rule,
    path: relativePath(_object(location, 'artifactLocation')['uri'] as String? ?? '', root),
    line: _object(location, 'region')['startLine'] as int? ?? 1,
    message: _object(result, 'message')['text'] as String? ?? '',
    priority: rule.contains('.formatting.') ? Priority.p3 : _sarifPriority(result['level'] as String?),
  );
}

/// Ranks a SARIF level.
Priority _sarifPriority(String? level) => switch (level) {
  'error' => Priority.p1,
  'warning' => Priority.p2,
  _ => Priority.p3,
};

/// Reads a Semgrep JSON report, its paths being under [mountPoint]. Errors and warnings are P1.
List<Finding> readSemgrep(Map<String, dynamic> json, {String mountPoint = '/src/'}) => [
  for (Map<String, dynamic> result in (json['results'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>())
    Finding(
      tool: 'semgrep',
      rule: (result['check_id'] as String).split('.').last,
      path: (result['path'] as String).replaceFirst(mountPoint, ''),
      line: _object(result, 'start')['line'] as int? ?? 1,
      message: _object(result, 'extra')['message'] as String? ?? '',
      priority: switch (_object(result, 'extra')['severity']) {
        'ERROR' || 'WARNING' => Priority.p1,
        _ => Priority.p2,
      },
    ),
];

/// Drops the suppressed findings and the exact duplicates, merges the metrics of one symbol into one
/// finding at its most urgent rank, and sorts by rank, then by place.
CuratedReport curate(List<Finding> raw, List<Suppression> suppressions) {
  Map<Suppression, int> suppressed = {};
  Map<String, Finding> kept = {};
  for (Finding finding in raw) {
    Suppression? suppression = suppressions.where((candidate) => candidate.matches(finding)).firstOrNull;
    if (suppression != null) {
      suppressed[suppression] = (suppressed[suppression] ?? 0) + 1;
      continue;
    }
    bool bySymbol = finding.tool == 'dart_code_linter' && finding.symbol != null;
    String key = bySymbol ? '${finding.tool}|${finding.path}|${finding.symbol}' : '${finding.tool}|${finding.rule}|${finding.path}|${finding.line}|${finding.message}';
    Finding? previous = kept[key];
    kept[key] = previous == null || !bySymbol ? finding : _merge(previous, finding);
  }
  List<Finding> findings = kept.values.toList()
    ..sort((a, b) {
      int byPriority = a.priority.index.compareTo(b.priority.index);
      int byPath = a.path.compareTo(b.path);
      return byPriority != 0 ? byPriority : (byPath != 0 ? byPath : a.line.compareTo(b.line));
    });
  return CuratedReport(rawCount: raw.length, findings: findings, suppressed: suppressed);
}

/// Merges two metrics of the same symbol.
Finding _merge(Finding a, Finding b) => Finding(
  tool: a.tool,
  rule: '${a.rule}, ${b.rule}',
  path: a.path,
  line: a.line,
  symbol: a.symbol,
  message: '${a.message}; ${b.message}',
  priority: a.priority.index <= b.priority.index ? a.priority : b.priority,
);

/// The key of [finding] in a baseline: stable when lines move. The metrics of one function share
/// one key, since the curator merges them.
String baselineKey(Finding finding) =>
    finding.tool == 'dart_code_linter' && finding.symbol != null ? '${finding.tool}|${finding.path}|${finding.symbol}' : '${finding.tool}|${finding.rule}|${finding.path}|${finding.symbol ?? ''}';

/// The findings at [atLeast] or more urgent that [baseline] does not know: what the code gained.
List<Finding> newSince(List<Finding> findings, Set<String> baseline, {Priority atLeast = Priority.p1}) => [
  for (Finding finding in findings)
    if (finding.priority.index <= atLeast.index && !baseline.contains(baselineKey(finding))) finding,
];

/// Renders [report] as Markdown. [tools] maps each analyzer to its status line.
String renderMarkdown(CuratedReport report, {required String title, required DateTime date, required Map<String, String> tools}) {
  StringBuffer out = StringBuffer()
    ..writeln('# $title')
    ..writeln()
    ..writeln('Generated on ${date.toIso8601String().substring(0, 16).replaceFirst('T', ' ')}. Report only: not a CI gate.')
    ..writeln()
    ..writeln('| Analyzer | Status |')
    ..writeln('| --- | --- |');
  for (MapEntry<String, String> tool in tools.entries) {
    out.writeln('| ${tool.key} | ${tool.value} |');
  }
  int suppressedCount = report.suppressed.values.fold(0, (sum, count) => sum + count);
  out
    ..writeln()
    ..writeln(
      '**${report.rawCount}** raw findings, **$suppressedCount** suppressed, **${report.findings.length}** kept: '
      '${Priority.values.map((priority) => '${report.at(priority).length} ${priority.label}').join(', ')}.',
    );
  for (Priority priority in Priority.values) {
    List<Finding> findings = report.at(priority);
    out
      ..writeln()
      ..writeln('## ${priority.label} (${findings.length})')
      ..writeln();
    if (findings.isEmpty) {
      out.writeln('None.');
      continue;
    }
    out
      ..writeln('| Where | What | Analyzer |')
      ..writeln('| --- | --- | --- |');
    for (Finding finding in findings) {
      out.writeln('| `${finding.location}` | ${finding.message.replaceAll('|', '\\|').replaceAll('\n', ' ')} | ${finding.tool} |');
    }
  }
  out
    ..writeln()
    ..writeln('## Suppressed')
    ..writeln();
  if (report.suppressed.isEmpty) {
    out.writeln('None.');
  } else {
    out
      ..writeln('| Rule | Count | Reason |')
      ..writeln('| --- | --- | --- |');
    for (MapEntry<Suppression, int> entry in report.suppressed.entries) {
      out.writeln('| ${entry.key.label} | ${entry.value} | ${entry.key.reason} |');
    }
  }
  return out.toString();
}
