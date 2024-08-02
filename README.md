
![Pub Version](https://img.shields.io/pub/v/auto_retry)
![GitHub Issues](https://img.shields.io/github/issues/xooniverse/auto_retry)
![GitHub Stars](https://img.shields.io/github/stars/xooniverse/auto_retry)

# AutoRetry Plugin for Televerse

The AutoRetry plugin for Televerse provides automatic retries for failed API requests, handling rate limits and server errors to enhance your bot's reliability and uptime. This plugin can be seamlessly integrated into your Televerse bot to ensure it remains functional even in the face of temporary network issues or rate limits imposed by the Telegram API.

## Installation

Add the plugin to your `pubspec.yaml`:

```yaml
dependencies:
  auto_retry: ^1.0.0
```

Then, run:

```bash
dart pub get
```

## Usage

To use the `AutoRetry` plugin, you simply need to attach it to your bot with the desired options.

### Example

```dart
import 'dart:io';
import 'package:televerse/televerse.dart';
import 'package:auto_retry/auto_retry.dart';

void main(List<String> args) async {
  // Create aan API instance or a Bot Instance passing the bot token
  final bot = Bot(
    Platform.environment["BOT_TOKEN"]!,
  );

  // Take an instance of the Auto Retry, feel free to check the different options
  const autoRetry = AutoRetry(
    enableLogs: true,
  );

  // Attach the auto retry plugin to the Bot - that's it. You're all set.
  bot.use(autoRetry);

  bot.command("start", (ctx) {
    // Just spam the Bot API Server (and hit some limits)
    // (You don't have to do this - this part is just to illustrate it works 🤖)
    for (var i = 0; i < 150; i++) {
      ctx.reply("Hello $i").ignore();
    }
  });

  // Start the bot
  await bot.start();
}
```

### Options

The `AutoRetryOptions` class allows you to configure the behavior of the plugin:

- **maxDelaySeconds**: The maximum number of seconds to wait before retrying a request. Default is 3 seconds.
- **maxRetryAttempts**: The maximum number of retry attempts for a failed request. Default is 3 attempts.
- **rethrowInternalServerErrors**: If true, internal server errors (status code 500 and above) will not be retried and will be rethrown immediately. Default is false.
- **enableLogs**: If true, logs will be printed to the console for each retry attempt. Default is false.

### Features

- **Automatic Retry**: Automatically retries failed API requests due to rate limits or server errors.
- **Exponential Backoff**: Implements exponential backoff with a cap at one hour for retry attempts.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request on GitHub.

## License

This project is licensed under the MIT License.

---

If you find this plugin useful, please consider giving it a star on [GitHub](https://github.com/xooniverse/auto_retry) and reporting any issues you encounter.

