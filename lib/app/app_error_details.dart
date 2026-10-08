import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

final class AppErrorDetails {
  const AppErrorDetails._();

  static String format({
    required String stage,
    required Object error,
    required StackTrace stackTrace,
  }) {
    final lines = <String>[
      '考研复习错误详情',
      '环节：$stage',
      '异常类型：${error.runtimeType}',
    ];
    if (error is DatabaseException) {
      lines.add('SQLite 信息：${_withoutSqlArguments(error.toString())}');
      final resultCode = error.getResultCode();
      if (resultCode != null) lines.add('SQLite 错误码：$resultCode');
    } else {
      lines.add('错误信息：${_withoutSqlArguments(error.toString())}');
    }
    lines.addAll(<String>['调用栈：', stackTrace.toString()]);
    return lines.join('\n');
  }

  static String _withoutSqlArguments(String value) {
    final sqlDetailsStart = value.indexOf(" sql '");
    return sqlDetailsStart < 0 ? value : value.substring(0, sqlDetailsStart);
  }
}

void showAppErrorDetails(
  BuildContext context, {
  required String title,
  required String details,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(child: SelectableText(details)),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: details));
            if (!dialogContext.mounted) return;
            Navigator.pop(dialogContext);
            if (messenger == null || !messenger.mounted) return;
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('错误详情已复制')));
          },
          icon: const Icon(Icons.copy),
          label: const Text('复制错误详情'),
        ),
      ],
    ),
  );
}

void showAppErrorSnackBar(
  BuildContext context, {
  required String message,
  required String details,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: '查看原因',
          onPressed: () =>
              showAppErrorDetails(context, title: message, details: details),
        ),
      ),
    );
}
