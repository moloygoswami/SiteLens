import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme.dart';
import 'router.dart';
import '../features/auth/session_router.dart';

class SiteLensApp extends ConsumerWidget {
  const SiteLensApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'SiteLens',
      debugShowCheckedModeBanner: false,
      theme: SiteLensTheme.lightTheme,
      home: const SessionRouter(),
      onGenerateRoute: AppRoutes.onGenerateRoute,
    );
  }
}
