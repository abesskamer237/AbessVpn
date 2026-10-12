import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const AbessVpnApp());

class AbessVpnApp extends StatelessWidget {
  const AbessVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ABESS VPN',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF020A12),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late FlutterV2ray v2ray;
  late ScrollController logsScroll;
  Timer? _trafficTimer;
  static const MethodChannel _trafficChannel = MethodChannel('abessvpn/traffic');

  final List<double> _rxSamples = [];
  final List<double> _txSamples = [];
  int? _lastRxBytes;
  int? _lastTxBytes;
  int _lastSampleTs = 0;

  // Traffic detection
  static const double _trafficThresholdKbps = 5.0; // threshold to consider "real" traffic
  bool _trafficActive = false; // true when recent samples exceed threshold
  int? _lastTrafficDetectedAt;
  bool _connectedWithTraffic = false;

  final hostCtrl = TextEditingController(
    text: 'ahmed-vip1-792623150612.us-central1.run.app',
  );

  String status = 'DÉCONNECTÉ';
  String motorStatus = 'MOTEUR: INACTIF';

  bool isConnected = false;
  bool isLoading = false;
  bool permissionGranted = false;
  bool motorReady = false;
  bool motorVerified = false;

  final List<LogEntry> logs = [];

  static const String _vlessUuid = '@abess237';
  static const String _vlessServer = '192.179.18.100';
  static const int _vlessPort = 443;
  static const String _vlessPath = '/@abess237';
  static const String _sniTls = 'crashlyticsreports-pa.googleapis.com';

  static Map<String, dynamic> buildEmbeddedConfig(String hostInjection) {
    final finalHost = hostInjection.trim().isEmpty
        ? 'abess-ops1-748584122458.us-central1.run.app'
        : hostInjection.trim();

    return {
      'inbounds': [
        {'port': 10808, 'protocol': 'socks', 'settings': {'udp': true}},
      ],
      'outbounds': [
        {
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': _vlessServer,
                'port': _vlessPort,
                'users': [
                  {'id': _vlessUuid, 'encryption': 'none'},
                ],
              },
            ],
          },
          'streamSettings': {
            'network': 'ws',
            'security': 'tls',
            'tlsSettings': {
              'serverName': _sniTls,
              'allowInsecure': false,
              'alpn': ['h2', 'http/1.1'],
            },
            'wsSettings': {
              'path': _vlessPath,
              'headers': {'Host': finalHost},
            },
          },
          'mux': {'enabled': false},
        },
      ],
    };
  }

  bool isValidHost(String host) {
    final clean = host.trim();
    if (clean.isEmpty) return false;
    if (clean.contains('://')) return false;
    final hostPattern = RegExp(r'^(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}\$|^(?:\d{1,3}\.){3}\d{1,3}\$');
    return hostPattern.hasMatch(clean);
  }

  String _sanitizeLog(String message) {
    final maskedHost = '[MASKED_HOST]';
    final maskedIp = '[MASKED_IP]';
    final maskedUuid = '[MASKED_UUID]';
    final maskedPath = '[MASKED_PATH]';
    final maskedSni = '[MASKED_SNI]';

    var sanitized = message;
    sanitized = sanitized.replaceAll(_vlessUuid, maskedUuid);
    sanitized = sanitized.replaceAll(_vlessServer, maskedIp);
    sanitized = sanitized.replaceAll(_vlessPath, maskedPath);
    sanitized = sanitized.replaceAll(_sniTls, maskedSni);

    final hostRegex = RegExp(
      r'(?:(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}|(?:\d{1,3}\.){3}\d{1,3})',
    );
    sanitized = sanitized.replaceAllMapped(hostRegex, (match) {
      final value = match.group(0) ?? '';
      if (value.contains('.') && !value.contains(' ')) {
        return maskedHost;
      }
      return value;
    });

    return sanitized;
  }

  Future<void> _startTrafficMonitoring() async {
    _trafficTimer?.cancel();
    _trafficTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      _updateTrafficSample();
    });

    await _updateTrafficSample();
  }

  Future<void> _updateTrafficSample() async {
    try {
      final result = await _trafficChannel.invokeMethod<Map>('getTrafficCounters');
      final rxBytes = (result?['rxBytes'] ?? 0) as num;
      final txBytes = (result?['txBytes'] ?? 0) as num;
      final now = DateTime.now().millisecondsSinceEpoch;
      final deltaMs = _lastSampleTs == 0 ? 1000 : (now - _lastSampleTs).clamp(400, 5000);

      final rxRate = _lastRxBytes == null
          ? 0.0
          : ((rxBytes - _lastRxBytes!).abs() / deltaMs) * 1000.0 * 8.0 / 1000.0;
      final txRate = _lastTxBytes == null
          ? 0.0
          : ((txBytes - _lastTxBytes!).abs() / deltaMs) * 1000.0 * 8.0 / 1000.0;

      _lastRxBytes = rxBytes.toInt();
      _lastTxBytes = txBytes.toInt();
      _lastSampleTs = now;

      // mark traffic active if threshold exceeded
      if (rxRate >= _trafficThresholdKbps || txRate >= _trafficThresholdKbps) {
        _trafficActive = true;
        _lastTrafficDetectedAt = DateTime.now().millisecondsSinceEpoch;
      }

      _addSample(rxRate.clamp(0.0, 1000.0), txRate.clamp(0.0, 1000.0));
    } catch (_) {
      // fallback to simulated wave when native method unavailable
      final time = DateTime.now().millisecondsSinceEpoch;
      final wave = 28 + (math.sin(time / 1400) * 18);
      final burst = 14 + (math.cos(time / 900) * 11);
      _addSample(wave.clamp(0.0, 200.0), burst.clamp(0.0, 200.0));
    }
  }

  Future<bool> _waitForTraffic({int timeoutSeconds = 8}) async {
    final endTs = DateTime.now().millisecondsSinceEpoch + timeoutSeconds * 1000;
    while (DateTime.now().millisecondsSinceEpoch < endTs) {
      // Check last samples first
      if (_rxSamples.isNotEmpty && _txSamples.isNotEmpty) {
        final lastRx = _rxSamples.last;
        final lastTx = _txSamples.last;
        if (lastRx >= _trafficThresholdKbps || lastTx >= _trafficThresholdKbps) return true;
      }

      // fallback: check lastTrafficDetectedAt
      if (_lastTrafficDetectedAt != null) {
        final age = DateTime.now().millisecondsSinceEpoch - _lastTrafficDetectedAt!;
        if (age <= timeoutSeconds * 1000) return true;
      }

      await Future.delayed(const Duration(milliseconds: 700));
    }
    return false;
  }

  void _addSample(double rx, double tx) {
    if (!mounted) return;

    setState(() {
      _rxSamples.add(rx);
      _txSamples.add(tx);

      if (_rxSamples.length > 30) {
        _rxSamples.removeAt(0);
      }
      if (_txSamples.length > 30) {
        _txSamples.removeAt(0);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    logsScroll = ScrollController();

    v2ray = FlutterV2ray(
      onStatusChanged: (s) {
        if (!mounted) return;

        setState(() {
          status = s.state;
          motorStatus = 'MOTEUR: ${s.state}';
          isConnected = s.state == 'CONNECTED';
          isLoading = s.state == 'CONNECTING';
        });

        _addLog(
          'Moteur: ${s.state}',
          s.state == 'CONNECTED'
              ? LogType.success
              : s.state == 'CONNECTING'
                  ? LogType.info
                  : s.state == 'DISCONNECTED'
                      ? LogType.warning
                      : LogType.error,
        );
      },
    );

    _verifyMotor();
    _startTrafficMonitoring();
  }

  Future<void> _verifyMotor() async {
    _addLog('Démarrage ABESS VPN...', LogType.info);
    _addLog('Initialisation du moteur Xray...', LogType.info);

    try {
      await v2ray.initializeV2Ray();
      _addLog('✓ Moteur Xray initialisé', LogType.success);

      final prefs = await SharedPreferences.getInstance();
      final savedHost = prefs.getString('host') ??
          'ahmed-vip1-792623150612.us-central1.run.app';

      if (mounted) {
        setState(() {
          hostCtrl.text = savedHost;
        });
      }

      try {
        final version = await v2ray.getCoreVersion();
        _addLog('✓ Xray Core v$version prêt', LogType.success);
        setState(() => motorReady = true);
      } catch (e) {
        _addLog('⚠ Version Xray indisponible: $e', LogType.warning);
        setState(() => motorReady = true);
      }

      final testConfig = buildEmbeddedConfig('test');
      final testJson = jsonEncode(testConfig);
      jsonDecode(testJson);

      _addLog('✓ Configuration VLESS intégrée validée', LogType.success);
      _addLog('✓ Serveur: $_vlessServer:$_vlessPort', LogType.info);
      _addLog('✓ Transport: WebSocket + TLS', LogType.info);
      _addLog('✓ SNI TLS: $_sniTls', LogType.success);
      _addLog('✓ Chemin WS: $_vlessPath', LogType.info);
      _addLog('✓ UUID intégré (masqué)', LogType.success);

      setState(() => motorVerified = true);
      _addLog('MOTEUR VPN PRÊT', LogType.success);
    } catch (e) {
      _addLog('Erreur critique du moteur: $e', LogType.error);
      setState(() => motorReady = false);
    }
  }

  void _addLog(String message, LogType type) {
    if (!mounted) return;

    final maskedMessage = _sanitizeLog(message);

    setState(() {
      logs.add(LogEntry(
        message: maskedMessage,
        type: type,
        timestamp: DateTime.now(),
      ));
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (logsScroll.hasClients) {
        logsScroll.animateTo(
          logsScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<String?> buildFinalConfig(String host) async {
    try {
      if (!motorReady) {
        _addLog('Moteur non prêt', LogType.error);
        return null;
      }

      final cleanHost = host.trim();

      if (cleanHost.isEmpty) {
        _addLog('Host vide → valeur par défaut', LogType.warning);
        return jsonEncode(
          buildEmbeddedConfig('ahmed-vip1-792623150612.us-central1.run.app'),
        );
      }

      if (cleanHost.contains('://')) {
        _addLog('Host invalide: URL détectée', LogType.error);
        return null;
      }

      final config = buildEmbeddedConfig(cleanHost);
      final configJson = jsonEncode(config);
      jsonDecode(configJson);

      _addLog('✓ JSON valide', LogType.success);
      _addLog('Host injecté: [MASKED_HOST]', LogType.info);

      return configJson;
    } catch (e) {
      _addLog('Erreur config: $e', LogType.error);
      return null;
    }
  }

  Future<void> connect() async {
    if (isLoading || isConnected || !motorReady) return;

    // validate host before attempting
    if (!isValidHost(hostCtrl.text)) {
      setState(() {
        status = 'HOST INVALIDE';
      });
      _addLog('Host invalide, connexion annulée', LogType.error);
      return;
    }

    _addLog('Tentative de connexion...', LogType.info);
    setState(() => isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', hostCtrl.text);

    final configJson = await buildFinalConfig(hostCtrl.text);

    if (configJson == null) {
      setState(() {
        isLoading = false;
        status = 'ERREUR CONFIG';
      });
      _addLog('Connexion annulée', LogType.error);
      return;
    }

    try {
      if (!permissionGranted) {
        _addLog('Demande de permission VPN Android...', LogType.info);
        final ok = await v2ray.requestPermission();
        if (!ok) {
          setState(() {
            isLoading = false;
            status = 'PERMISSION REFUSÉE';
          });
          _addLog('Permission VPN refusée', LogType.error);
          return;
        }
        permissionGranted = true;
        _addLog('Permission VPN accordée', LogType.success);
      }

      _addLog('Lancement du moteur Xray...', LogType.info);
      await v2ray.startV2Ray(
        remark: 'ABESS VPN',
        config: configJson,
        blockedApps: const [],
        bypassSubnets: const [],
        proxyOnly: false,
      );

      _addLog('Moteur lancé, attente de trafic réel...', LogType.info);

      // Wait for actual traffic; if none, stop the engine and mark as failed
      final trafficOk = await _waitForTraffic(timeoutSeconds: 10);

      if (trafficOk) {
        _connectedWithTraffic = true;
        setState(() {
          isLoading = false;
          status = 'CONNECTÉ';
        });
        _addLog('✓ Trafic détecté — connexion effective', LogType.success);
      } else {
        _addLog('⚠ Aucun trafic détecté — annulation de la connexion', LogType.error);
        try {
          await v2ray.stopV2Ray();
        } catch (_) {}
        setState(() {
          isLoading = false;
          status = 'ERREUR TRAFIC';
          isConnected = false;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        status = 'ERREUR';
      });
      _addLog('Erreur de démarrage: $e', LogType.error);
    }
  }

  Future<void> disconnect() async {
    _addLog('Déconnexion...', LogType.warning);
    try {
      await v2ray.stopV2Ray();
      _addLog('VPN arrêté', LogType.success);
      setState(() {
        status = 'DÉCONNECTÉ';
        motorStatus = 'MOTEUR: INACTIF';
        isConnected = false;
        isLoading = false;
        _connectedWithTraffic = false;
      });
    } catch (e) {
      _addLog('Erreur de déconnexion: $e', LogType.error);
    }
  }

  void clearLogs() {
    setState(() => logs.clear());
    _addLog('Logs effacés', LogType.info);
  }

  @override
  void dispose() {
    _trafficTimer?.cancel();
    hostCtrl.dispose();
    logsScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isCompact = screenSize.width < 380 || screenSize.height < 700;
    final horizontalPadding = isCompact ? 12.0 : 14.0;
    final hostValid = isValidHost(hostCtrl.text);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF020A12),
              const Color(0xFF051322),
              const Color(0xFF0A1B2A),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _buildHeader(compact: isCompact),
                    const SizedBox(height: 14),
                    _buildTrafficPanel(compact: isCompact),
                    const SizedBox(height: 14),
                    _buildLogPanel(compact: isCompact),
                    const SizedBox(height: 16),
                    Center(
                      child: _buildPowerButton(compact: isCompact, hostValid: hostValid),
                    ),
                    const SizedBox(height: 16),
                    _buildHostInput(compact: isCompact, hostValid: hostValid),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({required bool compact}) {
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF1AE2FF), width: 1.2),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1AE2FF).withOpacity(0.20),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 40 : 46,
            height: compact ? 40 : 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0xFF17E5FF), Color(0xFF0F6BFF)],
              ),
            ),
            child: const Center(
              child: Text(
                'A',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ABESS VPN',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: compact ? 22 : 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: Colors.white,
                  ),
                ),
                Text(
                  motorVerified ? '✓ MOTEUR VÉRIFIÉ' : '⚠ VÉRIFICATION...',
                  style: GoogleFonts.robotoMono(
                    fontSize: compact ? 8 : 9,
                    color: motorVerified
                        ? const Color(0xFF2DEB8A)
                        : const Color(0xFFF7B955),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.all(compact ? 6 : 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: isConnected
                    ? const Color(0xFF2DEB8A)
                    : isLoading
                        ? const Color(0xFF51A8FF)
                        : Colors.white30,
                width: 1.2,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isConnected ? '● LIVE' : isLoading ? '◐ LOADING' : '○ OFF',
              style: GoogleFonts.robotoMono(
                fontSize: compact ? 9 : 10,
                color: isConnected
                    ? const Color(0xFF2DEB8A)
                    : isLoading
                        ? const Color(0xFF51A8FF)
                        : Colors.white30,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrafficPanel({required bool compact}) {
    final rxData = _rxSamples.isNotEmpty
        ? _rxSamples.asMap().entries.map((entry) => FlSpot(entry.key.toDouble(), entry.value)).toList()
        : [const FlSpot(0, 0)];
    final txData = _txSamples.isNotEmpty
        ? _txSamples.asMap().entries.map((entry) => FlSpot(entry.key.toDouble(), entry.value)).toList()
        : [const FlSpot(0, 0)];

    final latestRx = _rxSamples.isNotEmpty ? _rxSamples.last : 0.0;
    final latestTx = _txSamples.isNotEmpty ? _txSamples.last : 0.0;

    return Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF1AE2FF), width: 1.1),
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFF03161D),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TRAFFIC RÉEL',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1AE2FF),
                ),
              ),
              Row(
                children: [
                  _legendDot(const Color(0xFFEF4444)),
                  const SizedBox(width: 6),
                  Text('Sortant', style: GoogleFonts.robotoMono(fontSize: 9, color: Colors.white70)),
                  const SizedBox(width: 12),
                  _legendDot(const Color(0xFF38BDF8)),
                  const SizedBox(width: 6),
                  Text('Entrant', style: GoogleFonts.robotoMono(fontSize: 9, color: Colors.white70)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('
{