import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../services/transfer_engine.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  final TransferEngine engine;
  final AppStrings strings;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onToggleLanguage;

  const SettingsScreen({
    super.key,
    required this.engine,
    required this.strings,
    required this.isDark,
    required this.onToggleTheme,
    required this.onToggleLanguage,
  });

  @override
  Widget build(BuildContext context) {
    final s = strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.settings, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: AnimatedBuilder(
        animation: engine,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Stats Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.statsTitle,
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatBytes(engine.totalBytesTransferred),
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                            ),
                            Text(s.totalTransferred, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${engine.history.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                            ),
                            Text(s.filesCount, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.lock_rounded, color: AppColors.primary),
                      title: Text(s.webPinLabel),
                      subtitle: Text('PIN: ${engine.webPin}'),
                      value: engine.pinEnabled,
                      onChanged: (v) => engine.setPinEnabled(v),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.verified_user_rounded, color: AppColors.success),
                      title: Text(s.autoAcceptLabel),
                      value: engine.autoAccept,
                      onChanged: (v) => engine.setAutoAccept(v),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.dark_mode_rounded, color: AppColors.accent),
                      title: Text(s.darkModeLabel),
                      value: isDark,
                      onChanged: (_) => onToggleTheme(),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.language_rounded, color: AppColors.primary),
                      title: Text(s.languageLabel),
                      trailing: Text(
                        s.isArabic ? 'العربية' : 'English',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
                      ),
                      onTap: onToggleLanguage,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
