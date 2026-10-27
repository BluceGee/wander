import 'package:flutter/material.dart';

import 'core/storage/app_store.dart';
import 'core/theme/app_theme.dart';
import 'features/assistant/assistant_page.dart';
import 'features/auth/login_page.dart';

class XnlApp extends StatelessWidget {
  const XnlApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return MaterialApp(
          title: 'XNL 工具箱',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: store.themeMode,
          // 打开即对话主页（豆包式）；首次启动先过欢迎/登录引导（可跳过）
          home: store.welcomeDone
              ? AssistantPage(app: store)
              : LoginPage(store: store),
        );
      },
    );
  }
}
