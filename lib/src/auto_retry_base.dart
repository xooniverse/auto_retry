import 'package:televerse/televerse.dart';

/// The `AutoRetry` plugin provides automatic retries for failed API requests
/// in Televerse, enhancing your bot's reliability and uptime.
///
/// This plugin handles rate limits and server errors by retrying failed
/// requests after specified intervals, making it easier to manage transient
/// failures without manually implementing retry logic.
///
/// Example usage:
/// ```dart
/// final bot = Bot('YOUR_BOT_TOKEN');
///
/// bot.plugin(AutoRetryPlugin(
///   maxRetryAttempts: 5,
///   rethrowInternalServerErrors: true,
///   enableLogs: true,
/// ));
///
/// bot.command('start', (ctx) async {
///   // If this fails, the request is automatically retried
///   await ctx.reply("Hello!");
/// });
///
/// await bot.start();
/// ```
class AutoRetryPlugin<CTX extends Context> implements TransformerPlugin<CTX> {
  /// The maximum duration after which we can actually abandon further retries.
  ///
  /// If the `retry_after` value exceeds this threshold, the error will be
  /// passed on, hence failing the request. This is useful if you don't want
  /// your bot to retry sending messages that are too old.
  ///
  /// The default value is `null`, meaning the threshold is disabled, and the
  /// plugin will wait any number of seconds.
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
  /// error immediately. The default is `false`.
  final bool rethrowInternalServerErrors;

  /// Enables logging for retry attempts.
  ///
  /// If set to `true`, logs will be printed to the console for each retry
  /// attempt, providing insight into the retry process. The default is `false`.
  final bool enableLogs;

  /// Creates an instance of the `AutoRetry` plugin with the specified options.
  ///
  /// Parameters:
  /// - [maxDelay]: The maximum duration after which we abandon further retries
  /// - [maxRetryAttempts]: The maximum number of retry attempts (default: 3)
  /// - [rethrowInternalServerErrors]: Whether to rethrow server errors (default: false)
  /// - [enableLogs]: Whether to enable retry logging (default: false)
  const AutoRetryPlugin({
    this.maxDelay,
    this.maxRetryAttempts = 3,
    this.rethrowInternalServerErrors = false,
    this.enableLogs = false,
  });

  @override
  String get name => 'auto-retry';

  @override
  String get version => '2.0.0';

  @override
  List<String> get dependencies => [];

  @override
  String? get description =>
      'Automatically retries failed API requests with exponential backoff';

  @override
  void install(Bot<CTX> bot) {
    bot.api.use(transformer);
  }

  @override
  void uninstall(Bot<Context> bot) {
    bot.api.removeTransformer(transformer);
  }

  @override
  Transformer get transformer => _AutoRetryTransformer(
        maxDelay: maxDelay,
        maxRetryAttempts: maxRetryAttempts,
        rethrowInternalServerErrors: rethrowInternalServerErrors,
        enableLogs: enableLogs,
      );
}

/// Internal transformer that handles the retry logic.
class _AutoRetryTransformer extends Transformer {
  /// The maximum duration after which we abandon further retries.
  final Duration? maxDelay;

  /// The maximum number of retry attempts for a failed request.
  final int maxRetryAttempts;

  /// Whether internal server errors should be rethrown.
  final bool rethrowInternalServerErrors;

  /// Whether logging is enabled for retry attempts.
  final bool enableLogs;

  /// The initial delay in seconds before the first retry.
  static const int _initialDelay = 3;

  /// Creates the auto-retry transformer.
  const _AutoRetryTransformer({
    this.maxDelay,
    required this.maxRetryAttempts,
    required this.rethrowInternalServerErrors,
    required this.enableLogs,
  });

  @override
  String get description =>
      'Automatic retry transformer with exponential backoff';

  @override
  Future<Map<String, dynamic>> transform(
    APICaller call,
    APIMethod method, [
    Payload? payload,
  ]) async {
    int remainingAttempts = maxRetryAttempts;
    int nextDelay = _initialDelay;

    while (true) {
      try {
        return await call(method, payload);
      } catch (e) {
        // If the error is not a TelegramException, rethrow it immediately
        if (e is! TelegramException) {
          _debugLog(
            "Non-Telegram exception occurred (${e.runtimeType}). Rethrowing...",
          );
          rethrow;
        }

        _debugLog("Caught error ${e.code} | ${e.description}");

        // Don't retry bad request errors (400) - these are client errors
        if (e.code == 400) {
          _debugLog(
            "Bad Request error (400). Please check your request parameters. Not retrying.",
          );
          rethrow;
        }

        // Handle internal server errors based on configuration
        if (e.isServerException && rethrowInternalServerErrors) {
          _debugLog(
            "Internal server error (${e.code}) occurred. Rethrowing as configured.",
          );
          rethrow;
        }

        // Check if we've exceeded max retry attempts
        if (remainingAttempts <= 0) {
          _debugLog(
            "Max retry attempts ($maxRetryAttempts) reached for '$method'",
          );
          throw TeleverseException(
            "Retry limit exceeded for method '$method'",
            description: "Maximum retry attempts ($maxRetryAttempts) reached",
            type: TeleverseExceptionType.requestFailed,
          );
        }

        // Handle rate limiting (429) with retry_after
        final retryAfter = e.parameters?.retryAfter;
        final maxDelaySeconds = maxDelay?.inSeconds ?? double.infinity;

        if (retryAfter != null && retryAfter > maxDelaySeconds) {
          _debugLog(
            "Retry delay ($retryAfter seconds) exceeds maximum allowed delay "
            "(${maxDelay?.inSeconds} seconds). Not retrying.",
          );
          rethrow;
        }

        Duration delayDuration;
        if (retryAfter != null && retryAfter <= maxDelaySeconds) {
          // Rate limit hit - use the exact retry_after value
          delayDuration = Duration(seconds: retryAfter);
          _debugLog(
            "Rate limit hit. Retrying '$method' after $retryAfter seconds "
            "(attempt ${maxRetryAttempts - remainingAttempts + 1}/$maxRetryAttempts)",
          );
          // Reset exponential backoff delay after rate limit
          nextDelay = _initialDelay;
        } else if (e.isServerException) {
          // Server error - use exponential backoff
          delayDuration = Duration(seconds: nextDelay);
          _debugLog(
            "Server error (${e.code}). Retrying '$method' after $nextDelay seconds "
            "(attempt ${maxRetryAttempts - remainingAttempts + 1}/$maxRetryAttempts)",
          );
          // Update delay for next retry (exponential backoff with cap)
          nextDelay = (nextDelay * 2).clamp(0, Duration.secondsPerHour);
        } else {
          // Other errors - use current delay
          delayDuration = Duration(seconds: nextDelay);
          _debugLog(
            "Retryable error (${e.code}). Retrying '$method' after $nextDelay seconds "
            "(attempt ${maxRetryAttempts - remainingAttempts + 1}/$maxRetryAttempts)",
          );
          nextDelay = (nextDelay * 2).clamp(0, Duration.secondsPerHour);
        }

        // Wait before retrying
        await Future.delayed(delayDuration);
        remainingAttempts--;
      }
    }
  }

  /// Logs debug messages if logging is enabled.
  void _debugLog(String message) {
    if (enableLogs) {
      final timestamp = DateTime.now().toIso8601String();
      print('[$timestamp] [AutoRetry] $message');
    }
  }
}

/// Extension to check if a TelegramException is a server exception.
extension _TelegramExceptionExtension on TelegramException {
  /// Checks if this exception is a server error (5xx status codes).
  bool get isServerException => code >= 500;
}
