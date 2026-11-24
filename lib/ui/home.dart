import 'package:flutter/material.dart';
import '../app_state.dart';
import 'gallery_tab.dart';
import 'people_tab.dart';
import 'settings_tab.dart';

class Home extends StatefulWidget {
  const Home({super.key});
  @override State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final state = AppState();
  int tab = 0;
  @override void initState() { super.initState(); state.init(); }
  @override void dispose() { state.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('PIC_AI 私人相簿')),
      body: SafeArea(child: IndexedStack(index: tab, children: [
        GalleryTab(state: state),
        PeopleTab(state: state),
        SettingsTab(state: state),
      ])),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.photo_library_outlined), selectedIcon: Icon(Icons.photo_library), label: '相簿'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: '家人'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '設定'),
        ],
      ),
    ),
  );
}
