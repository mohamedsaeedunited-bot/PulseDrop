import 'dart:convert';
import 'dart:io';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

enum UpdateCheckStatus {
  updateAvailable,
  upToDate,
  repoPrivateOrNoRelease,
  networkError,
}

class UpdateInfo {
  final UpdateCheckStatus status;
  final String latestVersion;
  final String releaseNotes;
  final String? downloadUrl;
  final int fileSizeBytes;

  UpdateInfo({
    required this.status,
    this.latestVersion = '',
    this.releaseNotes = '',
    this.downloadUrl,
    this.fileSizeBytes = 0,
  });
}

class AppUpdateService {
  static const String repoOwner = 'mohamedsaeedunited-bot';
  static const String repoName = 'PulseDrop';
  static const String currentVersion = '5.3.0';

  static Future<UpdateInfo> checkForUpdate() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
      );
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'PulseDrop-Android-App');
      req.headers.set('Accept', 'application/vnd.github+json');

      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode == 404 || res.statusCode == 403) {
        return UpdateInfo(status: UpdateCheckStatus.repoPrivateOrNoRelease);
      }
      if (res.statusCode != 200) {
        return UpdateInfo(status: UpdateCheckStatus.networkError);
      }

      final body = await utf8.decoder.bind(res).join();
      final data = jsonDecode(body);

      final rawTag = (data['tag_name'] ?? '').toString().trim();
      final latestVer = rawTag.replaceFirst(RegExp(r'^[vV]'), '');
      final notes = (data['body'] ?? '').toString().trim();

      String? apkUrl;
      int apkSize = 0;
      final assets = data['assets'];
      if (assets is List) {
        for (final item in assets) {
          final name = (item['name'] ?? '').toString().toLowerCase();
          if (name.endsWith('.apk')) {
            apkUrl = item['browser_download_url']?.toString();
            apkSize = (item['size'] is int) ? item['size'] as int : 0;
            break;
          }
        }
      }

      if (apkUrl != null && _isNewerVersion(latestVer, currentVersion)) {
        return UpdateInfo(
          status: UpdateCheckStatus.updateAvailable,
          latestVersion: latestVer,
          releaseNotes: notes.isNotEmpty
              ? notes
              : 'إصدار جديد جاهز للتثبيت المباشر فوق النسخة الحالية بدون مسح بياناتك.',
          downloadUrl: apkUrl,
          fileSizeBytes: apkSize,
        );
      }

      return UpdateInfo(
        status: UpdateCheckStatus.upToDate,
        latestVersion: latestVer.isNotEmpty ? latestVer : currentVersion,
      );
    } catch (_) {
      return UpdateInfo(status: UpdateCheckStatus.networkError);
    } finally {
      client.close(force: true);
    }
  }

  static bool _isNewerVersion(String latest, String current) {
    final lParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final cParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final maxLen = lParts.length > cParts.length ? lParts.length : cParts.length;
    for (int i = 0; i < maxLen; i++) {
      final l = i < lParts.length ? lParts[i] : 0;
      final c = i < cParts.length ? cParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  static Future<String?> downloadAndInstall(
    UpdateInfo info, {
    required void Function(double progress, int received, int total) onProgress,
  }) async {
    if (info.downloadUrl == null) return 'رابط التحميل غير متوفر';

    try {
      await Permission.requestInstallPackages.request();
    } catch (_) {}

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    RandomAccessFile? raf;

    try {
      final dir = (await getExternalStorageDirectory()) ??
          await getTemporaryDirectory();
      final apkFile = File('${dir.path}/PulseDrop_v${info.latestVersion}.apk');
      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final req = await client.getUrl(Uri.parse(info.downloadUrl!));
      req.headers.set('User-Agent', 'PulseDrop-Android-App');
      final res = await req.close().timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        return 'فشل تحميل التحديث (كود ${res.statusCode})';
      }

      final totalBytes = res.contentLength > 0
          ? res.contentLength
          : info.fileSizeBytes;
      int received = 0;
      raf = await apkFile.open(mode: FileMode.write);

      await for (final chunk in res) {
        await raf.writeFrom(chunk);
        received += chunk.length;
        final pct = totalBytes > 0 ? (received / totalBytes).clamp(0.0, 1.0) : 0.0;
        onProgress(pct, received, totalBytes);
      }

      await raf.flush();
      await raf.close();
      raf = null;

      final openRes = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );
      if (openRes.type != ResultType.done) {
        return 'تم تحميل التحديث لكن تعذر فتح المثبت: ${openRes.message}';
      }
      return null;
    } catch (e) {
      try {
        await raf?.close();
      } catch (_) {}
      return 'حدث خطأ أثناء تحميل التحديث: $e';
    } finally {
      client.close(force: true);
    }
  }
}
