import 'package:flutter_test/flutter_test.dart';

import '../../../scripts/quality/curator.dart';

/// A dart_code_linter record for [path], with one function and its [metrics] (`id`, `value`, `level`).
Map<String, dynamic> _dartRecord(String path, String function, List<(String, num, String)> metrics, {int line = 12}) => {
  'path': path,
  'functions': {
    function: {
      'codeSpan': {
        'start': {'line': line},
      },
      'metrics': [
        for ((String, num, String) metric in metrics) {'metricsId': metric.$1, 'value': metric.$2, 'level': metric.$3},
      ],
    },
  },
};

/// A finding with only what a test needs to set.
Finding _finding({String tool = 'jscpd', String rule = 'duplicate-dart', String path = 'lib/ezkey/a.dart', int line = 1, String? symbol, Priority priority = Priority.p3, String message = 'm'}) =>
    Finding(tool: tool, rule: rule, path: path, line: line, symbol: symbol, message: message, priority: priority);

void main() {
  const String root = r'C:\github\app';

  group('readDartMetrics', () {
    test('ranks alarm, warning and noted as P1, P2 and P3, and skips what is under its threshold', () {
      Map<String, dynamic> json = {
        'records': [
          _dartRecord(r'lib\ezkey\home.dart', 'build', [
            ('cyclomatic-complexity', 26, 'alarm'),
            ('source-lines-of-code', 60, 'warning'),
            ('number-of-parameters', 4, 'noted'),
            ('maximum-nesting-level', 1, 'none'),
          ]),
        ],
      };

      List<Finding> findings = readDartMetrics(json, root: root);

      expect(findings.map((finding) => (finding.rule, finding.priority)), [
        ('cyclomatic-complexity', Priority.p1),
        ('source-lines-of-code', Priority.p2),
        ('number-of-parameters', Priority.p3),
      ]);
      expect(findings.first.path, 'lib/ezkey/home.dart');
      expect(findings.first.symbol, 'build');
      expect(findings.first.line, 12);
    });

    test('ranks test code one level lower', () {
      Map<String, dynamic> json = {
        'records': [
          _dartRecord('test/ezkey/home_test.dart', 'pump', [('cyclomatic-complexity', 26, 'alarm')]),
        ],
      };

      expect(readDartMetrics(json, root: root).single.priority, Priority.p2);
    });
  });

  group('readDuplication', () {
    Map<String, dynamic> report(String first, int lines) => {
      'duplicates': [
        {
          'format': 'dart',
          'lines': lines,
          'firstFile': {'name': first, 'start': 10},
          'secondFile': {'name': r'lib\ezkey\b.dart', 'start': 40},
        },
      ],
    };

    test('ranks a long block in app code P2, and says where its copy is', () {
      Finding finding = readDuplication(report(r'lib\ezkey\a.dart', 16), root: root).single;

      expect(finding.priority, Priority.p2);
      expect(finding.path, 'lib/ezkey/a.dart');
      expect(finding.message, '16 lines also at lib/ezkey/b.dart:40');
    });

    test('ranks a short block, or any block in tests, P3', () {
      expect(readDuplication(report(r'lib\ezkey\a.dart', 14), root: root).single.priority, Priority.p3);
      expect(readDuplication(report(r'test\a_test.dart', 30), root: root).single.priority, Priority.p3);
    });
  });

  group('readSarif', () {
    Map<String, dynamic> report(String rule, String level) => {
      'runs': [
        {
          'results': [
            {
              'ruleId': rule,
              'level': level,
              'message': {'text': 'Too generic.'},
              'locations': [
                {
                  'physicalLocation': {
                    'artifactLocation': {'uri': 'file:///C:/github/app/packages/plugin/Plugin.kt'},
                    'region': {'startLine': 117},
                  },
                },
              ],
            },
          ],
        },
      ],
    };

    test('ranks by SARIF level, with the path relative to the root', () {
      Finding finding = readSarif(report('detekt.exceptions.TooGenericExceptionCaught', 'warning'), root: root, tool: 'detekt').single;

      expect(finding.priority, Priority.p2);
      expect(finding.path, 'packages/plugin/Plugin.kt');
      expect(finding.line, 117);
    });

    test('ranks formatting rules P3, whatever their level', () {
      expect(readSarif(report('detekt.formatting.MaximumLineLength', 'error'), root: root, tool: 'detekt').single.priority, Priority.p3);
    });
  });

  group('readSemgrep', () {
    test('ranks a warning P1, and strips the container mount point', () {
      Map<String, dynamic> json = {
        'results': [
          {
            'check_id': 'rules.ezkey-secret-in-log',
            'path': '/src/lib/ezkey/actions.dart',
            'start': {'line': 80},
            'extra': {'severity': 'WARNING', 'message': 'A secret goes to the log.'},
          },
        ],
      };

      Finding finding = readSemgrep(json).single;

      expect(finding.rule, 'ezkey-secret-in-log');
      expect(finding.path, 'lib/ezkey/actions.dart');
      expect(finding.priority, Priority.p1);
    });
  });

  group('Suppression', () {
    test('refuses an entry without a written reason', () {
      expect(() => Suppression.fromJson({'tool': 'jscpd', 'rule': 'duplicate-dart', 'reason': '  '}), throwsFormatException);
    });

    test('matches only its tool, rule, path and symbol', () {
      Suppression suppression = Suppression.fromJson({'tool': 'dart_code_linter', 'rule': 'source-lines-of-code', 'path': 'test/', 'symbol': 'main', 'reason': 'Tests.'});
      Finding inTest = _finding(tool: 'dart_code_linter', rule: 'source-lines-of-code', path: 'test/a_test.dart', symbol: 'main');

      expect(suppression.matches(inTest), isTrue);
      expect(suppression.matches(_finding(tool: 'dart_code_linter', rule: 'source-lines-of-code', path: 'lib/a.dart', symbol: 'main')), isFalse);
      expect(suppression.matches(_finding(tool: 'dart_code_linter', rule: 'source-lines-of-code', path: 'test/a_test.dart', symbol: 'pump')), isFalse);
      expect(suppression.matches(_finding(tool: 'dart_code_linter', rule: 'cyclomatic-complexity', path: 'test/a_test.dart', symbol: 'main')), isFalse);
    });
  });

  group('curate', () {
    test('drops suppressed findings and counts them per suppression', () {
      Suppression suppression = const Suppression(tool: 'jscpd', rule: 'duplicate-dart', reason: 'Not now.');

      CuratedReport report = curate([_finding(line: 1), _finding(line: 2), _finding(tool: 'detekt', rule: 'x')], [suppression]);

      expect(report.rawCount, 3);
      expect(report.findings.single.tool, 'detekt');
      expect(report.suppressed, {suppression: 2});
    });

    test('merges the metrics of one symbol into one finding at its most urgent rank', () {
      CuratedReport report = curate([
        _finding(tool: 'dart_code_linter', rule: 'maximum-nesting-level', symbol: 'build', priority: Priority.p3, message: 'nesting 3'),
        _finding(tool: 'dart_code_linter', rule: 'cyclomatic-complexity', symbol: 'build', priority: Priority.p1, message: 'complexity 26'),
      ], []);

      Finding finding = report.findings.single;
      expect(finding.priority, Priority.p1);
      expect(finding.message, 'nesting 3; complexity 26');
    });

    test('drops exact duplicates, and sorts by rank, then path, then line', () {
      CuratedReport report = curate([
        _finding(path: 'lib/b.dart', priority: Priority.p2),
        _finding(path: 'lib/a.dart', line: 9, priority: Priority.p2),
        _finding(path: 'lib/a.dart', line: 3, priority: Priority.p2),
        _finding(path: 'lib/a.dart', line: 3, priority: Priority.p2),
        _finding(path: 'lib/z.dart', priority: Priority.p1),
      ], []);

      expect(report.findings.map((finding) => finding.location), ['lib/z.dart:1', 'lib/a.dart:3', 'lib/a.dart:9', 'lib/b.dart:1']);
    });
  });

  group('renderMarkdown', () {
    test('states the counts, each rank and each suppression with its reason', () {
      Suppression suppression = const Suppression(tool: 'jscpd', rule: 'duplicate-dart', reason: 'Fixture data.');
      CuratedReport report = curate([_finding(priority: Priority.p1), _finding(line: 2)], [suppression]);

      String markdown = renderMarkdown(report, title: 'Report', date: DateTime(2026, 11, 8), tools: {'jscpd': 'ran'});

      expect(markdown, contains('**2** raw findings, **2** suppressed, **0** kept: 0 P1, 0 P2, 0 P3.'));
      expect(markdown, contains('| jscpd `duplicate-dart` | 2 | Fixture data. |'));
      expect(markdown, contains('## P1 (0)'));
    });
  });
}
