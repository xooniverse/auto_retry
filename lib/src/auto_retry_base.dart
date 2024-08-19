import 'package:televerse/televerse.dart';

/// The `AutoRetry` plugin provides automatic retries for failed API requests
/// in Televerse, enhancing your bot's reliability and uptime.
///
/// This plugin handles rate limits and server errors by retrying failed
/// requests after specified intervals, making it easier to manage transient
/// failures without manually implementing retry logic.
class AutoRetry implements Transformer {
  /// The maximum duration after which we can actually abandon further retries.
  ///
  /// If the `retry_after` value exceeds this threshold, the error will be
  /// passed on, hence failing the request. This is useful if you don't want
  /// your bot to retry sending messages that are too old.
  ///
  /// The default value is `Duration.infinity`, meaning the threshold is
  /// disabled, and the plugin will wait any number of seconds.
  final Duration? maxDelay;

  /// The maximum number of retry attempts for a failed request.
  ///
  /// Specifies how many times a failed request should be retried before
  /// giving up. The default value is 3 attempts.
  final int maxRetryAttempts;

  /// Determines whether internal server errors should be rethrown.
  ///
  /// If set to `true`, the plugin will not retry requests that fail due to
  /// internal server errors (status code 500 and above) and will rethrow the
  /// error immediately. The defaults to `false`.
  final bool rethrowInternalServerErrors;

  /// Enables logging for retry attempts.
  ///
  /// If set to `true`, logs will be printed to the console for each retry
  /// attempt, providing insight into the retry process. The defaults to `false`.
  final bool enableLogs;

  /// Creates an instance of the `AutoRetry` plugin with the specified options.
  ///
  /// Example usage:
  ///
  /// ```dart
  /// final bot = Bot(Platform.environment["BOT_TOKEN"]!);
  ///
  /// bot.use(AutoRetry(
  ///   maxRetryAttempts: 5,
  ///   rethrowInternalServerErrors: true,
  ///   enableLogs: true,
  /// ));
  ///
  ///
  /// bot.command('start', (ctx) async {
  ///   // If this fails, the request is automatically retried.
  ///   await ctx.reply("Hello!.");
  /// });
  ///
  /// bot.start();
  /// ```
  ///
  /// - [maxDelay]: The maximum duration after which we actually abandon further retries.
  /// - [maxRetryAttempts]: The maximum number of retry attempts for a failed request. Default is 3 attempts.
  /// - [rethrowInternalServerErrors]: If `true`, internal server errors will not be retried. Default is `false`.
  /// - [enableLogs]: If `true`, retry attempts will be logged to the console. Default is `false`.
  const AutoRetry({
    this.maxDelay,
    this.maxRetryAttempts = 3,
    this.rethrowInternalServerErrors = false,
    this.enableLogs = false,
  });

  static const int _initialDelay = 3;

  Future<void> _pause(int seconds) {
    return Future.delayed(Duration(seconds: seconds));
  }

  @override
  Future<Map<String, dynamic>> transform(
    APICaller call,
    APIMethod method,
    Payload payload,
  ) async {
    int remainingAttempts = maxRetryAttempts;
    int nextDelay = _initialDelay;

    Future<void> pauseAndUpdateDelay() async {
      await _pause(nextDelay);
      nextDelay = (nextDelay * 2).clamp(0, Duration.secondsPerHour);
    }

    Future<Map<String, dynamic>> callApi() async {
      while (true) {
        try {
          return await call(method, payload);
        } catch (e) {
          // If the error is not a TelegramException, rethrow it
          if (e is! TelegramException) {
            _debugLog(
              "Non Telegram Exception occurred. (Error Type: ${e.runtimeType}). Rethrowing...",
            );
            rethrow;
          }

          _debugLog("[Exception]: ${e.code} | ${e.description}");

          // If it is a server error and rethrowInternalServerErrors is true, rethrow the exception
          if (e.isServerExeption && rethrowInternalServerErrors) {
            _debugLog(
              "Internal Server Error occurred (code: ${e.code}) | Rethrowing as you've set [rethrowInternalServerErrors] to `true`.",
            );
            rethrow;
          }

          // Get the retry after parameter, yeah, we're going for it
          final retryAfter = e.parameters?.retryAfter;
          final max = (maxDelay?.inSeconds ?? double.infinity);

          if (retryAfter is int && retryAfter > max) {
            rethrow;
          }

          if (retryAfter is int && retryAfter <= max) {
            _debugLog(
              "Hit rate limit, will retry '$method' after $retryAfter seconds",
            );

            await _pause(retryAfter);
            nextDelay = _initialDelay;
          } else if (e.isServerExeption) {
            _debugLog(
              "Internal server error, will retry '$method' after $nextDelay seconds",
            );

            await pauseAndUpdateDelay();
          }
        }
        // Count retry attempts and throw when out of attempts
        if (remainingAttempts-- <= 0) {
          if (enableLogs) {
            print(
              "Max retry attempts reached for '$method'",
            );
          }
          throw TeleverseException(
            "Retry limit exceeded",
            type: TeleverseExceptionType.requestFailed,
          );
        }
      }
    }

    return await callApi();
  }

  void _debugLog(String msg) {
    if (enableLogs) {
      print("[Auto-Retry] $msg");
    }
  }
}
