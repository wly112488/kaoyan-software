import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_services.dart';
import 'app_shell.dart';

typedef AppServicesLoader = Future<AppServices> Function();

class KaoyanReviewApp extends StatefulWidget {
  const KaoyanReviewApp({super.key, this.loadServices});

  final AppServicesLoader? loadServices;

  @override
  State<KaoyanReviewApp> createState() => _KaoyanReviewAppState();
}

class _KaoyanReviewAppState extends State<KaoyanReviewApp> {
  late Future<AppServices> _servicesFuture;
  AppServices? _services;

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  void _startLoading() {
    _servicesFuture = Future<AppServices>.sync(
      (widget.loadServices ?? AppServices.openProduction),
    );
  }

  void _retry() {
    setState(_startLoading);
  }

  @override
  void dispose() {
    final services = _services;
    if (services != null) unawaited(services.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '考研碎片复习',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const <Locale>[Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF356B78)),
      home: FutureBuilder<AppServices>(
        future: _servicesFuture,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            _services = snapshot.data;
            return AppShell(services: snapshot.requireData);
          }
          if (snapshot.hasError) {
            return _StartupFailureScreen(
              error: snapshot.error!,
              onRetry: _retry,
            );
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }
}

class _StartupFailureScreen extends StatelessWidget {
  const _StartupFailureScreen({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.storage_rounded, size: 48),
              const SizedBox(height: 16),
              Text('启动初始化失败', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('本地数据或提醒服务暂时无法初始化。请重试。', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              SelectableText(
                '错误详情：${error.runtimeType}: $error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }
}
