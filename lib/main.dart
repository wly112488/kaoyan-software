import 'package:flutter/material.dart';

void main() {
  runApp(const KaoyanReviewApp());
}

class KaoyanReviewApp extends StatelessWidget {
  const KaoyanReviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '考研碎片复习',
      home: Scaffold(
        appBar: AppBar(title: const Text('考研碎片复习')),
        body: const SizedBox.shrink(),
      ),
    );
  }
}
