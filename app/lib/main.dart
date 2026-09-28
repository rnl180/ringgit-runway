import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'ui/theme.dart';

void main() {
  runApp(
    // Don't silently retry failed requests; screens offer "Try again".
    ProviderScope(retry: (_, _) => null, child: const RinggitRunwayApp()),
  );
}

class RinggitRunwayApp extends ConsumerWidget {
  const RinggitRunwayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Ringgit Runway',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
