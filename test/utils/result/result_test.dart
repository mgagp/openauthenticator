import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/utils/result/result.dart';

void main() {
  group('ResultSuccess', () {
    test('exposes its value through value and valueOrNull', () {
      ResultSuccess<int> result = const ResultSuccess(value: 42);

      expect(result.value, 42);
      expect(result.valueOrNull, 42);
    });

    test('allows an absent value, but value then throws', () {
      ResultSuccess<int> result = const ResultSuccess();

      expect(result.valueOrNull, isNull);
      expect(() => result.value, throwsA(isA<TypeError>()));
    });

    test('to() converts the value and stays a success', () {
      Result<String> converted = const ResultSuccess(value: 21).to((value) => 'value: ${value! * 2}');

      expect(converted, isA<ResultSuccess<String>>());
      expect(converted.valueOrNull, 'value: 42');
    });

    test('to() passes null to the converter when there is no value', () {
      Object? received = 'not called';
      Result<String> converted = const ResultSuccess<int>().to((value) {
        received = value;
        return null;
      });

      expect(received, isNull);
      expect(converted, isA<ResultSuccess<String>>());
      expect(converted.valueOrNull, isNull);
    });
  });

  group('ResultError', () {
    test('has no value', () {
      ResultError<int> result = ResultError(exception: Exception('boom'));

      expect(result.valueOrNull, isNull);
    });

    test('captures the current stack trace when none is given', () {
      ResultError<int> result = ResultError(exception: Exception('boom'));

      expect(result.stackTrace.toString(), contains('result_test.dart'));
    });

    test('keeps the given stack trace', () {
      StackTrace stackTrace = StackTrace.fromString('given stack trace');
      ResultError<int> result = ResultError(exception: Exception('boom'), stackTrace: stackTrace);

      expect(result.stackTrace, same(stackTrace));
    });

    test('to() keeps the same exception and stack trace, and never calls the converter', () {
      Exception exception = Exception('boom');
      ResultError<int> result = ResultError(exception: exception);
      bool converterCalled = false;

      Result<String> converted = result.to((_) {
        converterCalled = true;
        return 'unexpected';
      });

      expect(converterCalled, isFalse);
      expect(converted, isA<ResultError<String>>());
      ResultError<String> error = converted as ResultError<String>;
      expect(error.exception, same(exception));
      expect(error.stackTrace, same(result.stackTrace));
    });

    test('fromAnother() copies exception and stack trace', () {
      ResultError<int> original = ResultError(exception: Exception('boom'));
      ResultError<String> copy = ResultError.fromAnother(original);

      expect(copy.exception, same(original.exception));
      expect(copy.stackTrace, same(original.stackTrace));
    });
  });

  group('ResultCancelled', () {
    test('has no value', () {
      expect(const ResultCancelled<int>().valueOrNull, isNull);
    });

    test('to() stays cancelled and never calls the converter', () {
      bool converterCalled = false;

      Result<String> converted = const ResultCancelled<int>().to((_) {
        converterCalled = true;
        return 'unexpected';
      });

      expect(converterCalled, isFalse);
      expect(converted, isA<ResultCancelled<String>>());
    });
  });

  group('Result', () {
    test('can be handled exhaustively with a switch', () {
      String describe(Result<int> result) => switch (result) {
        ResultSuccess(:int? valueOrNull) => 'success $valueOrNull',
        ResultError(:Object exception) => 'error $exception',
        ResultCancelled() => 'cancelled',
      };

      expect(describe(const ResultSuccess(value: 1)), 'success 1');
      expect(describe(ResultError(exception: 'boom')), 'error boom');
      expect(describe(const ResultCancelled()), 'cancelled');
    });
  });
}
