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
