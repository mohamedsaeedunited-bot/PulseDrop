import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PulseDropApp());
}

class PulseDropApp extends StatefulWidget {
  const PulseDropApp({super.key});

  @override
  State<PulseDropApp> createState() => _PulseDropAppState();
}

class _PulseDropAppState extends State<PulseDropApp> {
  bool _isDark = false;
  bool _isArabic = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDark = prefs.getBool('is_dark') ?? false;
      _isArabic = prefs.getBool('is_arabic') ?? true;
    });
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isDark = !_isDark);
    await prefs.setBool('is_dark', _isDark);
  }

  Future<void> _toggleLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isArabic = !_isArabic);
    await prefs.setBool('is_arabic', _isArabic);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PulseDrop',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        return Directionality(
          textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        );
      },
      home: HomeScreen(
        isDark: _isDark,
        isArabic: _isArabic,
        onToggleTheme: _toggleTheme,
        onToggleLanguage: _toggleLanguage,
      ),
    );
  }
}
