class AppStrings {
  final bool isArabic;
  const AppStrings(this.isArabic);

  String get appName => 'PulseDrop';
  String get scanningRadar => isArabic ? 'جاري البحث عن الأجهزة القريبة...' : 'Scanning nearby devices...';
  String get connectSameWifi => isArabic
      ? 'تأكد أن الجهازين على نفس الواي فاي أو الهوتسبوت'
      : 'Connect both devices to the same Wi-Fi or Hotspot';
  String get tapDeviceToSend => isArabic ? 'اضغط على أي جهاز للإرسال' : 'Tap any device to send';
  String get multiDropMode => isArabic ? 'إرسال جماعي' : 'Multi-Drop';
  String get sendToSelected => isArabic ? 'إرسال للمحددين' : 'Send to Selected';
  String get stealthOn => isArabic ? 'وضع التخفي نشط (جهازك مخفي)' : 'Stealth Mode On (Hidden)';
  String get stealthOff => isArabic ? 'وضع التخفي متوقف' : 'Stealth Mode Off';
  String get send => isArabic ? 'إرسال' : 'Send';
  String get history => isArabic ? 'السجل' : 'History';
  String get settings => isArabic ? 'الإعدادات' : 'Settings';
  String get quickChatHint => isArabic ? 'شات محلي: اكتب نص أو رابط...' : 'Local chat: type text or link...';
  String get localChat => isArabic ? 'الشات المحلي' : 'Local Chat';
  String get copied => isArabic ? 'تم النسخ!' : 'Copied!';
  String get copy => isArabic ? 'نسخ' : 'Copy';
  String get deviceName => isArabic ? 'اسم جهازك' : 'Device Name';
  String get renameDevice => isArabic ? 'تغيير اسم الجهاز' : 'Rename Device';
  String get save => isArabic ? 'حفظ' : 'Save';
  String get cancel => isArabic ? 'إلغاء' : 'Cancel';
  String get activeTransfers => isArabic ? 'عمليات النقل الجارية' : 'Active Transfers';
  String get noHistory => isArabic ? 'لا توجد ملفات مستلمة أو مرسلة بعد' : 'No transferred files yet';
  String get received => isArabic ? 'مستلم' : 'Received';
  String get sent => isArabic ? 'مرسل' : 'Sent';
  String get openFile => isArabic ? 'فتح' : 'Open';
  String get webShareTitle => isArabic ? 'المشاركة والبث عبر المتصفح' : 'Web Share & Instant Stream';
  String get webShareDesc => isArabic
      ? 'امسح الـ QR أو افتح الرابط من الكمبيوتر أو الآيفون بدون نت'
      : 'Scan QR or open link from PC or iPhone offline';
  String get scanQrTab => isArabic ? 'مسح QR' : 'Scan QR';
  String get showQrTab => isArabic ? 'بوابة الويب' : 'Web Portal';
  String get hotspotTab => isArabic ? 'هوتسبوت QR' : 'Hotspot QR';
  String get addFilesForWeb => isArabic ? 'اختر ملفات للمشاركة أو البث المباشر' : 'Pick files to share or stream';
  String get sharedFilesCount => isArabic ? 'ملفات جاهزة:' : 'Ready files:';
  String get clearList => isArabic ? 'مسح القائمة' : 'Clear';
  String get pickTargetDevice => isArabic ? 'اختر الجهاز المستلم' : 'Select Target Device';
  String get noDevicesFound => isArabic
      ? 'لا توجد أجهزة PulseDrop متصلة حالياً. استخدم بوابة الويب أو أدخل الـ IP.'
      : 'No PulseDrop devices found yet. Use Web Portal or enter IP.';
  String get enterIpManually => isArabic ? 'إدخال IP يدوياً' : 'Enter IP Manually';
  String get connectAndSend => isArabic ? 'اتصال وإرسال' : 'Connect & Send';
  String get serverRunning => isArabic ? 'الرادار نشط' : 'Radar Active';
  String get offline => isArabic ? 'غير متصل بواي فاي' : 'No Wi-Fi';
  String get completed => isArabic ? 'اكتمل' : 'Completed';
  String get failed => isArabic ? 'فشل' : 'Failed';
  String get clearHistory => isArabic ? 'مسح السجل' : 'Clear History';
  String get webPinLabel => isArabic ? 'الرقم السري لبوابة الويب (PIN)' : 'Web Portal PIN Lock';
  String get autoAcceptLabel => isArabic ? 'قبول تلقائي للملفات' : 'Auto-Accept Files';
  String get darkModeLabel => isArabic ? 'الوضع الليلي (Dark Mode)' : 'Dark Mode';
  String get languageLabel => isArabic ? 'اللغة (العربية / English)' : 'Language (Arabic / English)';
  String get statsTitle => isArabic ? 'إحصائيات النقل' : 'Transfer Stats';
  String get totalTransferred => isArabic ? 'إجمالي المنقول' : 'Total Transferred';
  String get filesCount => isArabic ? 'عدد الملفات' : 'Files Count';
  String get allTab => isArabic ? 'الكل' : 'All';
  String get imagesTab => isArabic ? 'صور' : 'Images';
  String get videosTab => isArabic ? 'فيديو' : 'Videos';
  String get docsTab => isArabic ? 'مستندات' : 'Docs';
  String get appsTab => isArabic ? 'تطبيقات' : 'Apps';
  String get hotspotName => isArabic ? 'اسم شبكة الهوتسبوت' : 'Hotspot Name (SSID)';
  String get hotspotPass => isArabic ? 'كلمة السر' : 'Password';
  String get hotspotHint => isArabic
      ? 'أدخل بيانات هوتسبوت موبايلك لتوليد كود اتصال سريع للطرف الآخر'
      : 'Enter your phone hotspot details to generate a quick Wi-Fi QR';
}
