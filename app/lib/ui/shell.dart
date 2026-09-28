import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/providers.dart';
import 'screens/add_entry_sheet.dart';
import 'widgets/common.dart';

const tabs = [
  (
    path: '/home',
    label: 'Home',
    icon: Icons.flight_takeoff_outlined,
    selected: Icons.flight_takeoff,
  ),
  (
    path: '/activity',
    label: 'Activity',
    icon: Icons.receipt_long_outlined,
    selected: Icons.receipt_long,
  ),
  (
    path: '/insights',
    label: 'Insights',
    icon: Icons.insights_outlined,
    selected: Icons.insights,
  ),
  (
    path: '/plan',
    label: 'Bills & plan',
    icon: Icons.event_note_outlined,
    selected: Icons.event_note,
  ),
];

/// Bottom navigation, month switcher and the Add button shared by all tabs.
class AppShell extends ConsumerWidget {
  final Widget child;
  final String location;
  const AppShell({super.key, required this.child, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = tabs.indexWhere((t) => location.startsWith(t.path));
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const MonthSwitcher(),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (v) async {
              if (v == 'signout') {
                final ok = await confirm(
                  context,
                  title: 'Sign out?',
                  message: 'Your data stays saved on the server.',
                  action: 'Sign out',
                  destructive: false,
                );
                if (ok) await ref.read(sessionProvider.notifier).signOut();
              }
            },
            itemBuilder: (_) {
              final s = ref.read(sessionProvider);
              return [
                if (s is SignedIn && s.user.email.isNotEmpty)
                  PopupMenuItem(enabled: false, child: Text(s.user.email)),
                const PopupMenuItem(value: 'signout', child: Text('Sign out')),
              ];
            },
          ),
        ],
      ),
      body: child,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddEntrySheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index < 0 ? 0 : index,
        onDestinationSelected: (i) => context.go(tabs[i].path),
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selected),
              label: t.label,
            ),
        ],
      ),
    );
  }
}
