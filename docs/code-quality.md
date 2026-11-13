# Code quality

How this fork watches the quality of its own code: a punctual, curated pass over a few deterministic analyzers, in the same shape as EzKey's `mobile-doctor-curated` (#114).

## Scope

The pass covers the fork's own code only: `lib/ezkey/`, `packages/ezkey_keystore/`, `test/`, `integration_test/` and the fork's scripts. Upstream's code stays out of the report and out of any gate, since the fork takes no initiative on it (`CLAUDE.md` § Upstream alignment). Upstream's own scripts in `scripts/` (`flatpak-build-publish.sh`, `snap-build.sh`) are left out by name.

Formatting stays with `dart format`, checked in CI on the files that differ from upstream, so upstream's files keep their original format.

## Running it

```sh
scripts/with-env.sh dart scripts/quality_doctor.dart            # about 40 s
scripts/with-env.sh dart scripts/quality_doctor.dart --skip semgrep
```

It writes `build/quality/doctor.curated.md` and `.json` (curated), and `build/quality/raw/` (each analyzer's output). It exits 0 whatever it finds: it is a report, not a gate. A missing runtime (Node, a JDK, Docker) makes its analyzer show as skipped, with the reason.

**Keyword:** `doctor-curated`. Run the pass, read the curated report, then decide with the maintainer what each P1 and P2 gets: a fix, a suppression with its reason, or nothing. The [compass](#compass-how-far-to-go) says how far to go. Record the decisions in a pass note under [`quality/`](quality/).

## Analyzers

Chosen on 2026-11-08 after a trial on this code (phase 0 of #114). Every version is pinned in `scripts/quality_doctor.dart`.

| Analyzer | Version | Licence | What it gives | How it runs |
| --- | --- | --- | --- | --- |
| [dart_code_linter](https://pub.dev/packages/dart_code_linter) | 4.4.4 | MIT | Cyclomatic complexity, nesting, parameters, size per function | `dart pub global`, so `pubspec.yaml` is untouched |
| [jscpd](https://github.com/kucherenko/jscpd) | 4.0.5 | MIT | Repeated blocks, in Dart and the other languages | `npx` |
| [Detekt](https://detekt.dev/) with its ktlint rules | 1.23.8 | Apache 2.0 | Design and formatting of the plugin's Kotlin | JDK, jars from Maven Central checked by SHA-256 |
| [Semgrep](https://semgrep.dev/) | 1.166.0 | LGPL 2.1 | The project's own rules (`config/quality/semgrep.yml`): secrets in logs, plain HTTP, key material in the Android log | Docker image pinned by digest |

**Left out:**

- **DCM:** commercial since its open-source edition stopped. dart_code_linter continues that edition.
- **solid_lints:** an analyzer plugin, which needs a dependency in `pubspec.yaml` and a change to the root `analysis_options.yaml`, two upstream files. It overlaps with dart_code_linter.
- **SonarQube:** too heavy for a punctual pass. EzKey left it out too.
- **Detekt 2.0:** still in alpha. Stay on 1.23.8, as EzKey does.

## Ranking

| Rank | Means | From |
| --- | --- | --- |
| **P1** | Act now | Semgrep warnings and errors, metrics at alarm level, Detekt errors |
| **P2** | Act when the code is touched | Metrics at warning level, a repeated block of 15 lines or more in app code, Detekt warnings |
| **P3** | Watch | Metrics just at their threshold, short or test duplicates, Kotlin formatting |

Test code is ranked one level lower. The metrics of one function are merged into one finding at its most urgent rank.

**Thresholds** (`config/quality/doctor.json`): cyclomatic complexity 10, nesting 3, parameters 4, 50 source lines per function. dart_code_linter reports a value at the threshold as noted, then warning and alarm further past it.

**Suppressions** (`config/quality/suppressions.json`) drop a rule by analyzer, and optionally by path or by function. A bare method name, like `build`, covers that method in every class. Each one needs a written reason, or the pass refuses to run. The report lists every suppression with its count.

## Compass: how far to go

Agreed on 2026-11-13, after pass 2 ([`quality/2026-11-11-pass-2.md`](quality/2026-11-11-pass-2.md) § What the pass taught). The aim is the code a professional who knows the language, its community and its practices would write with reasonable care. It is not a perfect report: past a point, more work on a finding brings less than it costs. Read these eight rules before going through a report.

1. **The report is a signal, not a task list.** A finding asks for a look. The default decision is to change nothing.
2. **The rank sets the action.** P1: act. P2: act only when that code is touched for another reason. P3: do nothing.
3. **Risk comes before the metric.** Act ahead of time only when both are true: the code is sensitive (approving, keys, storage, backups), and the finding points to code that is really hard to read or to a path with no test.
4. **The professional's test.** Would an experienced developer of the language raise it in a review? If not, suppress it with a written reason, or adjust the threshold.
5. **A missing test is worth more than a split.** On sensitive code, add the tests. Split a function only when it really helps the reader.
6. **Check in proportion to the change.** A moved piece of layout: the analyzer and the existing tests. Sensitive logic: tests first, a break of each path to see red, then a device.
7. **A pass has an end.** It ends when the P1 are fixed and each P2 has a decision, not when the report is empty.
8. **A signal that keeps coming back without value is settled in the tool.** Adjust a threshold or add a suppression with its reason, and leave the code.

## Criteria for new code

Phase 2 of #114. They apply to the fork's code, whoever writes it, a person or an agent.

| Criterion | Checked by |
| --- | --- |
| A function stays within the thresholds above: complexity 10, nesting 3, 4 parameters, 50 lines. Past them, split it, or say in the PR why not. A `build` method in `lib/ezkey/` has no line limit: it is a widget tree | The pass. CI fails on a new P1, which is about twice a threshold |
| The extra lint rules of our folders pass (below) | `flutter analyze` in CI |
| No secret, token or key material in a log, no plain HTTP URL in app code | Semgrep rules, in CI |
| A catch names what it catches. A catch-all is only for an intended fail-open, written `on Object catch`, with the reason next to it | `avoid_catches_without_on_clauses` |
| Every public member has a doc comment | `public_member_api_docs` (app and plugin code) |
| Names say what the thing is or does, without abbreviations other than common ones (`id`, `url`). A boolean reads as a question (`isAdministration`, `hasEnrollments`) | Review: no deterministic tool judges this |
| Format | `dart format`, in CI |
| A test proves it can fail: break the code, see red, restore | Review, and the PR's checks section |

**Extra lint rules.** Each of our folders has its own `analysis_options.yaml`, which includes the root one and adds rules: `lib/ezkey/`, `packages/ezkey_keystore/`, `scripts/`, `test/`, `integration_test/`. The root file is upstream's and stays untouched, so upstream's code is not checked by them. Including the root file, which declares the `riverpod_lint` plugin, raises no diagnostic (checked on 2026-11-08).

The rules: `public_member_api_docs`, `avoid_dynamic_calls`, `unawaited_futures`, `avoid_print`, `always_declare_return_types`, `avoid_catches_without_on_clauses`, `cancel_subscriptions`, `close_sinks`, `directives_ordering`, `prefer_final_fields`, `avoid_slow_async_io`, `only_throw_errors`, `avoid_positional_boolean_parameters`, `use_named_constants`, `no_literal_bool_comparisons`, `prefer_null_aware_method_calls`, `avoid_redundant_argument_values`, `unnecessary_await_in_return`, `literal_only_boolean_expressions`, `no_adjacent_strings_in_list`, `avoid_void_async`. Tests drop the first, `avoid_positional_boolean_parameters` and `avoid_redundant_argument_values`. Scripts and device tests drop `avoid_print`, since printing is their output. `discarded_futures` was left out: in Flutter callbacks it asks for `unawaited` on every fire-and-forget call, for little gain.

**The CI check.** `dart scripts/quality_doctor.dart --skip jscpd,detekt --fail-on-new` runs dart_code_linter and Semgrep, and fails on a P1 finding that `config/quality/baseline.json` does not list. It also fails when one of them cannot run, rather than pass blind. The baseline lists known P1 findings, keyed by file and function so moved lines do not matter. It started with two, and is empty since pass 2 fixed them ([`quality/2026-11-11-pass-2.md`](quality/2026-11-11-pass-2.md)). When one is fixed, remove it from the baseline with `--write-baseline`, never to make room for a new one.

## Reuse in the EzKey SDK

Nothing in the curator (`scripts/quality/curator.dart`) is specific to this app: it reads the analyzers' standard outputs. To reuse it for `ezkey_dart`, copy `scripts/quality_doctor.dart`, `scripts/quality/` and `config/quality/`, set the paths in `doctor.json`, and drop the Kotlin part.

## Next phases (#114)

- **Phase 2:** done, see [Criteria for new code](#criteria-for-new-code).
- **Phase 3:** the plugin's Kotlin gets the same treatment, with a narrowed Detekt configuration.
