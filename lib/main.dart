import 'dart:convert';
import 'package:flutter/material.dart';
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

  final hostCtrl = TextEditingController(
    text: 'abess-ops12-626132458064.us-central1.run.app',
  );

  String status = 'DÉCONNECTÉ';
  String motorStatus = 'MOTEUR: INACTIF';

  bool isConnected = false;
  bool isLoading = false;
  bool permissionGranted = false;
  bool motorReady = false;
  bool motorVerified = false;

  final List<LogEntry> logs = [];

  // UUID VLESS intégré
  static const String _vlessUuid = 'cc6e26f5-e8a0-4a3c-8e57-f60aa57e9e8e';

  static Map<String, dynamic> buildEmbeddedConfig(String host) {
    final finalHost = host.trim().isEmpty
        ? 'abess-ops12-626132458064.us-central1.run.app'
        : host.trim();

    return {
      'inbounds': [
        {
          'port': 10808,
          'protocol': 'socks',
          'settings': {'udp': true},
        }
      ],
      'outbounds': [
        {
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': '192.179.18.100',
                'port': 443,
                'users': [
                  {'id': _vlessUuid, 'encryption': 'none'}
                ],
              }
            ],
          },
          'streamSettings': {
            'network': 'ws',
            'security': 'tls',
            'tlsSettings': {
              'serverName': 'crashlyticsreports-pa.googleapis.com',
              'allowInsecure': false,
              'alpn': ['h2', 'http/1.1'],
            },
            'wsSettings': {
              'path': '/@abess237',
              'headers': {
                'Host': finalHost,
              }
            }
          },
          'mux': {'enabled': false},
        }
      ]
    };
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
  }

  Future<void> _verifyMotor() async {
    _addLog('Démarrage ABESS VPN...', LogType.info);
    _addLog('Initialisation du moteur Xray...', LogType.info);

    try {
      await v2ray.initializeV2Ray();
      _addLog('✓ Moteur Xray initialisé', LogType.success);

      final prefs = await SharedPreferences.getInstance();
      final savedHost = prefs.getString('host') ??
          'abess-ops12-626132458064.us-central1.run.app';

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

      final testConfig = buildEmbeddedConfig('test.example.com');
      final testJson = jsonEncode(testConfig);
      jsonDecode(testJson);

      _addLog('✓ Configuration VLESS intégrée validée', LogType.success);
      _addLog('✓ Serveur: 192.179.18.100:443', LogType.info);
      _addLog('✓ Transport: WebSocket + TLS', LogType.info);
      _addLog('✓ SNI TLS: crashlyticsreports-pa.googleapis.com', LogType.success);
      _addLog('✓ UUID intégré', LogType.success);

      setState(() => motorVerified = true);
      _addLog('MOTEUR VPN PRÊT', LogType.success);
    } catch (e) {
      _addLog('Erreur critique du moteur: $e', LogType.error);
      setState(() => motorReady = false);
    }
  }

  void _addLog(String message, LogType type) {
    if (!mounted) return;

    setState(() {
      logs.add(LogEntry(
        message: message,
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
        return jsonEncode(buildEmbeddedConfig('abess-ops12-626132458064.us-central1.run.app'));
      }

      if (cleanHost.contains('://')) {
        _addLog('Host invalide: URL détectée', LogType.error);
        return null;
      }

      final config = buildEmbeddedConfig(cleanHost);
      final configJson = jsonEncode(config);
      jsonDecode(configJson);

      _addLog('✓ JSON valide', LogType.success);
      _addLog('Host injecté: $cleanHost', LogType.info);

      return configJson;
    } catch (e) {
      _addLog('Erreur config: $e', LogType.error);
      return null;
    }
  }

  Future<void> connect() async {
    if (isLoading || isConnected || !motorReady) return;

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

      _addLog('Lancement du moteur...', LogType.info);
      await v2ray.startV2Ray(
        remark: 'ABESS VPN',
        config: configJson,
        blockedApps: const [],
        bypassSubnets: const [],
        proxyOnly: false,
      );

      _addLog('Connexion en cours...', LogType.info);
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
    hostCtrl.dispose();
    logsScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                _buildHeader(),
                const SizedBox(height: 18),
                _buildLogPanel(),
                const SizedBox(height: 18),
                Center(child: _buildPowerButton()),
                const SizedBox(height: 18),
                _buildHostInput(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF1AE2FF), width: 1.4),
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
            width: 46,
            height: 46,
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ABESS VPN',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                    color: Colors.white,
                  ),
                ),
                Text(
                  motorVerified ? '✓ MOTEUR VÉRIFIÉ' : '⚠ VÉRIFICATION...',
                  style: GoogleFonts.robotoMono(
                    fontSize: 9,
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
            padding: const EdgeInsets.all(8),
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
                fontSize: 10,
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

  Widget _buildLogPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF1AE2FF), width: 1.2),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1AE2FF).withOpacity(0.22),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TERMINAL LOGS',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1AE2FF),
                ),
              ),
              IconButton(
                onPressed: clearLogs,
                icon: const Icon(Icons.delete_outline_rounded),
                color: const Color(0xFF1AE2FF),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 260,
            color: const Color(0xFF021117),
            child: logs.isEmpty
                ? Center(
                    child: Text(
                      'Aucun log pour le moment',
                      style: GoogleFonts.robotoMono(
                        fontSize: 12,
                        color: Colors.white24,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: logsScroll,
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '[${log.timestamp.toString().substring(11, 19)}] ',
                                style: GoogleFonts.robotoMono(
                                  fontSize: 9,
                                  color: Colors.white12,
                                ),
                              ),
                              TextSpan(
                                text: log.message,
                                style: GoogleFonts.robotoMono(
                                  fontSize: 10,
                                  color: log.type.color,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPowerButton() {
    return GestureDetector(
      onTap: !motorReady || !motorVerified
          ? null
          : (isLoading ? null : (isConnected ? disconnect : connect)),
      child: Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isConnected
                ? [const Color(0xFF2DEB8A), const Color(0xFF0D7C4E)]
                : isLoading
                    ? [const Color(0xFF1AE2FF), const Color(0xFF0A5CD2)]
                    : [const Color(0xFF1D4ED8), const Color(0xFF0A0F2A)],
          ),
          boxShadow: [
            BoxShadow(
              color: isConnected
                  ? const Color(0xFF2DEB8A).withOpacity(0.45)
                  : const Color(0xFF1AE2FF).withOpacity(0.35),
              blurRadius: 28,
              spreadRadius: 4,
            ),
          ],
          border: Border.all(
            color: const Color(0xFF1AE2FF),
            width: 2.2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 54,
                height: 54,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 3.3,
                ),
              )
            else
              const Icon(
                Icons.power_settings_new_rounded,
                size: 62,
                color: Colors.white,
              ),
            const SizedBox(height: 12),
            Text(
              isLoading
                  ? 'CONNEXION...'
                  : (isConnected ? 'ARRÊTER' : 'CONNECTER'),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostInput() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF1AE2FF), width: 1.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HOST (INJECTÉ)',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1AE2FF),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: hostCtrl,
            enabled: !isLoading && !isConnected && motorVerified,
            style: GoogleFonts.robotoMono(
              fontSize: 13,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              hintText: 'abess-ops12-626132458064.us-central1.run.app',
              prefixIcon: const Icon(
                Icons.language_rounded,
                color: Color(0xFF1AE2FF),
                size: 18,
              ),
              suffixIcon: hostCtrl.text.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        hostCtrl.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear_rounded),
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF051421),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: const Color(0xFF1AE2FF).withOpacity(0.25),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: const Color(0xFF1AE2FF).withOpacity(0.25),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(
                  color: Color(0xFF1AE2FF),
                  width: 2,
                ),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            'Seul paramètre configurable — config VLESS intégrée',
            style: GoogleFonts.robotoMono(
              fontSize: 9,
              color: Colors.white24,
            ),
          ),
        ],
      ),
    );
  }
}

enum LogType { info, success, warning, error }

extension LogTypeExt on LogType {
  Color get color {
    switch (this) {
      case LogType.info:
        return const Color(0xFF1AE2FF);
      case LogType.success:
        return const Color(0xFF2DEB8A);
      case LogType.warning:
        return const Color(0xFFF7B955);
      case LogType.error:
        return const Color(0xFFEF4444);
    }
  }
}

class LogEntry {
  final String message;
  final LogType type;
  final DateTime timestamp;

  LogEntry({
    required this.message,
    required this.type,
    required this.timestamp,
  });
}
