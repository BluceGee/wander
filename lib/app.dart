import 'package:flutter/material.dart';

import 'core/storage/app_store.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_page.dart';

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
          home: HomePage(store: store),
        );
      },
    );
  }
}
