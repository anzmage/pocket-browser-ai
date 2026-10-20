import 'package:flutter/material.dart';
import 'ui/browser_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PocketBrowserApp());
}

class PocketBrowserApp extends StatelessWidget {
  const PocketBrowserApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pocket Browser AI',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: const BrowserPage(),
  );
}
