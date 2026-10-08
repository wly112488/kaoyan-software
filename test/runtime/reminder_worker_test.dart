import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/runtime/reminder_scheduler.dart';
import 'package:kaoyan_review/runtime/reminder_worker.dart';
import 'package:workmanager/workmanager.dart';

const _channelPrefix =
    'dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerFlutterApi.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unhandled reminder worker failures request WorkManager retry',
    () async {
      reminderCallbackDispatcher();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final codec = WorkmanagerFlutterApi.pigeonChannelCodec;

      Future<List<Object?>?> send(String channel, Object? message) async {
        ByteData? reply;
        await messenger.handlePlatformMessage(
          channel,
          codec.encodeMessage(message),
          (data) => reply = data,
        );
        return reply == null
            ? null
            : codec.decodeMessage(reply) as List<Object?>?;
      }

      final taskReply = await send('${_channelPrefix}executeTask', <Object?>[
        reminderWorkerTaskName,
        null,
      ]);

      expect(taskReply, <Object?>[false]);
    },
  );
}
