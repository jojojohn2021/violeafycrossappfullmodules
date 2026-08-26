import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../core/router/app_router.dart';

class LeafyMainApp extends StatelessWidget {
  const LeafyMainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Leafy - Connect,Refer,Earn',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      routerConfig: appRouter,
    );
  }
}
