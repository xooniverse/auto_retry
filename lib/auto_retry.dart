/// Auto Retry Plugin for Televerse
///
/// The `AutoRetry` plugin provides automatic retries for failed API requests
/// in Televerse, enhancing your bot's reliability and uptime.
///
/// This plugin handles rate limits and server errors by retrying failed
/// requests after specified intervals, making it easier to manage transient
/// failures without manually implementing retry logic.
library;

export 'src/auto_retry_base.dart';
