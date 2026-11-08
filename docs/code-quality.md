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

**Keyword:** `doctor-curated`. Run the pass, read the curated report, then go through the findings one at a time with the maintainer. Each one gets a fix, a suppression with its reason, or nothing. Record the decisions in a pass note under [`quality/`](quality/).

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

**Suppressions** (`config/quality/suppressions.json`) drop a rule by analyzer, and optionally by path or by function. Each one needs a written reason, or the pass refuses to run. The report lists every suppression with its count.

## Criteria for new code

Phase 2 of #114. They apply to the fork's code, whoever writes it, a person or an agent.

| Criterion | Checked by |
| --- | --- |
| A function stays within the thresholds above: complexity 10, nesting 3, 4 parameters, 50 lines. Past them, split it, or say in the PR why not | The pass. CI fails on a new P1, which is about twice a threshold |
| The extra lint rules of our folders pass (below) | `flutter analyze` in CI |
| No secret, token or key material in a log, no plain HTTP URL in app code | Semgrep rules, in CI |
| A catch names what it catches. A catch-all is only for an intended fail-open, written `on Object catch`, with the reason next to it | `avoid_catches_without_on_clauses` |
| Every public member has a doc comment | `public_member_api_docs` (app and plugin code) |
| Names say what the thing is or does, without abbreviations other than common ones (`id`, `url`). A boolean reads as a question (`isAdministration`, `hasEnrollments`) | Review: no deterministic tool judges this |
| Format | `dart format`, in CI |
| A test proves it can fail: break the code, see red, restore | Review, and the PR's checks section |

**Extra lint rules.** Each of our folders has its own `analysis_options.yaml`, which includes the root one and adds rules: `lib/ezkey/`, `packages/ezkey_keystore/`, `scripts/`, `test/`, `integration_test/`. The root file is upstream's and stays untouched, so upstream's code is not checked by them. Including the root file, which declares the `riverpod_lint` plugin, raises no diagnostic (checked on 2026-11-08).

The rules: `public_member_api_docs`, `avoid_dynamic_calls`, `unawaited_futures`, `avoid_print`, `always_declare_return_types`, `avoid_catches_without_on_clauses`, `cancel_subscriptions`, `close_sinks`, `directives_ordering`, `prefer_final_fields`, `avoid_slow_async_io`, `only_throw_errors`, `avoid_positional_boolean_parameters`, `use_named_constants`, `no_literal_bool_comparisons`, `prefer_null_aware_method_calls`, `avoid_redundant_argument_values`, `unnecessary_await_in_return`, `literal_only_boolean_expressions`, `no_adjacent_strings_in_list`, `avoid_void_async`. Tests drop the first, `avoid_positional_boolean_parameters` and `avoid_redundant_argument_values`. Scripts and device tests drop `avoid_print`, since printing is their output. `discarded_futures` was left out: in Flutter callbacks it asks for `unawaited` on every fire-and-forget call, for little gain.

**The CI check.** `dart scripts/quality_doctor.dart --skip jscpd,detekt --fail-on-new` runs dart_code_linter and Semgrep, and fails on a P1 finding that `config/quality/baseline.json` does not list. It also fails when one of them cannot run, rather than pass blind. The baseline lists today's two P1 findings, keyed by file and function so moved lines do not matter. When one is fixed, remove it from the baseline with `--write-baseline`, never to make room for a new one.

## Reuse in the EzKey SDK

Nothing in the curator (`scripts/quality/curator.dart`) is specific to this app: it reads the analyzers' standard outputs. To reuse it for `ezkey_dart`, copy `scripts/quality_doctor.dart`, `scripts/quality/` and `config/quality/`, set the paths in `doctor.json`, and drop the Kotlin part.

## Next phases (#114)

- **Phase 2:** done, see [Criteria for new code](#criteria-for-new-code).
- **Phase 3:** the plugin's Kotlin gets the same treatment, with a narrowed Detekt configuration.
