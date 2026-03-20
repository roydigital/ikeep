import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_providers.dart';
import 'providers/settings_provider.dart';
import 'routing/app_router.dart';
import 'theme/app_theme.dart';

class IkeepApp extends ConsumerWidget {
  const IkeepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authSessionBootstrapProvider);
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider);

    return MaterialApp.router(
      title: 'Ikeep',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,
      routerConfig: router,
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF040124), 
                      const Color(0xFF130A38), 
                      const Color(0xFF0C0A20)
                    ]
                  : [
                      const Color(0xFFF7F5FC), 
                      const Color(0xFFEBE6F5), 
                      const Color(0xFFFFFFFF)
                    ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: child,
        );
      },
    );
  }
}
