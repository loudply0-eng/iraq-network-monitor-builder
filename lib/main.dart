import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class AppPreferences {
  static final ValueNotifier<bool> english = ValueNotifier<bool>(false);
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);
  static final ValueNotifier<int> accentIndex = ValueNotifier<int>(0);
  static final ValueNotifier<bool> networkAlertsEnabled = ValueNotifier<bool>(false);

  static const List<Color> accentColors = <Color>[
    Color(0xFF16BCEB), Color(0xFF3B82F6), Color(0xFF8B5CF6),
    Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEC4899),
    Color(0xFFEF4444), Color(0xFF14B8A6),
  ];

  static Future<File> _settingsFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/app-settings.json');
  }

  static Future<Map<String, dynamic>> _readSettings() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return <String, dynamic>{};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }

  static Future<void> load() async {
    final data = await _readSettings();
    english.value = data['language'] == 'en';
    themeMode.value = switch (data['themeMode']) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    final savedAccent = ((data['accentIndex'] as num?)?.toInt() ?? 0)
        .clamp(0, accentColors.length - 1).toInt();
    accentIndex.value = savedAccent;
    networkAlertsEnabled.value = data['networkAlertsEnabled'] == true;
  }

  static Future<void> _save(String key, Object value) async {
    try {
      final file = await _settingsFile();
      final data = await _readSettings();
      data[key] = value;
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {
      // Preferences remain usable for this session if storage is unavailable.
    }
  }

  static Future<void> setEnglish(bool value) async {
    english.value = value;
    await _save('language', value ? 'en' : 'ar');
  }

  static Future<void> setThemeMode(ThemeMode value) async {
    themeMode.value = value;
    final encoded = switch (value) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    };
    await _save('themeMode', encoded);
  }

  static Future<void> setAccentIndex(int value) async {
    final safeValue = value.clamp(0, accentColors.length - 1).toInt();
    accentIndex.value = safeValue;
    await _save('accentIndex', safeValue);
  }

  static Future<void> setNetworkAlertsEnabled(bool value) async {
    networkAlertsEnabled.value = value;
    await _save('networkAlertsEnabled', value);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferences.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _theme(Brightness brightness, Color accent) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
        .copyWith(
      primary: accent,
      secondary: accent,
      surface: dark ? const Color(0xFF0D2038) : Colors.white,
      onSurface: dark ? Colors.white : const Color(0xFF182230),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF061426) : const Color(0xFFF3F6FA),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF071A31) : Colors.white,
        foregroundColor: dark ? Colors.white : const Color(0xFF172033),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: dark ? Colors.white : const Color(0xFF172033),
          fontSize: 17,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: dark ? const Color(0xFF0D2038) : Colors.white,
        elevation: dark ? 0 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: dark ? const Color(0xFF041323) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([
          AppPreferences.english,
          AppPreferences.themeMode,
          AppPreferences.accentIndex,
          AppPreferences.networkAlertsEnabled,
        ]),
        builder: (context, _) {
          final accent = AppPreferences.accentColors[AppPreferences.accentIndex.value];
          return MaterialApp(
            title: 'IRAQ NETWORK MONITOR',
            theme: _theme(Brightness.light, accent),
            darkTheme: _theme(Brightness.dark, accent),
            themeMode: AppPreferences.themeMode.value,
            builder: (context, child) => Directionality(
              textDirection: AppPreferences.english.value ? TextDirection.ltr : TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
            home: const MapScreen(),
          );
        },
      );
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.abrjiraq/tower');
  bool get isEnglish => AppPreferences.english.value;
  String tr(String ar, String en) => isEnglish ? en : ar;

  Future<void> showSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => ValueListenableBuilder<bool>(
        valueListenable: AppPreferences.english,
        builder: (context, english, _) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(english ? 'Settings' : 'الإعدادات', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.language, color: Colors.lightBlueAccent),
                title: Text(english ? 'App language' : 'لغة التطبيق', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                trailing: DropdownButton<bool>(
                  value: english, dropdownColor: Theme.of(context).colorScheme.surface,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  items: const [
                    DropdownMenuItem(value: false, child: Text('العربية')),
                    DropdownMenuItem(value: true, child: Text('English')),
                  ],
                  onChanged: (value) { if (value != null) AppPreferences.setEnglish(value); },
                ),
              ),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: AppPreferences.themeMode,
                builder: (context, selectedMode, _) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.contrast, color: Theme.of(context).colorScheme.primary),
                  title: Text(english ? 'Appearance' : 'مظهر التطبيق'),
                  trailing: DropdownButton<ThemeMode>(
                    value: selectedMode,
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(value: ThemeMode.dark, child: Text(english ? 'Dark' : 'داكن')),
                      DropdownMenuItem(value: ThemeMode.light, child: Text(english ? 'Light' : 'فاتح')),
                      DropdownMenuItem(value: ThemeMode.system, child: Text(english ? 'System' : 'حسب الجهاز')),
                    ],
                    onChanged: (value) {
                      if (value != null) AppPreferences.setThemeMode(value);
                    },
                  ),
                ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: AppPreferences.accentIndex,
                builder: (context, selectedAccent, _) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(english ? 'Accent color' : 'لون التطبيق',
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: List.generate(AppPreferences.accentColors.length, (index) {
                          final color = AppPreferences.accentColors[index];
                          final selected = index == selectedAccent;
                          return InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => AppPreferences.setAccentIndex(index),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color,
                                border: Border.all(
                                  color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                                  width: selected ? 3 : 1,
                                ),
                              ),
                              child: selected ? const Icon(Icons.check, color: Colors.white, size: 19) : null,
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: AppPreferences.networkAlertsEnabled,
                builder: (context, enabled, _) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(Icons.notifications_active_outlined,
                      color: Theme.of(context).colorScheme.primary),
                  title: Text(english ? 'Network alerts' : 'تنبيهات الشبكة'),
                  subtitle: Text(english
                      ? 'While the app is open: signal drops, cell changes and 5G detection'
                      : 'أثناء فتح التطبيق: ضعف الإشارة وتغيّر البرج واكتشاف 5G'),
                  value: enabled,
                  onChanged: (value) async {
                    if (value) {
                      final permission = await Permission.notification.request();
                      if (!permission.isGranted) {
                        if (sheetContext.mounted) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(content: Text(english
                                ? 'Allow notifications in Android settings to enable alerts.'
                                : 'اسمح بالإشعارات من إعدادات أندرويد لتفعيل التنبيهات.')),
                          );
                        }
                        return;
                      }
                    }
                    await AppPreferences.setNetworkAlertsEnabled(value);
                  },
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: checkingForUpdates ? null : () { Navigator.of(sheetContext).pop(); checkForUpdates(showPrompt: true); },
                icon: checkingForUpdates ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.system_update_alt),
                label: Text(english ? 'Check for app updates' : 'فحص تحديثات التطبيق'),
              ),
              if (updateStatus.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(updateStatus, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
              ),
              if (pendingVersion != null) ...[
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: showUpdateDialog,
                  icon: Icon(pendingApkPath != null ? Icons.install_mobile : Icons.download),
                  label: Text(pendingApkPath != null
                      ? (english ? 'Install update $pendingVersion' : 'تثبيت التحديث $pendingVersion')
                      : (english ? 'Download update $pendingVersion' : 'تنزيل التحديث $pendingVersion')),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  static const String versionUrl =
      'https://mahmoudaljuorany.store/version.json';

  String cellData = "اضغط لقراءة الإشارة";
  String? signalErrorMessage;
  String updateStatus = "";

  String? pendingApkPath;
  String? pendingVersion;
  String? pendingDownloadUrl;
  String? pendingSha256;
  String pendingReleaseTitle = 'تحديث جديد لبرنامج مراقب شبكات العراق';
  List<String> pendingReleaseNotes = <String>[];
  bool updateDialogShown = false;
  bool updateNoticeShown = false;
  Timer? updateCheckTimer;

  bool checkingForUpdates = false;
  bool downloadingUpdate = false;
  final ValueNotifier<String> updateProgressMessage = ValueNotifier<String>('');
  bool isReadingSignal = false;
  bool autoRefresh = false;
  Timer? signalTimer;
  final List<int> signalHistory = <int>[];
  final List<Map<String, dynamic>> readingHistory = <Map<String, dynamic>>[];
  final MapController mapController = MapController();
  LatLng? currentPosition;
  DateTime? lastGpsSampleAt;
  int? latestRsrp, latestRsrq, latestRssi, latestEnbId;
  double? latestSinr;
  String? latestBand;
  List<Map<String, dynamic>> simCards = <Map<String, dynamic>>[];
  final List<double> sinrHistory = <double>[];
  bool scanningWifi = false;
  String wifiScanStatus = '';
  List<Map<String, dynamic>> wifiNetworks = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> neighborCells = <Map<String, dynamic>>[];
  String signalUpdatedAt = 'لم تُقرأ الإشارة بعد';
  int selectedTab = 0;
  String? lastObservedCellId;
  String? lastObservedNetworkType;
  int? lastObservedRsrp;
  DateTime? lastNetworkAlertAt;
  final TextEditingController channelInput = TextEditingController();
  final TextEditingController distanceInput = TextEditingController();
  final TextEditingController frequencyInput = TextEditingController();
  int channelCalculatorMode = 0;
  int lteChannelDirection = 0;
  String channelResult = '';
  String pathLossResult = '';
  bool testingTcpLatency = false;
  String tcpLatencyResult = '';
  bool showHeatmap = false;
  bool showDriveTest = true;

  bool get isDark => Theme.of(context).brightness == Brightness.dark;
  Color get accentColor => AppPreferences.accentColors[AppPreferences.accentIndex.value];
  Color get panelColor => isDark ? const Color(0xFF0D2038) : Colors.white;
  Color get subPanelColor => isDark ? const Color(0xFF07182B) : const Color(0xFFF1F5F9);
  Color get primaryTextColor => Theme.of(context).colorScheme.onSurface;
  Color get mutedTextColor => Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.68);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadReadingHistory();
    if (AppPreferences.english.value) {
      cellData = 'Tap to read signal';
      signalUpdatedAt = 'Signal not read yet';
      pendingReleaseTitle = 'New Iraq Network Monitor update';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkForUpdates();
    });
    updateCheckTimer = Timer.periodic(const Duration(hours: 6), (_) {
      if (mounted) checkForUpdates();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) checkForUpdates();
  }

  Future<File> _historyFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/signal-history.json');
  }

  Future<void> _loadReadingHistory() async {
    try {
      final file = await _historyFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) {
        final records = decoded.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item)).toList();
        if (!mounted) return;
        setState(() {
          readingHistory
            ..clear()
            ..addAll(records.take(200));
          currentPosition = readingHistory.isNotEmpty &&
                  readingHistory.first['latitude'] is num &&
                  readingHistory.first['longitude'] is num
              ? LatLng(
                  (readingHistory.first['latitude'] as num).toDouble(),
                  (readingHistory.first['longitude'] as num).toDouble(),
                )
              : null;
          latestRsrp = readingHistory.isNotEmpty
              ? (readingHistory.first['rsrp'] as num?)?.toInt() : null;
          latestRssi = readingHistory.isNotEmpty
              ? (readingHistory.first['rssi'] as num?)?.toInt() : null;
          latestEnbId = readingHistory.isNotEmpty
              ? (readingHistory.first['enbId'] as num?)?.toInt() : null;
          latestBand = readingHistory.isNotEmpty
              ? readingHistory.first['band']?.toString() : null;
          latestRsrq = readingHistory.isNotEmpty
              ? (readingHistory.first['rsrq'] as num?)?.toInt() : null;
          latestSinr = readingHistory.isNotEmpty
              ? (readingHistory.first['sinr'] as num?)?.toDouble() : null;
          signalHistory
            ..clear()
            ..addAll(readingHistory.take(30).toList().reversed
                .map((item) => item['rsrp'])
                .whereType<num>()
                .map((value) => value.toInt())
                .toList()
                .take(30));
          sinrHistory
            ..clear()
            ..addAll(readingHistory.take(30).toList().reversed
                .map((item) => item['sinr'])
                .whereType<num>()
                .map((value) => value.toDouble())
                .toList()
                .take(30));
          if (readingHistory.isNotEmpty) {
            final latest = readingHistory.first;
            lastObservedCellId = latest['cellId']?.toString();
            lastObservedNetworkType = latest['network']?.toString() ??
                latest['radioTech']?.toString();
            lastObservedRsrp = (latest['rsrp'] as num?)?.toInt();
            cellData = _formatCellSummary(latest);
            signalUpdatedAt = _formatReadingTime(latest['time']);
            final savedNeighbors = latest['neighbors'];
            if (savedNeighbors is List) {
              neighborCells = savedNeighbors.whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item)).toList();
            }
            final savedSims = latest['simCards'];
            if (savedSims is List) {
              simCards = savedSims.whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item)).toList();
            }
          }
        });
      }
    } catch (_) {
      // A damaged history file must never prevent signal monitoring.
    }
  }

  Future<void> _saveSignalReading(
    Map<String, dynamic> data,
    int? rsrp,
    int? rsrq,
    double? sinr,
    List<Map<String, dynamic>> neighbors,
    List<Map<String, dynamic>> sims,
  ) async {
    double? latitude;
    double? longitude;
    final now = DateTime.now();
    if (lastGpsSampleAt == null ||
        now.difference(lastGpsSampleAt!) >= const Duration(minutes: 1)) {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 8),
        );
        latitude = position.latitude;
        longitude = position.longitude;
        currentPosition = LatLng(position.latitude, position.longitude);
        lastGpsSampleAt = now;
        mapController.move(currentPosition!, 14);
      } catch (_) {
        lastGpsSampleAt = now;
        // Cell measurements remain useful when GPS is unavailable.
      }
    } else {
      latitude = currentPosition?.latitude;
      longitude = currentPosition?.longitude;
    }

    final record = <String, dynamic>{
      'time': DateTime.now().toIso8601String(),
      'carrier': data['carrier']?.toString() ?? '',
      'network': data['networkType']?.toString() ?? '',
      'radioTech': data['radioTech']?.toString() ?? data['networkType']?.toString() ?? '',
      'cellId': data['cellId'],
      'pci': data['pci'],
      'tac': data['tac'],
      'enbId': data['enbId'],
      'band': data['band'],
      'rssi': data['rssi'],
      'arfcn': data['arfcn'],
      'earfcn': data['earfcn'],
      'channel': data['arfcn'] ?? data['earfcn'],
      'neighbors': neighbors.map((item) => Map<String, dynamic>.from(item)).toList(),
      'simCards': sims.map((item) => Map<String, dynamic>.from(item)).toList(),
      'rsrp': rsrp,
      'rsrq': rsrq,
      'sinr': sinr,
      'latitude': latitude,
      'longitude': longitude,
    };
    readingHistory.insert(0, record);
    if (readingHistory.length > 200) {
      readingHistory.removeRange(200, readingHistory.length);
    }
    try {
      final file = await _historyFile();
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(readingHistory), flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    } catch (_) {
      // Keep live readings working even if local storage is unavailable.
    }
    if (mounted) setState(() {});
  }

  String _formatReadingTime(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return value?.toString() ?? '—';
    final local = parsed.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> showReadingHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF102B3D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.78,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(children: [
                  Expanded(child: Text(
                    tr('سجل قراءات الشبكة', 'Signal history'),
                    style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                  )),
                  IconButton(
                    tooltip: tr('نسخ السجل', 'Copy history'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(readingHistory)));
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr('تم نسخ السجل', 'History copied'))),
                      );
                    },
                    icon: const Icon(Icons.copy, color: Colors.white),
                  ),
                ]),
                Text(
                  tr('يُحفظ آخر 200 قياس على هذا الجهاز', 'Last 200 readings are stored on this device'),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: readingHistory.isEmpty
                      ? Center(child: Text(tr('لا توجد قراءات محفوظة بعد', 'No saved readings yet'), style: const TextStyle(color: Colors.white70)))
                      : ListView.separated(
                          itemCount: readingHistory.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                          itemBuilder: (_, index) {
                            final item = readingHistory[index];
                            final radio = item['radioTech']?.toString() ?? item['network']?.toString() ?? '—';
                            final isNr = radio.contains('NR') || radio.contains('5G');
                            final channelLabel = isNr ? 'NR-ARFCN' : 'EARFCN';
                            final channel = item['channel'] ?? item['arfcn'] ?? item['earfcn'] ?? '—';
                            final cellLabel = isNr ? 'NCI' : 'Cell ID';
                            final signalLabel = isNr ? 'SS-RSRP' : 'RSRP';
                            final coords = item['latitude'] is num && item['longitude'] is num
                                ? '${(item['latitude'] as num).toStringAsFixed(5)}, ${(item['longitude'] as num).toStringAsFixed(5)}'
                                : tr('غير متاح', 'unavailable');
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.cell_tower, color: Color(0xFF22D3EE)),
                              title: Text('${item['carrier'] ?? '—'} · $radio',
                                  style: const TextStyle(color: Colors.white)),
                              subtitle: Text(
                                '${_formatReadingTime(item['time'])}\n$cellLabel: ${item['cellId'] ?? '—'} · PCI: ${item['pci'] ?? '—'} · $channelLabel: $channel\n$signalLabel: ${item['rsrp'] ?? '—'} dBm · GPS: $coords',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                              isThreeLine: true,
                              trailing: item['latitude'] is num && item['longitude'] is num
                                  ? IconButton(
                                      icon: const Icon(Icons.location_on, color: Colors.orangeAccent),
                                      onPressed: () {
                                        Navigator.pop(sheetContext);
                                        final point = LatLng(
                                          (item['latitude'] as num).toDouble(),
                                          (item['longitude'] as num).toDouble(),
                                        );
                                        setState(() => currentPosition = point);
                                        mapController.move(point, 15);
                                      },
                                    )
                                  : null,
                            );
                          },
                        ),
                ),
                if (readingHistory.isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      readingHistory.clear();
                      signalHistory.clear();
                      sinrHistory.clear();
                      final file = await _historyFile();
                      if (await file.exists()) await file.delete();
                      if (mounted) {
                        setState(() {});
                        Navigator.pop(sheetContext);
                      }
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    label: Text(tr('مسح السجل المحفوظ', 'Clear saved history'),
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void setUpdateStatus(String value) {
    if (!mounted) return;
    setState(() => updateStatus = value);
    updateProgressMessage.value = value;
  }

  void showDownloadProgressDialog() {
    updateProgressMessage.value = updateStatus;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF102B3D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: ValueListenableBuilder<String>(
            valueListenable: updateProgressMessage,
            builder: (context, message, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFF22D3EE)),
                const SizedBox(height: 18),
                Text(
                  tr('تنزيل تحديث مراقب شبكات العراق', 'Downloading Iraq Network Monitor'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  message.isEmpty ? tr('يُرجى إبقاء التطبيق مفتوحاً أثناء التنزيل', 'Keep the app open while the update downloads') : message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('لا تغلق التطبيق حتى يكتمل التحقق من الملف', 'Do not close the app until file verification completes'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }

  void hideDownloadProgressDialog() {
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  String shortError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  int compareVersions(String a, String b) {
    // Compare semantic version and Android build number (for example 1.0.2+3).
    List<int> versionParts(String value) {
      final core = value.trim().split('+').first.split('-').first;
      return core.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    }

    int buildPart(String value) {
      final pieces = value.trim().split('+');
      if (pieces.length < 2) return 0;
      return int.tryParse(pieces.last.split('-').first) ?? 0;
    }

    final aa = versionParts(a);
    final bb = versionParts(b);
    final length = aa.length > bb.length ? aa.length : bb.length;

    for (var i = 0; i < length; i++) {
      final x = i < aa.length ? aa[i] : 0;
      final y = i < bb.length ? bb[i] : 0;
      if (x > y) return 1;
      if (x < y) return -1;
    }

    final aBuild = buildPart(a);
    final bBuild = buildPart(b);
    if (aBuild > bBuild) return 1;
    if (aBuild < bBuild) return -1;
    return 0;
  }

  Future<String> calculateSha256(File file) async {
    return (await sha256.bind(file.openRead()).first).toString();
  }

  Future<void> checkForUpdates({bool showPrompt = false}) async {
    if (!mounted || checkingForUpdates) return;
    setState(() => checkingForUpdates = true);
    try {
      final response = await http
          .get(Uri.parse(versionUrl), headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) throw Exception(tr('تعذر قراءة بيانات التحديث', 'Could not read update information'));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw Exception(tr('بيانات الإصدار غير صحيحة', 'Invalid release information'));

      final latestVersion = decoded['latest_version']?.toString().trim() ?? '';
      if (latestVersion.isEmpty) throw Exception(tr('رقم الإصدار غير موجود', 'Version number is missing'));
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      if (compareVersions(latestVersion, currentVersion) <= 0) {
        if (mounted) setUpdateStatus(tr('التطبيق محدث', 'App is up to date'));
        return;
      }

      final downloadUrl = decoded['download_url']?.toString() ?? '';
      final downloadUri = Uri.tryParse(downloadUrl);
      if (downloadUri == null || downloadUri.scheme != 'https') {
        throw Exception(tr('رابط التحديث غير صالح', 'Invalid update URL'));
      }
      final checksumValue = decoded['sha256'] ?? decoded['sha256_checksum'];
      if (checksumValue == null || checksumValue.toString().trim().isEmpty) {
        throw Exception(tr('التحديث مرفوض: بصمة SHA256 غير موجودة', 'Update rejected: SHA256 checksum is missing'));
      }
      final expectedHash = checksumValue.toString().trim().toLowerCase();
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash)) {
        throw Exception(tr('بصمة SHA256 غير صحيحة', 'Invalid SHA256 checksum'));
      }

      pendingVersion = latestVersion;
      pendingDownloadUrl = downloadUri.toString();
      pendingSha256 = expectedHash;
      pendingApkPath = null;
      pendingReleaseTitle =
          decoded['release_title']?.toString().trim().isNotEmpty == true
              ? decoded['release_title'].toString().trim()
              : tr('تحديث جديد لبرنامج مراقب شبكات العراق', 'New Iraq Network Monitor update');
      pendingReleaseNotes = _readReleaseNotes(decoded['release_notes']);
      if (pendingReleaseNotes.isEmpty) await _loadReleaseNotes(latestVersion);

      final supportDirectory = await getApplicationSupportDirectory();
      final updatesDirectory = Directory('${supportDirectory.path}/updates');
      await updatesDirectory.create(recursive: true);
      final safeVersion = latestVersion.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
      final apkFile = File('${updatesDirectory.path}/app-release-$safeVersion.apk');
      final metadataFile = File('${apkFile.path}.json');

      if (await apkFile.exists() && await metadataFile.exists()) {
        try {
          final metadata = jsonDecode(await metadataFile.readAsString());
          final localHash = await calculateSha256(apkFile);
          final valid = metadata is Map &&
              metadata['version'] == latestVersion &&
              metadata['url'] == downloadUri.toString() &&
              metadata['sha256'] == localHash &&
              expectedHash == localHash;
          if (valid) pendingApkPath = apkFile.path;
        } catch (_) {
          pendingApkPath = null;
        }
      }

      if (!mounted) return;
      setUpdateStatus(pendingApkPath == null
          ? tr('يتوفر تحديث جديد $latestVersion', 'Update $latestVersion is available')
          : tr('التحديث $latestVersion جاهز للتثبيت', 'Update $latestVersion is ready to install'));
      if (showPrompt) {
        await showUpdateDialog();
      } else if (!updateNoticeShown && mounted) {
        updateNoticeShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(
            'يتوفر تحديث جديد $latestVersion. افتح الإعدادات لمراجعته.',
            'Update $latestVersion is available. Open Settings to review it.',
          ))),
        );
      }
    } catch (e) {
      setUpdateStatus(tr('تعذر فحص التحديث: ${shortError(e)}', 'Could not check for updates: ${shortError(e)}'));
    } finally {
      if (mounted) setState(() => checkingForUpdates = false);
    }
  }

  List<String> _readReleaseNotes(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty).toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value.split(RegExp(r'[\r\n]+'))
          .map((item) => item.replaceFirst(RegExp(r'^[•\-*]\s*'), '').trim())
          .where((item) => item.isNotEmpty).toList();
    }
    return <String>[];
  }

  Future<void> _loadReleaseNotes(String version) async {
    try {
      final uri = Uri.parse(
        'https://mahmoudaljuorany.store/release_notes.json',
      );
      final response = await http.get(uri, headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['version']?.toString() != version) return;
      final notes = _readReleaseNotes(data['notes']);
      if (notes.isNotEmpty) {
        pendingReleaseTitle = data['title']?.toString().trim().isNotEmpty == true
            ? data['title'].toString().trim()
            : pendingReleaseTitle;
        pendingReleaseNotes = notes;
      }
    } catch (_) {
      // The update can proceed even if the optional changelog is unavailable.
    }
  }

  Future<void> showUpdateDialog() async {
    if (!mounted || updateDialogShown || pendingVersion == null) return;
    updateDialogShown = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final isDownloaded = pendingApkPath != null;
        return Dialog(
          backgroundColor: const Color(0xFF102B3D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFF24516C)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.system_update_alt, color: Colors.lightBlueAccent, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    pendingReleaseTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(tr('الإصدار $pendingVersion متوفر الآن', 'Version $pendingVersion is available'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 18),
                  Text(tr('جديد في هذا التحديث', "What's new"),
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...((pendingReleaseNotes.isEmpty
                      ? <String>[tr('تحسينات عامة وإصلاحات لرفع استقرار التطبيق.', 'General improvements and stability fixes.')]
                      : pendingReleaseNotes).map((note) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(note, style: const TextStyle(color: Colors.white70, height: 1.4))),
                          ],
                        ),
                      ))),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.lightBlueAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      if (isDownloaded) {
                        installPendingUpdate();
                      } else {
                        downloadPendingUpdate();
                      }
                    },
                    icon: Icon(isDownloaded ? Icons.install_mobile : Icons.download),
                    label: Text(isDownloaded ? tr('تثبيت التحديث الآن', 'Install update now') : tr('تنزيل وتحديث الآن', 'Download and update'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(tr('لاحقاً', 'Later'), style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    updateDialogShown = false;
  }

  Future<void> downloadPendingUpdate() async {
    final version = pendingVersion;
    final url = pendingDownloadUrl;
    final expectedHash = pendingSha256;
    if (version == null || url == null || expectedHash == null || downloadingUpdate) return;

    downloadingUpdate = true;
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final updatesDirectory = Directory('${supportDirectory.path}/updates');
      await updatesDirectory.create(recursive: true);
      final safeVersion = version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
      final apkFile = File('${updatesDirectory.path}/app-release-$safeVersion.apk');
      final metadataFile = File('${apkFile.path}.json');
      final temporaryFile = File('${apkFile.path}.part');
      if (await apkFile.exists()) await apkFile.delete();
      if (await metadataFile.exists()) await metadataFile.delete();

      setUpdateStatus(tr('يتم تجهيز تنزيل التحديث...', 'Preparing update download...'));
      showDownloadProgressDialog();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await downloadUpdate(Uri.parse(url), apkFile, metadataFile,
          temporaryFile, version, expectedHash);

      if (mounted) {
        hideDownloadProgressDialog();
        setUpdateStatus(tr('اكتمل التنزيل والتحقق من سلامة التحديث', 'Update downloaded and verified'));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('تم تنزيل التحديث والتحقق منه. جارٍ فتح مثبت أندرويد...', 'Update verified. Opening Android installer...'))),
        );
        await installPendingUpdate();
      }
    } catch (e) {
      if (mounted) {
        hideDownloadProgressDialog();
        final message = tr(
          'فشل تنزيل التحديث: ${shortError(e)}',
          'Update download failed: ${shortError(e)}',
        );
        setUpdateStatus(message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 10)),
        );
      }
    } finally {
      downloadingUpdate = false;
    }
  }

  Future<void> downloadUpdate(
    Uri url,
    File apkFile,
    File metadataFile,
    File temporaryFile,
    String version,
    String expectedHash,
  ) async {
    final client = http.Client();
    int? totalBytes;

    try {
      // Keep the partial file after transient network errors so the next
      // attempt (or a later user retry) can continue with an HTTP Range request.
      for (var attempt = 1; attempt <= 5; attempt++) {
        var existingBytes =
            await temporaryFile.exists() ? await temporaryFile.length() : 0;
        final request = http.Request('GET', url);
        request.headers['Accept-Encoding'] = 'identity';
        request.headers['Cache-Control'] = 'no-cache';
        if (existingBytes > 0) {
          request.headers['Range'] = 'bytes=$existingBytes-';
        }

        try {
          final response =
              await client.send(request).timeout(const Duration(seconds: 45));

          if (response.statusCode == 206) {
            final contentRange =
                response.headers[HttpHeaders.contentRangeHeader] ?? '';
            final match = RegExp(
              r'^bytes\s+(\d+)-(\d+)/(\d+)$',
              caseSensitive: false,
            ).firstMatch(contentRange.trim());
            if (match == null) {
              throw Exception('Invalid Content-Range: $contentRange');
            }
            final rangeStart = int.parse(match.group(1)!);
            final rangeEnd = int.parse(match.group(2)!);
            totalBytes = int.parse(match.group(3)!);
            if (rangeStart != existingBytes ||
                rangeEnd < rangeStart ||
                totalBytes <= 0 ||
                rangeEnd >= totalBytes) {
              throw Exception('Unexpected Content-Range: $contentRange');
            }
            final expectedChunkLength = rangeEnd - rangeStart + 1;
            if (response.contentLength != null &&
                response.contentLength != expectedChunkLength) {
              throw Exception('Partial response length does not match Content-Range');
            }
          } else if (response.statusCode == 200) {
            // The server does not support ranges (or ignored the range).
            // Restart safely instead of appending a duplicate full APK.
            existingBytes = 0;
            totalBytes = response.contentLength;
          } else {
            throw Exception('APK download failed: HTTP ${response.statusCode}');
          }

          final sink = temporaryFile.openWrite(
            mode: existingBytes > 0 ? FileMode.append : FileMode.write,
          );
          var attemptBytes = 0;
          try {
            await for (final chunk
                in response.stream.timeout(const Duration(seconds: 75))) {
              sink.add(chunk);
              attemptBytes += chunk.length;
              final currentBytes = existingBytes + attemptBytes;
              if (totalBytes != null && totalBytes! > 0) {
                final percent =
                    (currentBytes * 100 / totalBytes!).clamp(0, 100);
                setUpdateStatus(
                  'جاري تنزيل التحديث: ${percent.toStringAsFixed(0)}% '
                  '($attempt/5)',
                );
              } else {
                final mb = (currentBytes / 1024 / 1024).toStringAsFixed(1);
                setUpdateStatus(
                  tr('جاري التنزيل: $mb MB', 'Downloading: $mb MB'),
                );
              }
            }
            await sink.flush();
          } finally {
            await sink.close();
          }

          final currentLength = await temporaryFile.length();
          if (totalBytes != null && currentLength != totalBytes) {
            throw Exception('Connection ended before the APK was complete');
          }
          if (currentLength == 0) {
            throw Exception('The update file is empty');
          }
          // A clean EOF with no Content-Length is allowed; SHA-256 below
          // remains the authoritative completeness/integrity check.
          break;
        } catch (error) {
          if (attempt == 5) {
            throw Exception(
              tr(
                'فشل التنزيل بعد $attempt محاولات. السبب: ${shortError(error)}',
                'Download failed after $attempt attempts. Reason: ${shortError(error)}',
              ),
            );
          }
          setUpdateStatus(
            tr(
              'انقطع الاتصال؛ إعادة المحاولة واستكمال التنزيل ($attempt/5)...',
              'Connection interrupted; retrying download ($attempt/5)...',
            ),
          );
          await Future<void>.delayed(
            Duration(seconds: attempt * 2),
          );
        }
      }

      setUpdateStatus(tr(
        'جاري التحقق من سلامة ملف التحديث...',
        'Verifying update file integrity...',
      ));
      final actualHash = await calculateSha256(temporaryFile);
      if (actualHash != expectedHash) {
        // A complete transfer with a mismatched digest must never be installed.
        await temporaryFile.delete();
        throw Exception(tr(
          'فشل التحقق من SHA256؛ أُعيد ضبط التنزيل لحماية التطبيق.',
          'SHA256 verification failed; download was reset for safety.',
        ));
      }

      if (await apkFile.exists()) await apkFile.delete();
      await temporaryFile.rename(apkFile.path);

      final metadataTemporary = File('${metadataFile.path}.tmp');
      await metadataTemporary.writeAsString(
        jsonEncode({
          'version': version,
          'url': url.toString(),
          'sha256': actualHash,
        }),
        flush: true,
      );
      if (await metadataFile.exists()) await metadataFile.delete();
      await metadataTemporary.rename(metadataFile.path);

      if (!mounted) return;
      setState(() {
        pendingApkPath = apkFile.path;
        pendingVersion = version;
        updateStatus =
            tr('التحديث محفوظ وجاهز للتثبيت', 'Update saved and ready to install');
      });
    } catch (_) {
      // Preserve .part for safe Range-based continuation on the next retry.
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<void> installPendingUpdate() async {
    final path = pendingApkPath;

    if (path == null) return;

    try {
      final result = await platform.invokeMethod<String>(
        'installUpdateApk',
        {'path': path},
      );

      if (result == 'permission_required') {
        setUpdateStatus(
          tr('اسمح بتثبيت التطبيقات من هذا المصدر، ثم اضغط تثبيت التحديث', 'Allow installs from this source, then tap Install update'),
        );
      } else if (result == 'installer_opened') {
        setUpdateStatus(tr('تم فتح مثبت أندرويد', 'Android installer opened'));
      } else {
        setUpdateStatus(tr('تعذر فتح مثبت التحديث', 'Could not open the update installer'));
      }
    } on PlatformException catch (e) {
      setUpdateStatus(tr('خطأ التثبيت: ${e.message}', 'Installation error: ${e.message}'));
    } catch (e) {
      setUpdateStatus(tr('خطأ: ${shortError(e)}', 'Error: ${shortError(e)}'));
    }
  }

  String _formatCellSummary(Map<String, dynamic> data, {LatLng? location}) {
    final radio = data['radioTech']?.toString() ?? data['network']?.toString() ?? data['networkType']?.toString() ?? '';
    final isNr = radio.contains('NR') || radio.contains('5G');
    final channel = data['channel'] ?? data['arfcn'] ?? data['earfcn'] ?? '—';
    final position = location ?? currentPosition;
    final gps = position == null
        ? tr('GPS: غير متاح', 'GPS: unavailable')
        : 'GPS: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
    return [
      "${tr('الشركة', 'Carrier')}: ${data['carrier'] ?? tr('غير معروفة', 'Unknown')}",
      "${tr('الشبكة', 'Network')}: ${data['network'] ?? data['networkType'] ?? tr('غير معروفة', 'Unknown')}",
      'Radio: ${radio.isEmpty ? '—' : radio}',
      '${isNr ? 'NCI' : 'Cell ID'}: ${data['cellId'] ?? '—'}',
      'PCI: ${data['pci'] ?? '—'}',
      'TAC: ${data['tac'] ?? '—'}',
      '${isNr ? 'NR-ARFCN' : 'EARFCN'}: $channel',
      if (!isNr) 'eNB ID: ${data['enbId'] ?? '—'}',
      'Band: ${data['band'] ?? '—'}',
      'RSSI: ${data['rssi'] ?? '—'} dBm',
      '${isNr ? 'SS-RSRP' : 'RSRP'}: ${data['rsrp'] ?? '—'} dBm',
      '${isNr ? 'SS-RSRQ' : 'RSRQ'}: ${data['rsrq'] ?? '—'} dB',
      '${isNr ? 'SS-SINR' : 'SINR'}: ${data['sinr'] ?? '—'} dB',
      gps,
    ].join('\n');
  }
  Future<void> _evaluateNetworkAlerts(
    Map<String, dynamic> data,
    int? currentRsrp,
  ) async {
    final currentCellId = data['cellId']?.toString();
    final networkType = data['networkType']?.toString() ??
        data['radioTech']?.toString() ?? '';
    final messages = <String>[];

    if (lastObservedCellId != null &&
        currentCellId != null &&
        currentCellId.isNotEmpty &&
        currentCellId != lastObservedCellId) {
      messages.add(tr(
        'انتقل الهاتف إلى خلية جديدة: $lastObservedCellId ← $currentCellId',
        'Cell changed: $lastObservedCellId → $currentCellId',
      ));
    }

    if (lastObservedRsrp != null &&
        currentRsrp != null &&
        lastObservedRsrp! > -105 &&
        currentRsrp <= -110) {
      messages.add(tr(
        'تدهورت قوة الإشارة إلى $currentRsrp dBm.',
        'Signal dropped to $currentRsrp dBm.',
      ));
    }

    final previously5G = lastObservedNetworkType?.toUpperCase().contains('5G') ?? false;
    final currently5G = networkType.toUpperCase().contains('5G');
    if (!previously5G && currently5G) {
      messages.add(tr(
        'تم اكتشاف اتصال 5G: $networkType',
        '5G connection detected: $networkType',
      ));
    }

    if (currentCellId != null && currentCellId.isNotEmpty) {
      lastObservedCellId = currentCellId;
    }
    if (networkType.isNotEmpty) lastObservedNetworkType = networkType;
    if (currentRsrp != null) lastObservedRsrp = currentRsrp;

    if (messages.isEmpty || !AppPreferences.networkAlertsEnabled.value) return;

    final now = DateTime.now();
    if (lastNetworkAlertAt != null &&
        now.difference(lastNetworkAlertAt!) < const Duration(seconds: 20)) {
      return;
    }
    lastNetworkAlertAt = now;

    try {
      final result = await platform.invokeMethod<String>(
        'showNetworkNotification',
        {
          'title': tr('تنبيه مراقبة الشبكة', 'Network monitor alert'),
          'body': messages.join('\n'),
          'id': 7301,
        },
      );
      if (result == 'permission_required' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(
            'إذن الإشعارات غير مفعّل. افتح إعدادات التطبيق واسمح بالإشعارات.',
            'Notification permission is disabled. Allow it in Android app settings.',
          ))),
        );
      }
    } on PlatformException {
      // Measurement should continue even if the notification service is unavailable.
    }
  }

  Future<void> getSignal() async {
    if (isReadingSignal) return;
    isReadingSignal = true;
    try {
      // Android requires runtime location permission to expose nearby cell data.
      var locationStatus = await Permission.locationWhenInUse.status;
      if (!locationStatus.isGranted) {
        locationStatus = await Permission.locationWhenInUse.request();
      }

      if (!locationStatus.isGranted) {
        throw Exception(tr('اسمح للتطبيق بالوصول إلى الموقع حتى يقرأ بيانات الأبراج', 'Allow location access so the app can read cell tower data'));
      }

      var phoneStatus = await Permission.phone.status;
      if (!phoneStatus.isGranted) {
        phoneStatus = await Permission.phone.request();
      }

      if (!phoneStatus.isGranted) {
        throw Exception(tr('اسمح بإذن الهاتف لقراءة معلومات الشبكة', 'Allow phone permission to read network information'));
      }

      final raw = await platform.invokeMethod('getCellData');
      if (raw is! Map) {
        throw Exception(tr('استجابة بيانات الشبكة غير صالحة', 'Invalid network data response'));
      }

      final data = Map<String, dynamic>.from(raw);

      List<Map<String, dynamic>> parsedNeighborCells = <Map<String, dynamic>>[];
      try {
        final neighborsRaw = await platform.invokeMethod('getNeighborCells');
        if (neighborsRaw is List) {
          parsedNeighborCells = neighborsRaw.whereType<Map>()
              .map((cell) => Map<String, dynamic>.from(cell)).toList();
        }
      } on PlatformException {
        // The serving-cell reading can still be displayed without neighbors.
      }
      List<Map<String, dynamic>> parsedSimCards = <Map<String, dynamic>>[];
      try {
        final rawSims = await platform.invokeMethod('getSimCards');
        if (rawSims is List) {
          parsedSimCards = rawSims.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item)).toList();
        }
      } on PlatformException {
        // Main cell data remains available if subscription details are restricted.
      }

      final observedRsrp = (data['rsrp'] as num?)?.toInt();
      await _evaluateNetworkAlerts(data, observedRsrp);

      // Android may report an active 3G/5G/2G connection without exposing
      // a registered LTE cell. Show the real network state instead of
      // treating this expected condition as a platform failure.
      if (data['cellAvailable'] == false || (data['cellAvailable'] == null && data['lteAvailable'] == false)) {
        final carrier = data['carrier']?.toString().trim();
        final network = data['networkType']?.toString().trim();
        final carrierLabel =
            carrier == null || carrier.isEmpty ? tr('غير معروفة', 'Unknown') : carrier;
        final networkLabel =
            network == null || network.isEmpty ? tr('غير معروف', 'Unknown') : network;
        if (!mounted) return;
        setState(() {
          latestRsrp = null;
          latestSinr = null;
          latestRsrq = null;
          latestRssi = null;
          latestEnbId = null;
          latestBand = null;
          neighborCells = parsedNeighborCells;
          simCards = parsedSimCards;
          signalErrorMessage = tr('الشبكة الحالية: $networkLabel. الهاتف لم يزوّد التطبيق بخلية مسجّلة حالياً؛ لذلك لا يمكن عرض قياسات الخلية.', 'Current network: $networkLabel. The phone has not provided a registered cell, so cell measurements cannot be shown.');
          signalUpdatedAt = tr('تم تحديث حالة الشبكة', 'Network status updated');
          cellData =
              tr('الشركة: $carrierLabel\nالشبكة: $networkLabel\nحالة القياس: لا توجد خلية مسجّلة حالياً', 'Carrier: $carrierLabel\nNetwork: $networkLabel\nMeasurement status: No registered cell is currently available');
        });
        return;
      }

      final rsrp = (data['rsrp'] as num?)?.toInt();
      final sinr = (data['sinr'] as num?)?.toDouble();
      final rsrq = (data['rsrq'] as num?)?.toInt();
      await _saveSignalReading(data, rsrp, rsrq, sinr, parsedNeighborCells, parsedSimCards);

      if (!mounted) return;
      setState(() {
        latestRsrp = rsrp;
        latestSinr = sinr;
        latestRsrq = rsrq;
        latestRssi = (data['rssi'] as num?)?.toInt();
        latestEnbId = (data['enbId'] as num?)?.toInt();
        latestBand = data['band']?.toString();
        neighborCells = parsedNeighborCells;
        simCards = parsedSimCards;

        if (rsrp != null) {
          signalHistory.add(rsrp);
          if (signalHistory.length > 30) signalHistory.removeAt(0);
        }
        if (sinr != null) {
          sinrHistory.add(sinr);
          if (sinrHistory.length > 30) sinrHistory.removeAt(0);
        }

        signalUpdatedAt = TimeOfDay.now().format(context);
        signalErrorMessage = null;
        cellData = _formatCellSummary({
          ...data,
          'rsrp': rsrp,
          'rsrq': rsrq,
          'sinr': sinr,
        }, location: currentPosition);
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'UNAVAILABLE' =>
          tr('لا تتوفر بيانات LTE من الهاتف حالياً. قد تكون الشبكة على 3G أو أن بيانات البرج لم تصل بعد.', 'LTE data is not currently available. The phone may be on 3G, or cell information may not have arrived yet.'),
        'PERMISSION_DENIED' =>
          tr('يلزم السماح بصلاحية الموقع والهاتف حتى نتمكن من قراءة معلومات الشبكة.', 'Location and phone permissions are required to read network information.'),
        _ => tr('حدثت مشكلة أثناء جلب معلومات الشبكة. حاول مرة أخرى.', 'There was a problem reading network information. Please try again.'),
      };
      setState(() {
        signalErrorMessage = message;
        signalUpdatedAt = tr('لم تكتمل القراءة', 'Reading incomplete');
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          signalErrorMessage = tr('تعذّر جلب معلومات الإشارة حالياً. حاول إعادة القراءة.', 'Signal information is unavailable. Please try again.');
          signalUpdatedAt = tr('لم تكتمل القراءة', 'Reading incomplete');
        });
      }
    } finally {
      isReadingSignal = false;
    }
  }

  List<Marker> buildHistoryMarkers() {
    final markers = <Marker>[];
    final seen = <String>{};
    final currentKey = currentPosition == null
        ? null
        : '${currentPosition!.latitude.toStringAsFixed(4)},${currentPosition!.longitude.toStringAsFixed(4)}';
    for (final record in readingHistory) {
      final lat = record['latitude'];
      final lon = record['longitude'];
      if (lat is! num || lon is! num) continue;
      final latitude = lat.toDouble();
      final longitude = lon.toDouble();
      final key = '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';
      if (key == currentKey || !seen.add(key)) continue;
      markers.add(Marker(
        point: LatLng(latitude, longitude),
        width: 34,
        height: 38,
        child: GestureDetector(
          onTap: () {
            final stamp = _formatReadingTime(record['time']);
            final radio = record['radioTech'] ?? record['network'] ?? '—';
            final value = record['rsrp'] ?? '—';
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${tr('قراءة محفوظة', 'Saved reading')} · $stamp · $radio · RSRP $value dBm'),
            ));
          },
          child: const Icon(Icons.location_on, color: Color(0xFFFFB74D), size: 30),
        ),
      ));
      if (markers.length >= 100) break;
    }
    return markers;
  }
  Widget buildSignalErrorCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF332719),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.signal_cellular_connected_no_internet_4_bar,
              color: Colors.orangeAccent, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('بيانات الإشارة غير متاحة', 'Signal data unavailable'),
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                const SizedBox(height: 5),
                Text(signalErrorMessage ?? tr('تعذّر جلب معلومات الشبكة.', 'Could not read network information.'),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12, height: 1.5)),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: getSignal,
                    icon: const Icon(Icons.refresh, size: 17),
                    label: Text(tr('إعادة المحاولة', 'Try again')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orangeAccent,
                      side: const BorderSide(color: Colors.orangeAccent),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSimCards() {
    if (simCards.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.sim_card, color: accentColor, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('معلومات الشرائح', 'SIM card measurements'),
                style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w800))),
            Text('${simCards.length}', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          ...simCards.map((sim) {
            final slot = sim['slot']?.toString() ?? '?';
            final name = sim['displayName']?.toString().trim();
            final carrier = sim['carrier']?.toString().trim();
            final radio = sim['radioTech']?.toString() ?? sim['networkType']?.toString() ?? '—';
            final cellId = sim['cellId']?.toString() ?? '—';
            final band = sim['band']?.toString() ?? '—';
            final rsrp = sim['rsrp']?.toString() ?? '—';
            final rsrq = sim['rsrq']?.toString() ?? '—';
            final sinr = sim['sinr']?.toString() ?? '—';
            final rssi = sim['rssi']?.toString() ?? '—';
            final enb = sim['enbId']?.toString() ?? '—';
            return Container(
              margin: const EdgeInsets.only(top: 7),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: subPanelColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.sim_card, color: accentColor, size: 17),
                    const SizedBox(width: 7),
                    Expanded(child: Text(
                      '${tr('الشريحة', 'SIM')} $slot · ${(name?.isNotEmpty == true) ? name : ((carrier?.isNotEmpty == true) ? carrier : tr('غير معروفة', 'Unknown'))}',
                      style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w800),
                    )),
                    Text(radio, style: TextStyle(color: mutedTextColor, fontSize: 10)),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    'Cell: $cellId  •  Band: $band',
                    style: TextStyle(color: mutedTextColor, fontSize: 11),
                  ),
                  Text(
                    'RSRP: $rsrp dBm  •  RSRQ: $rsrq dB  •  SINR: $sinr dB',
                    style: TextStyle(color: mutedTextColor, fontSize: 11),
                  ),
                  Text(
                    'RSSI: $rssi dBm  •  eNB ID: $enb',
                    style: TextStyle(color: mutedTextColor, fontSize: 11),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget buildNeighborCells() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cell_tower, color: accentColor, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  tr('الخلايا القريبة', 'Nearby cells'),
                  style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${neighborCells.length}',
                  style: TextStyle(color: accentColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (neighborCells.isEmpty)
            Text(
              tr(
                'لا توجد بيانات خلايا مجاورة متاحة حالياً من الجهاز أو الشبكة',
                'No neighboring cell data is currently available',
              ),
              style: TextStyle(color: mutedTextColor, fontSize: 12, height: 1.45),
            )
          else
            ...neighborCells.asMap().entries.map((entry) {
              final index = entry.key;
              final cell = entry.value;
              final registered = cell['registered'] == true;
              final radio = cell['radioTech']?.toString() ?? '4G LTE';
              final isNr = radio.contains('NR') || cell['arfcn'] != null;
              final channelName = isNr ? 'NR-ARFCN' : 'EARFCN';
              final channel = isNr ? cell['arfcn'] : cell['earfcn'];
              final cellName = isNr ? 'NCI' : 'Cell ID';
              String value(String key) => cell[key]?.toString() ?? '—';

              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: subPanelColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: registered
                        ? const Color(0xFF237D74)
                        : Theme.of(context).dividerColor,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          registered ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: registered ? const Color(0xFF16A36A) : mutedTextColor,
                          size: 15,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            registered
                                ? tr('الخلية المتصل بها', 'Serving cell')
                                : tr('خلية مجاورة ${index + 1}', 'Neighbor cell ${index + 1}'),
                            style: TextStyle(
                              color: registered ? const Color(0xFF16A36A) : accentColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          isNr ? '5G NR' : '4G LTE',
                          style: TextStyle(color: mutedTextColor, fontSize: 10),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '$cellName: ${value('cellId')}   |   PCI: ${value('pci')}   |   TAC: ${value('tac')}',
                      style: TextStyle(color: primaryTextColor, fontSize: 11),
                    ),
                    Text(
                      '$channelName: ${channel?.toString() ?? '—'}',
                      style: TextStyle(color: mutedTextColor, fontSize: 11),
                    ),
                    Text(
                      'Band: ${value('band')}  •  RSSI: ${value('rssi')} dBm',
                      style: TextStyle(color: mutedTextColor, fontSize: 11),
                    ),
                    if (!isNr)
                      Text('eNB ID: ${value('enbId')}', style: TextStyle(color: mutedTextColor, fontSize: 11)),
                    Text(
                      '${isNr ? 'SS-RSRP' : 'RSRP'}: ${value('rsrp')} dBm   |   ${isNr ? 'SS-RSRQ' : 'RSRQ'}: ${value('rsrq')} dB',
                      style: TextStyle(color: mutedTextColor, fontSize: 11),
                    ),
                    Text(
                      '${isNr ? 'SS-SINR' : 'SINR'}: ${value('sinr')} dB',
                      style: TextStyle(color: mutedTextColor, fontSize: 11),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  void setAutoRefresh(bool enabled) {
    signalTimer?.cancel();
    setState(() => autoRefresh = enabled);
    if (enabled) {
      getSignal();
      signalTimer = Timer.periodic(const Duration(seconds: 10), (_) => getSignal());
    }
  }

  Future<void> copyReport() async {
    await Clipboard.setData(ClipboardData(text: 'IRAQ NETWORK MONITOR\n$signalUpdatedAt\n$cellData'));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('تم نسخ تقرير الشبكة', 'Network report copied'))));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    signalTimer?.cancel();
    updateCheckTimer?.cancel();
    channelInput.dispose();
    distanceInput.dispose();
    frequencyInput.dispose();
    updateProgressMessage.dispose();
    super.dispose();
  }

  String quality(num? v, {bool rsrp = false}) {
    if (v == null) return tr('غير متاح', 'Unavailable');
    if (rsrp) return v >= -85 ? tr('ممتاز', 'Excellent') : v >= -100 ? tr('جيد', 'Good') : v >= -110 ? tr('متوسط', 'Fair') : tr('ضعيف', 'Weak');
    return v >= 20 ? tr('ممتاز', 'Excellent') : v >= 10 ? tr('جيد', 'Good') : v >= 0 ? tr('متوسط', 'Fair') : tr('ضعيف', 'Weak');
  }

  Widget metric(String name, num? value, String unit, String status) => Container(
    width: 98,
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: panelColor,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: accentColor.withValues(alpha: 0.28)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name, style: TextStyle(color: mutedTextColor, fontSize: 11, fontWeight: FontWeight.w600)),
      Text(
        value == null ? '—' : '${value is double ? value.toStringAsFixed(1) : value} $unit',
        style: TextStyle(color: accentColor, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      Text(status, style: TextStyle(color: mutedTextColor, fontSize: 10)),
    ]),
  );

  double _log10(double value) => math.log(value) / math.ln10;

  void calculateChannelFrequency() {
    final channel = int.tryParse(channelInput.text.trim());
    if (channel == null || channel < 0) {
      setState(() => channelResult = tr('أدخل رقم قناة صحيحاً.', 'Enter a valid channel number.'));
      return;
    }

    if (channelCalculatorMode == 0) {
      final bands = lteChannelDirection == 0
          ? const <Map<String, num>>[
              {'band': 1, 'first': 0, 'last': 599, 'base': 2110, 'offset': 0, 'tdd': 0},
              {'band': 3, 'first': 1200, 'last': 1949, 'base': 1805, 'offset': 1200, 'tdd': 0},
              {'band': 7, 'first': 2750, 'last': 3449, 'base': 2620, 'offset': 2750, 'tdd': 0},
              {'band': 8, 'first': 3450, 'last': 3799, 'base': 925, 'offset': 3450, 'tdd': 0},
              {'band': 20, 'first': 6150, 'last': 6449, 'base': 791, 'offset': 6150, 'tdd': 0},
              {'band': 28, 'first': 9210, 'last': 9659, 'base': 758, 'offset': 9210, 'tdd': 0},
              {'band': 38, 'first': 37750, 'last': 38249, 'base': 2570, 'offset': 37750, 'tdd': 1},
              {'band': 40, 'first': 38650, 'last': 39649, 'base': 2300, 'offset': 38650, 'tdd': 1},
              {'band': 41, 'first': 39650, 'last': 41589, 'base': 2496, 'offset': 39650, 'tdd': 1},
              {'band': 42, 'first': 41590, 'last': 43589, 'base': 3400, 'offset': 41590, 'tdd': 1},
              {'band': 43, 'first': 43590, 'last': 45589, 'base': 3600, 'offset': 43590, 'tdd': 1},
            ]
          : const <Map<String, num>>[
              {'band': 1, 'first': 18000, 'last': 18599, 'base': 1920, 'offset': 18000, 'tdd': 0},
              {'band': 3, 'first': 19200, 'last': 19949, 'base': 1710, 'offset': 19200, 'tdd': 0},
              {'band': 7, 'first': 20750, 'last': 21449, 'base': 2500, 'offset': 20750, 'tdd': 0},
              {'band': 8, 'first': 21450, 'last': 21799, 'base': 880, 'offset': 21450, 'tdd': 0},
              {'band': 20, 'first': 24150, 'last': 24449, 'base': 832, 'offset': 24150, 'tdd': 0},
              {'band': 28, 'first': 27210, 'last': 27659, 'base': 703, 'offset': 27210, 'tdd': 0},
              {'band': 38, 'first': 37750, 'last': 38249, 'base': 2570, 'offset': 37750, 'tdd': 1},
              {'band': 40, 'first': 38650, 'last': 39649, 'base': 2300, 'offset': 38650, 'tdd': 1},
              {'band': 41, 'first': 39650, 'last': 41589, 'base': 2496, 'offset': 39650, 'tdd': 1},
              {'band': 42, 'first': 41590, 'last': 43589, 'base': 3400, 'offset': 41590, 'tdd': 1},
              {'band': 43, 'first': 43590, 'last': 45589, 'base': 3600, 'offset': 43590, 'tdd': 1},
            ];
      Map<String, num>? selected;
      for (final band in bands) {
        if (channel >= band['first']! && channel <= band['last']!) {
          selected = band;
          break;
        }
      }
      if (selected == null) {
        setState(() => channelResult = tr(
          lteChannelDirection == 0
              ? 'قناة DL هذه ليست ضمن نطاقات LTE المضافة حالياً.'
              : 'قناة UL هذه ليست ضمن نطاقات LTE المضافة حالياً.',
          lteChannelDirection == 0
              ? 'This downlink EARFCN is outside the LTE bands currently included.'
              : 'This uplink EARFCN is outside the LTE bands currently included.',
        ));
        return;
      }
      final frequency = selected['base']! +
          0.1 * (channel - selected['offset']!);
      final isTdd = selected['tdd'] == 1;
      final linkLabel = lteChannelDirection == 0
          ? tr('التنزيل DL', 'Downlink (DL)')
          : tr('الرفع UL', 'Uplink (UL)');
      final duplexLabel = isTdd ? 'TDD' : 'FDD';
      setState(() {
        channelResult = 'LTE Band ${selected!['band']} · $duplexLabel\n'
            'EARFCN: $channel\n'
            '$linkLabel: ${frequency.toStringAsFixed(2)} MHz'
            '${isTdd ? '\n' + tr('قناة TDD نفسها للرفع والتنزيل', 'TDD uses the same channel number and frequency for UL and DL') : ''}';
      });
      return;
    }

    if (channel > 3279165) {
      setState(() => channelResult = tr('NR-ARFCN يجب أن يكون بين 0 و3,279,165.', 'NR-ARFCN must be between 0 and 3,279,165.'));
      return;
    }

    final double frequencyMHz;
    if (channel <= 599999) {
      frequencyMHz = channel * 0.005;
    } else if (channel <= 2016666) {
      frequencyMHz = 3000 + (channel - 600000) * 0.015;
    } else {
      frequencyMHz = 24250.08 + (channel - 2016667) * 0.06;
    }
    setState(() {
      channelResult = '5G NR\nNR-ARFCN: $channel\n'
          'Frequency: ${frequencyMHz.toStringAsFixed(3)} MHz';
    });
  }

  void calculatePathLoss() {
    final distanceKm = double.tryParse(distanceInput.text.trim());
    final frequencyMHz = double.tryParse(frequencyInput.text.trim());
    if (distanceKm == null || frequencyMHz == null ||
        distanceKm <= 0 || frequencyMHz <= 0) {
      setState(() => pathLossResult = tr(
        'أدخل مسافة بالكيلومتر وتردداً بالميغاهرتز أكبر من صفر.',
        'Enter a distance in km and frequency in MHz, both greater than zero.',
      ));
      return;
    }
    final loss = 32.44 + 20 * _log10(distanceKm) + 20 * _log10(frequencyMHz);
    setState(() {
      pathLossResult = '${loss.toStringAsFixed(2)} dB  •  FSPL';
    });
  }

  String get signalDiagnosis {
    if (latestRsrp == null) {
      return tr(
        'اقرأ الإشارة أولاً حتى نحلّل قوة التغطية.',
        'Read the signal first to analyze coverage quality.',
      );
    }
    final parts = <String>[];
    if (latestRsrp! <= -115) {
      parts.add(tr(
        'قوة RSRP ضعيفة جداً؛ الاحتمال الأكبر ضعف التغطية أو البعد عن موقع الخلية أو وجود عوائق.',
        'RSRP is very weak; poor coverage, distance from the cell, or physical obstructions are likely.',
      ));
    } else if (latestRsrp! <= -105) {
      parts.add(tr(
        'قوة RSRP ضعيفة؛ جرّب مكاناً مفتوحاً أو أقرب إلى جهة البرج.',
        'RSRP is weak; try an open location or move toward the cell site.',
      ));
    } else if (latestRsrp! <= -95) {
      parts.add(tr(
        'قوة RSRP متوسطة؛ التغطية موجودة لكنها ليست قوية.',
        'RSRP is fair; coverage is present but not strong.',
      ));
    } else {
      parts.add(tr(
        'قوة RSRP جيدة؛ ضعف السرعة لا يبدو ناتجاً عن ضعف مستوى الإشارة وحده.',
        'RSRP is good; slow data is unlikely to be caused by signal level alone.',
      ));
    }

    if (latestSinr == null) {
      parts.add(tr(
        'لا توجد قراءة SINR/RSSNR من المودم حالياً؛ لا يمكن الجزم بمستوى التداخل.',
        'The modem did not expose SINR/RSSNR; interference quality cannot be assessed yet.',
      ));
    } else if (latestSinr! < 0) {
      parts.add(tr(
        'SINR منخفض وسالب؛ توجد جودة راديوية سيئة قد ترتبط بالتداخل أو ازدحام الخلية. لا يمكن إثبات الازدحام من هذه القراءة وحدها.',
        'SINR is negative; radio quality is poor and may reflect interference or cell load. This reading alone cannot prove congestion.',
      ));
    } else if (latestSinr! < 10) {
      parts.add(tr(
        'SINR متوسط؛ يوجد مجال لتحسين جودة الإشارة.',
        'SINR is fair; radio quality could be improved.',
      ));
    } else {
      parts.add(tr(
        'SINR جيد؛ جودة الإشارة الراديوية تبدو مقبولة.',
        'SINR is good; radio quality appears healthy.',
      ));
    }
    return parts.join('\n\n');
  }

  Future<void> runTcpLatencyTest() async {
    if (testingTcpLatency) return;
    setState(() {
      testingTcpLatency = true;
      tcpLatencyResult = tr('جاري فحص اتصال TCP...', 'Testing TCP connection...');
    });
    final samples = <int>[];
    try {
      for (var i = 0; i < 3; i++) {
        final stopwatch = Stopwatch()..start();
        final socket = await Socket.connect(
          '1.1.1.1',
          443,
          timeout: const Duration(seconds: 5),
        );
        stopwatch.stop();
        socket.destroy();
        samples.add(stopwatch.elapsedMilliseconds);
      }
      final average = samples.reduce((a, b) => a + b) / samples.length;
      if (mounted) {
        setState(() {
          tcpLatencyResult = tr(
            'متوسط فتح اتصال TCP: ${average.toStringAsFixed(0)} ms\nالقراءات: ${samples.join(' / ')} ms',
            'Average TCP connect time: ${average.toStringAsFixed(0)} ms\nSamples: ${samples.join(' / ')} ms',
          );
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          tcpLatencyResult = tr(
            'تعذر الاتصال بخادم الاختبار: $error',
            'Could not connect to the test server: $error',
          );
        });
      }
    } finally {
      if (mounted) setState(() => testingTcpLatency = false);
    }
  }

  Future<void> scanWifiNetworks() async {
    if (scanningWifi) return;
    setState(() {
      scanningWifi = true;
      wifiScanStatus = tr('جاري طلب مسح شبكات Wi-Fi...', 'Requesting a Wi-Fi scan...');
    });
    try {
      var locationStatus = await Permission.locationWhenInUse.status;
      if (!locationStatus.isGranted) {
        locationStatus = await Permission.locationWhenInUse.request();
      }
      if (!locationStatus.isGranted) {
        throw Exception(tr(
          'يلزم إذن الموقع حتى يسمح أندرويد بقراءة نتائج مسح Wi-Fi.',
          'Android requires location permission to read Wi-Fi scan results.',
        ));
      }
      final locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!locationServiceEnabled) {
        throw Exception(tr(
          'فعّل خدمة الموقع في إعدادات الهاتف حتى يتمكن أندرويد من مسح شبكات Wi-Fi.',
          'Enable Android Location services before scanning nearby Wi-Fi networks.',
        ));
      }

      final raw = await platform.invokeMethod('scanWifiNetworks');
      if (raw is! Map) throw Exception('Invalid Wi-Fi scan response');
      final enabled = raw['wifiEnabled'] == true;
      final requested = raw['scanRequested'] == true;
      final rawNetworks = raw['networks'];
      final results = rawNetworks is List
          ? rawNetworks.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item)).toList()
          : <Map<String, dynamic>>[];
      results.sort((a, b) =>
          ((b['levelDbm'] as num?)?.toInt() ?? -127)
              .compareTo((a['levelDbm'] as num?)?.toInt() ?? -127));

      if (!mounted) return;
      setState(() {
        wifiNetworks = results;
        wifiScanStatus = !enabled
            ? tr('فعّل Wi-Fi في إعدادات الهاتف أولاً.', 'Turn on Wi-Fi in Android settings first.')
            : results.isEmpty
                ? tr('لم تظهر شبكات؛ تأكد من تشغيل خدمة الموقع وWi-Fi ثم أعد المسح.', 'No networks returned; enable Location services and Wi-Fi, then scan again.')
                : requested
                    ? tr('تم قبول طلب المسح؛ قد تقيّد أندرويد التحديثات المتكررة.', 'Scan request accepted; Android may throttle repeated scans.')
                    : tr('أندرويد أعاد آخر نتائج متاحة؛ قد تكون مخزّنة مؤقتاً.', 'Android returned the latest available results; they may be cached.');
      });
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          wifiScanStatus = tr(
            'تعذر مسح Wi-Fi: ${error.message ?? error.code}',
            'Wi-Fi scan failed: ${error.message ?? error.code}',
          );
        });
      }
    } catch (error) {
      if (mounted) setState(() => wifiScanStatus = error.toString());
    } finally {
      if (mounted) setState(() => scanningWifi = false);
    }
  }

  double _wifiChannelLoad(int candidate, String band) {
    var load = 0.0;
    for (final network in wifiNetworks) {
      if (network['band'] != band) continue;
      final channel = (network['channel'] as num?)?.toInt();
      if (channel == null || channel <= 0) continue;
      final distance = (channel - candidate).abs();
      if (band == '2.4 GHz') {
        if (distance <= 4) load += (5 - distance).toDouble();
      } else if (distance == 0) {
        load += 1;
      }
    }
    return load;
  }

  int? get recommendedWifi24Channel {
    if (!wifiNetworks.any((item) => item['band'] == '2.4 GHz')) return null;
    const choices = <int>[1, 6, 11];
    choices.sort((a, b) =>
        _wifiChannelLoad(a, '2.4 GHz').compareTo(_wifiChannelLoad(b, '2.4 GHz')));
    return choices.first;
  }

  int? get recommendedWifi5Channel {
    if (!wifiNetworks.any((item) => item['band'] == '5 GHz')) return null;
    const choices = <int>[36, 40, 44, 48, 149, 153, 157, 161];
    choices.sort((a, b) =>
        _wifiChannelLoad(a, '5 GHz').compareTo(_wifiChannelLoad(b, '5 GHz')));
    return choices.first;
  }

  Widget buildWifiAnalyzerCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.wifi, color: accentColor),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('محلل شبكات Wi-Fi', 'Wi-Fi analyzer'),
                style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w800))),
            Text('${wifiNetworks.length}', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          Text(
            tr(
              'يعرض الشبكات التي يسمح أندرويد بمسحها، ويقترح قنوات أقل ازدحاماً ضمن النتائج الظاهرة فقط.',
              'Shows networks Android allows the app to scan and suggests less occupied channels from visible results only.',
            ),
            style: TextStyle(color: mutedTextColor, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 9),
          ElevatedButton.icon(
            onPressed: scanningWifi ? null : scanWifiNetworks,
            icon: scanningWifi
                ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.radar),
            label: Text(tr('مسح الشبكات المحيطة', 'Scan nearby networks')),
          ),
          if (wifiScanStatus.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(wifiScanStatus, style: TextStyle(color: mutedTextColor, fontSize: 11)),
          ],
          if (wifiNetworks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (recommendedWifi24Channel != null)
                  Chip(
                    avatar: const Icon(Icons.wifi, size: 15),
                    label: Text(tr('أفضل 2.4 GHz: قناة $recommendedWifi24Channel',
                        'Suggested 2.4 GHz: channel $recommendedWifi24Channel')),
                  ),
                if (recommendedWifi5Channel != null)
                  Chip(
                    avatar: const Icon(Icons.wifi, size: 15),
                    label: Text(tr('أفضل 5 GHz: قناة $recommendedWifi5Channel',
                        'Suggested 5 GHz: channel $recommendedWifi5Channel')),
                  ),
              ],
            ),
            const Divider(height: 18),
            ...wifiNetworks.take(20).map((network) {
              final ssid = network['ssid']?.toString() ?? tr('شبكة مخفية', 'Hidden network');
              final band = network['band']?.toString() ?? '—';
              final channel = network['channel']?.toString() ?? '—';
              final frequency = network['frequencyMhz']?.toString() ?? '—';
              final level = (network['levelDbm'] as num?)?.toInt();
              final capabilities = network['capabilities']?.toString() ?? '';
              final signalColor = level == null
                  ? mutedTextColor
                  : level >= -60
                      ? const Color(0xFF16A34A)
                      : level >= -75
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFFDC2626);
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.wifi, color: signalColor),
                title: Text(ssid, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '$band · CH $channel · $frequency MHz${capabilities.isEmpty ? '' : ' · $capabilities'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: mutedTextColor, fontSize: 10),
                ),
                trailing: Text(level == null ? '—' : '$level dBm',
                    style: TextStyle(color: accentColor, fontSize: 11, fontWeight: FontWeight.bold)),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget buildToolsTab() {
    final cardDecoration = BoxDecoration(
      color: panelColor,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: accentColor.withValues(alpha: 0.25)),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Text(
          tr('أدوات المهندس', 'Engineering tools'),
          style: TextStyle(color: primaryTextColor, fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          tr('حاسبات ترددات وتشخيص أولي للشبكة', 'Frequency calculators and basic network diagnostics'),
          style: TextStyle(color: mutedTextColor, fontSize: 12),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.analytics_outlined, color: accentColor),
                const SizedBox(width: 8),
                Text(tr('التشخيص الذكي للإشارة', 'Signal diagnostics'),
                    style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 10),
              Text(signalDiagnosis, style: TextStyle(color: mutedTextColor, height: 1.55)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.cell_tower, color: accentColor),
                const SizedBox(width: 8),
                Text(tr('حاسبة EARFCN / NR-ARFCN', 'EARFCN / NR-ARFCN calculator'),
                    style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: channelCalculatorMode,
                decoration: InputDecoration(
                  labelText: tr('نوع القناة', 'Channel type'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: 0, child: Text('LTE EARFCN')),
                  DropdownMenuItem(value: 1, child: Text('5G NR-ARFCN')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() {
                    channelCalculatorMode = value;
                    channelResult = '';
                  });
                },
              ),
              if (channelCalculatorMode == 0) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: lteChannelDirection,
                  decoration: InputDecoration(
                    labelText: tr('اتجاه التردد', 'Frequency direction'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: 0, child: Text(tr('التنزيل DL', 'Downlink (DL)'))),
                    DropdownMenuItem(value: 1, child: Text(tr('الرفع UL', 'Uplink (UL)'))),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() {
                      lteChannelDirection = value;
                      channelResult = '';
                    });
                  },
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: channelInput,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('رقم القناة', 'Channel number'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: calculateChannelFrequency,
                icon: const Icon(Icons.calculate_outlined),
                label: Text(tr('احسب التردد', 'Calculate frequency')),
              ),
              if (channelResult.isNotEmpty) ...[
                const SizedBox(height: 10),
                SelectableText(channelResult, style: TextStyle(color: accentColor, height: 1.5, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 8),
              Text(
                tr('تحويل LTE يدعم DL وUL للنطاقات B1/B3/B7/B8/B20/B28 وTDD للنطاقات B38/B40/B41/B42/B43. تحويل NR يستخدم جدول التردد العالمي.',
                  'LTE conversion supports DL and UL for B1/B3/B7/B8/B20/B28 and shared TDD channels for B38/B40/B41/B42/B43. NR uses the global NR-ARFCN raster.'),
                style: TextStyle(color: mutedTextColor, fontSize: 11, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.waves, color: accentColor),
                const SizedBox(width: 8),
                Text(tr('حاسبة فقدان المسار الحر', 'Free-space path loss calculator'),
                    style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: distanceInput,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: tr('المسافة', 'Distance'),
                  suffixText: 'km',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 9),
              TextField(
                controller: frequencyInput,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: tr('التردد', 'Frequency'),
                  suffixText: 'MHz',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: calculatePathLoss,
                icon: const Icon(Icons.calculate_outlined),
                label: Text(tr('احسب فقدان المسار', 'Calculate path loss')),
              ),
              if (pathLossResult.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(pathLossResult, style: TextStyle(color: accentColor, fontWeight: FontWeight.w800)),
              ],
              const SizedBox(height: 6),
              Text(
                tr('هذه معادلة الفضاء الحر FSPL، ولا تشمل خسائر المباني أو التضاريس أو الهوائيات.',
                  'FSPL is a free-space estimate; it excludes buildings, terrain, antenna gains, and other real-world losses.'),
                style: TextStyle(color: mutedTextColor, fontSize: 11, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.network_ping, color: accentColor),
                const SizedBox(width: 8),
                Text(tr('اختبار زمن اتصال TCP', 'TCP connection latency'),
                    style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 6),
              Text(
                tr('يقيس زمن فتح اتصال TCP إلى 1.1.1.1 على المنفذ 443؛ هذا ليس ICMP Ping ولا يمثل سرعة التنزيل.',
                  'Measures TCP connection setup time to 1.1.1.1:443. This is not ICMP ping and does not measure download speed.'),
                style: TextStyle(color: mutedTextColor, fontSize: 11, height: 1.45),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: testingTcpLatency ? null : runTcpLatencyTest,
                icon: testingTcpLatency
                    ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(tr('ابدأ الاختبار', 'Start test')),
              ),
              if (tcpLatencyResult.isNotEmpty) ...[
                const SizedBox(height: 10),
                SelectableText(tcpLatencyResult, style: TextStyle(color: accentColor, height: 1.5)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        buildWifiAnalyzerCard(),
      ],
    );
  }

  Widget _graphLegend(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(color: mutedTextColor, fontSize: 10)),
    ],
  );

  Widget buildNetworkTab() {
    return RefreshIndicator(
      onRefresh: getSignal,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('مراقبة الشبكة الخلوية', 'Mobile network monitor'),
                        style: TextStyle(color: primaryTextColor, fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(tr('قراءات الهاتف والخلية المتصل بها', 'Live phone and serving-cell measurements'),
                        style: TextStyle(color: mutedTextColor, fontSize: 12)),
                  ],
                ),
              ),
              Column(
                children: [
                  Text(tr('تلقائي', 'Auto'), style: TextStyle(color: mutedTextColor, fontSize: 11)),
                  Switch(value: autoRefresh, onChanged: setAutoRefresh),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              metric('RSRP', latestRsrp, 'dBm', quality(latestRsrp, rsrp: true)),
              metric('RSRQ', latestRsrq, 'dB', tr('جودة القناة', 'Channel quality')),
              metric('SINR / RSSNR', latestSinr, 'dB', quality(latestSinr)),
              metric('RSSI', latestRssi, 'dBm', tr('قوة الاستقبال', 'Received signal')),
            ],
          ),
          if (latestSinr == null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: panelColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accentColor.withValues(alpha: 0.25)),
              ),
              child: Text(
                tr(
                  'ملاحظة: يمكن قراءة SINR على LTE أيضاً. إذا بقيت — فهذا يعني أن الهاتف أو المودم لم يوفّر قيمة RSSNR عبر أندرويد؛ التطبيق لا يخمّن القراءة.',
                  'Note: SINR can also be read on LTE. If it stays as —, the phone or modem did not expose RSSNR to Android; the app will not invent a value.',
                ),
                style: TextStyle(color: mutedTextColor, fontSize: 12, height: 1.45),
              ),
            ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accentColor.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.timeline, color: accentColor),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr('تغيّر قوة الإشارة', 'Signal history'),
                      style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w800))),
                  Text(tr('آخر 30 عينة', 'Last 30 samples'),
                      style: TextStyle(color: mutedTextColor, fontSize: 10)),
                ]),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 14,
                  children: [
                    _graphLegend(const Color(0xFF16A34A), 'RSRP'),
                    _graphLegend(const Color(0xFFF59E0B), 'SINR'),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 82,
                  child: CustomPaint(
                    painter: SignalHistoryPainter(
                      List<int>.from(signalHistory),
                      sinrValues: List<double>.from(sinrHistory),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(tr('آخر قراءة: $signalUpdatedAt', 'Last reading: $signalUpdatedAt'),
                      style: TextStyle(color: mutedTextColor, fontSize: 11)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (signalErrorMessage != null)
            buildSignalErrorCard()
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: panelColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accentColor.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.cell_tower, color: accentColor),
                    const SizedBox(width: 8),
                    Text(tr('تفاصيل الخلية الحالية', 'Serving cell details'),
                        style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 10),
                  SelectableText(
                    cellData,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: isDark ? const Color(0xFF9DECCB) : const Color(0xFF176B4A),
                    ),
                  ),
                ],
              ),
            ),
          if (latestBand != null || latestEnbId != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: panelColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accentColor.withValues(alpha: 0.22)),
              ),
              child: Row(
                children: [
                  Expanded(child: Text('Band: ${latestBand ?? '—'}', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700))),
                  Expanded(child: Text('eNB ID: ${latestEnbId?.toString() ?? '—'}', style: TextStyle(color: mutedTextColor))),
                ],
              ),
            ),
          buildSimCards(),
          buildNeighborCells(),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isReadingSignal ? null : getSignal,
                  icon: isReadingSignal
                      ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: Text(tr('قراءة الإشارة الآن', 'Read signal now')),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: copyReport,
                tooltip: tr('نسخ التقرير', 'Copy report'),
                icon: const Icon(Icons.copy),
              ),
              IconButton.filledTonal(
                onPressed: () => setState(() => selectedTab = 2),
                tooltip: tr('سجل القياسات', 'Measurement history'),
                icon: const Icon(Icons.history),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _signalMapColor(dynamic value) {
    final rsrp = (value as num?)?.toInt();
    if (rsrp == null) return Colors.grey;
    if (rsrp >= -90) return const Color(0xFF16A34A);
    if (rsrp >= -100) return const Color(0xFF84CC16);
    if (rsrp >= -110) return const Color(0xFFF59E0B);
    return const Color(0xFFDC2626);
  }

  List<CircleMarker> buildHeatmapCircles() {
    final circles = <CircleMarker>[];
    final seen = <String>{};
    for (final record in readingHistory) {
      final lat = record['latitude'];
      final lon = record['longitude'];
      if (lat is! num || lon is! num) continue;
      final key = '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
      if (!seen.add(key)) continue;
      final color = _signalMapColor(record['rsrp']);
      circles.add(CircleMarker(
        point: LatLng(lat.toDouble(), lon.toDouble()),
        radius: 23,
        useRadiusInMeter: false,
        color: color.withValues(alpha: 0.24),
        borderColor: color.withValues(alpha: 0.9),
        borderStrokeWidth: 1.5,
      ));
      if (circles.length >= 200) break;
    }
    return circles;
  }

  List<Polyline> buildDriveTestLines() {
    final samples = readingHistory.reversed.where((record) =>
      record['latitude'] is num && record['longitude'] is num
    ).toList();
    final lines = <Polyline>[];
    for (var i = 1; i < samples.length; i++) {
      final before = samples[i - 1];
      final after = samples[i];
      final start = LatLng(
        (before['latitude'] as num).toDouble(),
        (before['longitude'] as num).toDouble(),
      );
      final end = LatLng(
        (after['latitude'] as num).toDouble(),
        (after['longitude'] as num).toDouble(),
      );
      if ((start.latitude - end.latitude).abs() < 0.000001 &&
          (start.longitude - end.longitude).abs() < 0.000001) {
        continue;
      }
      lines.add(Polyline(
        points: [start, end],
        color: _signalMapColor(after['rsrp']),
        strokeWidth: 5,
        strokeCap: StrokeCap.round,
      ));
    }
    return lines;
  }

  Widget buildMapTab() {
    final gpsCount = readingHistory.where((item) =>
      item['latitude'] is num && item['longitude'] is num
    ).length;

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: currentPosition ?? const LatLng(33.3152, 44.3661),
            initialZoom: currentPosition == null ? 12.0 : 14.0,
          ),
          mapController: mapController,
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.abrj_iraq',
            ),
            if (showHeatmap)
              CircleLayer(circles: buildHeatmapCircles()),
            if (showDriveTest)
              PolylineLayer(polylines: buildDriveTestLines()),
            MarkerLayer(
              markers: [
                ...buildHistoryMarkers(),
                if (currentPosition != null)
                  Marker(
                    point: currentPosition!,
                    width: 46,
                    height: 46,
                    child: Icon(Icons.my_location, color: accentColor, size: 34),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 14,
          right: 14,
          top: 12,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.map_outlined, color: accentColor),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          tr('مواقع القياسات المحفوظة', 'Saved measurement locations'),
                          style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text('$gpsCount',
                          style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      FilterChip(
                        selected: showHeatmap,
                        label: Text(tr('خريطة قوة الإشارة', 'Signal heatmap')),
                        avatar: const Icon(Icons.blur_on, size: 17),
                        onSelected: (value) => setState(() => showHeatmap = value),
                      ),
                      FilterChip(
                        selected: showDriveTest,
                        label: Text(tr('مسار القيادة', 'Drive test path')),
                        avatar: const Icon(Icons.route, size: 17),
                        onSelected: (value) => setState(() => showDriveTest = value),
                      ),
                    ],
                  ),
                  Text(
                    tr(
                      'الألوان: أخضر قوي • أصفر متوسط • أحمر ضعيف. يحتاج المسار إلى قراءات محفوظة مع GPS.',
                      'Colors: green strong • yellow fair • red weak. The route needs saved GPS measurements.',
                    ),
                    style: TextStyle(color: mutedTextColor, fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 18,
          right: 16,
          child: FloatingActionButton(
            heroTag: 'map_current_location',
            onPressed: () async {
              if (currentPosition != null) {
                mapController.move(currentPosition!, 15);
              } else {
                await getSignal();
                if (currentPosition != null) mapController.move(currentPosition!, 15);
              }
            },
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }

  Widget buildHistoryTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('سجل القياسات', 'Measurement history'),
                        style: TextStyle(color: primaryTextColor, fontSize: 20, fontWeight: FontWeight.w900)),
                    Text(tr('آخر 200 قراءة محفوظة على الجهاز', 'Last 200 readings stored on this device'),
                        style: TextStyle(color: mutedTextColor, fontSize: 11)),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: tr('نسخ بصيغة CSV', 'Copy CSV'),
                onPressed: readingHistory.isEmpty ? null : copyHistoryCsv,
                icon: const Icon(Icons.copy),
              ),
              IconButton.filledTonal(
                tooltip: tr('تصدير ملف CSV', 'Export CSV file'),
                onPressed: readingHistory.isEmpty ? null : shareHistoryCsvFile,
                icon: const Icon(Icons.table_view_outlined),
              ),
              IconButton.filledTonal(
                tooltip: tr('تصدير إلى Google Earth (KML)', 'Export to Google Earth (KML)'),
                onPressed: readingHistory.isEmpty ? null : shareHistoryKml,
                icon: const Icon(Icons.public),
              ),
              IconButton.filledTonal(
                tooltip: tr('مسح السجل', 'Clear history'),
                onPressed: readingHistory.isEmpty ? null : clearReadingHistory,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
        Expanded(
          child: readingHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 48, color: mutedTextColor),
                      const SizedBox(height: 10),
                      Text(tr('لا توجد قياسات محفوظة بعد', 'No measurements saved yet'),
                          style: TextStyle(color: mutedTextColor)),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => setState(() => selectedTab = 0),
                        icon: const Icon(Icons.network_cell),
                        label: Text(tr('اذهب إلى تبويب الشبكة', 'Go to Network tab')),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                  itemCount: readingHistory.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 7),
                  itemBuilder: (context, index) {
                    final item = readingHistory[index];
                    final radio = item['radioTech']?.toString() ?? item['network']?.toString() ?? '—';
                    final cell = item['cellId']?.toString() ?? '—';
                    final pci = item['pci']?.toString() ?? '—';
                    final rsrp = item['rsrp']?.toString() ?? '—';
                    final sinr = item['sinr']?.toString() ?? '—';
                    final hasGps = item['latitude'] is num && item['longitude'] is num;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: accentColor.withValues(alpha: 0.14),
                          child: Icon(Icons.cell_tower, color: accentColor),
                        ),
                        title: Text('${item['carrier'] ?? '—'}  •  $radio',
                            style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${_formatReadingTime(item['time'])}\nCell: $cell  •  PCI: $pci\nBand: ${item['band'] ?? '—'}  •  RSSI: ${item['rssi'] ?? '—'} dBm\nRSRP: $rsrp dBm  •  SINR: $sinr dB',
                          style: TextStyle(color: mutedTextColor, fontSize: 12, height: 1.45),
                        ),
                        isThreeLine: true,
                        trailing: hasGps
                            ? IconButton(
                                tooltip: tr('عرض على الخريطة', 'Show on map'),
                                icon: Icon(Icons.location_on, color: accentColor),
                                onPressed: () {
                                  final point = LatLng(
                                    (item['latitude'] as num).toDouble(),
                                    (item['longitude'] as num).toDouble(),
                                  );
                                  setState(() {
                                    currentPosition = point;
                                    selectedTab = 1;
                                  });
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (mounted) mapController.move(point, 15);
                                  });
                                },
                              )
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _csvValue(dynamic value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }

  String _xmlEscape(dynamic value) {
    return (value?.toString() ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  String _kmlSignalStyle(dynamic value) {
    final rsrp = (value as num?)?.toInt();
    if (rsrp == null) return 'signalUnknown';
    if (rsrp >= -90) return 'signalStrong';
    if (rsrp >= -100) return 'signalGood';
    if (rsrp >= -110) return 'signalFair';
    return 'signalWeak';
  }

  String buildKmlDocument() {
    final records = readingHistory.where((item) =>
      item['latitude'] is num && item['longitude'] is num
    ).toList();
    final output = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<kml xmlns="http://www.opengis.net/kml/2.2">')
      ..writeln('<Document>')
      ..writeln('<name>IRAQ NETWORK MONITOR</name>')
      ..writeln('<description>Mobile network signal measurements with GPS coordinates</description>');

    const styles = <String, String>{
      'signalStrong': 'ff16a34a',
      'signalGood': 'ff84cc16',
      'signalFair': 'ff0b9ff5',
      'signalWeak': 'ff2626dc',
      'signalUnknown': 'ff808080',
    };
    for (final entry in styles.entries) {
      output
        ..writeln('<Style id="${entry.key}">')
        ..writeln('<IconStyle><color>${entry.value}</color><scale>0.85</scale>')
        ..writeln('<Icon><href>http://maps.google.com/mapfiles/kml/shapes/placemark_circle.png</href></Icon>')
        ..writeln('</IconStyle></Style>');
    }

    for (final item in records) {
      final latitude = (item['latitude'] as num).toDouble();
      final longitude = (item['longitude'] as num).toDouble();
      final radio = item['radioTech'] ?? item['network'] ?? '—';
      final timestamp = _formatReadingTime(item['time']);
      final name = '${item['carrier'] ?? 'Network'} - $timestamp';
      final description = [
        'Network: $radio',
        'Cell ID: ${item['cellId'] ?? '—'}',
        'eNB ID: ${item['enbId'] ?? '—'}',
        'PCI: ${item['pci'] ?? '—'}',
        'TAC: ${item['tac'] ?? '—'}',
        'Band: ${item['band'] ?? '—'}',
        'RSSI: ${item['rssi'] ?? '—'} dBm',
        'RSRP: ${item['rsrp'] ?? '—'} dBm',
        'RSRQ: ${item['rsrq'] ?? '—'} dB',
        'SINR: ${item['sinr'] ?? '—'} dB',
        'Channel: ${item['channel'] ?? item['earfcn'] ?? item['arfcn'] ?? '—'}',
        'Time: ${item['time'] ?? '—'}',
      ].join('\n');

      output
        ..writeln('<Placemark>')
        ..writeln('<name>${_xmlEscape(name)}</name>')
        ..writeln('<description>${_xmlEscape(description)}</description>')
        ..writeln('<styleUrl>#${_kmlSignalStyle(item['rsrp'])}</styleUrl>')
        ..writeln('<Point><coordinates>$longitude,$latitude,0</coordinates></Point>')
        ..writeln('</Placemark>');
    }

    output
      ..writeln('</Document>')
      ..writeln('</kml>');
    return output.toString();
  }

  Future<void> shareHistoryKml() async {
    final count = readingHistory.where((item) =>
      item['latitude'] is num && item['longitude'] is num
    ).length;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(
          'لا توجد قياسات مرتبطة بإحداثيات GPS لتصديرها.',
          'There are no GPS-linked measurements to export.',
        ))),
      );
      return;
    }
    try {
      final result = await platform.invokeMethod<String>(
        'shareKml',
        {'content': buildKmlDocument()},
      );
      if (mounted && result == 'share_opened') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(
            'تم تجهيز ملف KML؛ اختر Google Earth أو التطبيق المناسب.',
            'KML export is ready; choose Google Earth or another app.',
          ))),
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(
            'تعذر تصدير KML: ${error.message ?? error.code}',
            'KML export failed: ${error.message ?? error.code}',
          ))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('تعذر إنشاء ملف KML: $error', 'Could not create KML: $error'))),
        );
      }
    }
  }

  String buildHistoryCsv() {
    const columns = <String>[
      'time', 'carrier', 'network', 'radioTech', 'cellId', 'enbId', 'pci',
      'tac', 'band', 'rssi', 'earfcn', 'arfcn', 'rsrp', 'rsrq', 'sinr',
      'latitude', 'longitude'
    ];
    final rows = <String>[
      columns.join(','),
      ...readingHistory.map((item) => columns.map((key) => _csvValue(item[key])).join(',')),
    ];
    return rows.join('\r\n');
  }

  Future<void> copyHistoryCsv() async {
    await Clipboard.setData(ClipboardData(text: buildHistoryCsv()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('تم نسخ سجل القياسات بصيغة CSV', 'Measurement history copied as CSV'))),
      );
    }
  }

  Future<void> shareHistoryCsvFile() async {
    if (readingHistory.isEmpty) return;
    try {
      final result = await platform.invokeMethod<String>(
        'shareCsv',
        {'content': buildHistoryCsv()},
      );
      if (mounted && result == 'share_opened') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(
            'تم تجهيز ملف CSV. اختر Excel أو التطبيق المناسب لحفظه.',
            'CSV file is ready. Choose Excel or another app to save it.',
          ))),
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(
            'تعذر تصدير ملف CSV: ${error.message ?? error.code}',
            'CSV export failed: ${error.message ?? error.code}',
          ))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(
            'تعذر إنشاء ملف CSV: $error',
            'Could not create CSV file: $error',
          ))),
        );
      }
    }
  }

  Future<void> clearReadingHistory() async {
    final file = await _historyFile();
    readingHistory.clear();
    signalHistory.clear();
    sinrHistory.clear();
    if (await file.exists()) await file.delete();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final destinations = <NavigationDestination>[
      NavigationDestination(icon: const Icon(Icons.network_cell), selectedIcon: const Icon(Icons.network_cell), label: tr('الشبكة', 'Network')),
      NavigationDestination(icon: const Icon(Icons.map_outlined), selectedIcon: const Icon(Icons.map), label: tr('الخريطة', 'Map')),
      NavigationDestination(icon: const Icon(Icons.history), selectedIcon: const Icon(Icons.history), label: tr('السجل', 'History')),
      NavigationDestination(icon: const Icon(Icons.build_outlined), selectedIcon: const Icon(Icons.build), label: tr('الأدوات', 'Tools')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cell_tower, color: accentColor, size: 23),
            const SizedBox(width: 9),
            const Flexible(child: Text('IRAQ NETWORK MONITOR', overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: tr('الإعدادات', 'Settings'),
            onPressed: showSettings,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.settings_outlined),
                if (pendingVersion != null)
                  const Positioned(
                    top: -2,
                    right: -2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                      child: SizedBox(width: 9, height: 9),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: selectedTab,
        children: [buildNetworkTab(), buildMapTab(), buildHistoryTab(), buildToolsTab()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) => setState(() => selectedTab = index),
        destinations: destinations,
      ),
    );
  }
}

class SignalHistoryPainter extends CustomPainter {
  SignalHistoryPainter(this.values, {this.sinrValues = const <double>[]});

  final List<int> values;
  final List<double> sinrValues;

  void _drawSeries(
    Canvas canvas,
    Size size,
    List<num> samples,
    double minValue,
    double maxValue,
    Color color,
  ) {
    if (samples.length < 2) return;
    final path = ui.Path();
    for (var i = 0; i < samples.length; i++) {
      final x = size.width * i / (samples.length - 1);
      final normalized = ((samples[i].toDouble() - minValue) /
              (maxValue - minValue))
          .clamp(0.0, 1.0).toDouble();
      final y = size.height - normalized * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.grey.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // Separate fixed ranges keep the two engineering metrics readable.
    _drawSeries(canvas, size, values, -140, -40, const Color(0xFF16A34A));
    _drawSeries(canvas, size, sinrValues, -20, 40, const Color(0xFFF59E0B));
  }

  @override
  bool shouldRepaint(covariant SignalHistoryPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.sinrValues != sinrValues;
}
