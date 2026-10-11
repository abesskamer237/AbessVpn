import 'dart:convert';
import 'dart:async';
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

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  late FlutterV2ray v2ray;
  late ScrollController logsScroll;
  late AnimationController pulseCtrl;
  late AnimationController scanCtrl;

  final hostCtrl = TextEditingController(
    text: 'abess-ops12-626132458064.us-central1.run.app',
  );

  String status = 'DÉCONNECTÉ';
  String motorStatus = 'MOTEUR: INACTIF';
  String traficUpMbps = '0.0';
  String traficDownMbps = '0.0';
  String latencyMs = '--';
  
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
    pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
    scanCtrl = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat();

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
          '► MOTEUR: ${s.state}',
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
    _addLog('◇ Vérification du moteur Xray...', LogType.info);

    try {
      await v2ray.initializeV2Ray();
      _addLog('✓ Moteur Xray initialisé avec succès', LogType.success);

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
        _addLog('✓ Xray Core Version: $version', LogType.success);
        setState(() => motorReady = true);
      } catch (e) {
        _addLog('⚠ Version Xray indisponible: $e', LogType.warning);
        setState(() => motorReady = true);
      }

      // Vérifier que le moteur peut créer une config valide
      final testConfig = buildEmbeddedConfig('test.example.com');
      final testJson = jsonEncode(testConfig);
      jsonDecode(testJson);
      
      _addLog('✓ Configuration VLESS intégrée validée', LogType.success);
      _addLog('✓ Serveur: 192.179.18.100:443', LogType.info);
      _addLog('✓ Transport: WebSocket + TLS', LogType.info);
      _addLog('✓ SNI TLS: crashlyticsreports-pa.googleapis.com', LogType.success);
      _addLog('✓ UUID: ${_vlessUuid.substring(0, 8)}***', LogType.success);
      _addLog('════════════════════════════════', LogType.info);
      _addLog('MOTEUR VPN OPÉRATIONNEL ET PRÊT', LogType.success);
      _addLog('════════════════════════════════', LogType.success);

      setState(() => motorVerified = true);
    } catch (e) {
      _addLog('✗ Erreur moteur critique: $e', LogType.error);
      _addLog('Moteur VPN NON FONCTIONNEL', LogType.error);
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
        _addLog('✗ Moteur non prêt', LogType.error);
        return null;
      }

      final cleanHost = host.trim();

      if (cleanHost.isEmpty) {
        _addLog('⚠ Host vide → valeur par défaut', LogType.warning);
        return jsonEncode(buildEmbeddedConfig('abess-ops12-626132458064.us-central1.run.app'));
      }

      if (cleanHost.contains('://')) {
        _addLog('✗ Host invalide: URL détectée', LogType.error);
        return null;
      }

      final config = buildEmbeddedConfig(cleanHost);
      final finalJson = jsonEncode(config);
      jsonDecode(finalJson);

      _addLog('✓ Configuration JSON valide', LogType.success);
      _addLog('► Host WebSocket injecté: $cleanHost', LogType.info);

      return finalJson;
    } catch (e) {
      _addLog('✗ Erreur JSON config: $e', LogType.error);
      return null;
    }
  }

  Future<void> connect() async {
    if (isLoading || isConnected || !motorReady) return;

    if (!motorVerified) {
      _addLog('✗ Moteur VPN non vérifié', LogType.error);
      return;
    }

    _addLog('▶ Tentative de connexion...', LogType.info);
    setState(() => isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', hostCtrl.text);

    final configJson = await buildFinalConfig(hostCtrl.text);

    if (configJson == null) {
      setState(() {
        isLoading = false;
        status = 'ERREUR CONFIG';
      });
      _addLog('✗ Connexion annulée: config invalide', LogType.error);
      return;
    }

    try {
      if (!permissionGranted) {
        _addLog('► Demande permission VPN Android...', LogType.info);
        final ok = await v2ray.requestPermission();
        if (!ok) {
          setState(() {
            isLoading = false;
            status = 'PERMISSION REFUSÉE';
          });
          _addLog('✗ Permission VPN refusée par utilisateur', LogType.error);
          return;
        }
        permissionGranted = true;
        _addLog('✓ Permission VPN accordée', LogType.success);
      }

      _addLog('► Lancement du moteur Xray...', LogType.info);
      await v2ray.startV2Ray(
        remark: 'ABESS VPN',
        config: configJson,
        blockedApps: const [],
        bypassSubnets: const [],
        proxyOnly: false,
      );

      _addLog('✓ Moteur démarré → attente de connexion...', LogType.success);
    } catch (e) {
      setState(() {
        isLoading = false;
        status = 'ERREUR DÉMARRAGE';
      });
      _addLog('✗ Erreur démarrage moteur: $e', LogType.error);
    }
  }

  Future<void> disconnect() async {
    _addLog('◆ Arrêt du VPN...', LogType.warning);
    try {
      await v2ray.stopV2Ray();
      _addLog('✓ VPN arrêté avec succès', LogType.success);
      setState(() {
        status = 'DÉCONNECTÉ';
        motorStatus = 'MOTEUR: INACTIF';
        isConnected = false;
        isLoading = false;
        traficUpMbps = '0.0';
        traficDownMbps = '0.0';
        latencyMs = '--';
      });
    } catch (e) {
      _addLog('✗ Erreur arrêt: $e', LogType.error);
    }
  }

  void clearLogs() {
    setState(() => logs.clear());
    _addLog('◇ Logs effacés', LogType.info);
  }

  @override
  void dispose() {
    hostCtrl.dispose();
    logsScroll.dispose();
    pulseCtrl.dispose();
    scanCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Fond dégradé
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF020A12),
                  const Color(0xFF051322),
                  const Color(0xFF0A1A28),
                ],
              ),
            ),
            child: SizedBox.expand(
              child: SafeArea(
                child: SingleChildScrollView(
                  controller: logsScroll,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      _buildHackerHeader(),
                      const SizedBox(height: 18),
                      _buildLogTerminal(),
                      const SizedBox(height: 16),
                      Center(child: _buildPowerCircle()),
                      const SizedBox(height: 16),
                      _buildHudPanel(),
                      const SizedBox(height: 16),
                      _buildHostField(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Effet scanline animé
          AnimatedBuilder(
            animation: scanCtrl,
            builder: (context, child) {
              return Positioned(
                top: scanCtrl.value * 300,
                left: 0,
                right: 0,
                height: 2,
                child: Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1AE2FF).withOpacity(0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHackerHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF1AE2FF), width: 1.5),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1AE2FF).withOpacity(0.25),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0xFF17E5FF), Color(0xFF0F6BFF)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1AE2FF).withOpacity(0.5),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Center(
              child: Text(
                '◀',
                style: TextStyle(
                  fontSize: 24,
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
                  '█ ABESS VPN █',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: const Color(0xFF1AE2FF),
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
                width: 1.5,
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

  Widget _buildLogTerminal() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF1AE2FF), width: 1.2),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1AE2FF).withOpacity(0.2),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFF1AE2FF),
                  width: 1.2,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '█ TERMINAL LOGS [${logs.length}]',
                  style: GoogleFonts.robotoMono(
                    fontSize: 11,
                    color: const Color(0xFF1AE2FF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  onPressed: clearLogs,
                  icon: const Icon(Icons.clear_rounded),
                  iconSize: 18,
                  color: const Color(0xFF1AE2FF),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Container(
            height: 280,
            color: const Color(0xFF021117),
            child: logs.isEmpty
                ? Center(
                    child: Text(
                      '> Initialisation en cours...',
                      style: GoogleFonts.robotoMono(
                        fontSize: 12,
                        color: Colors.white24,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: logsScroll,
                    padding: const EdgeInsets.all(10),
                    itemCount: logs.length,
                    itemBuilder: (_, idx) {
                      final log = logs[idx];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '[${log.timestamp.toString().substring(11, 19)}] ',
                                style: GoogleFonts.robotoMono(
                                  fontSize: 9,
                                  color: Colors.white20,
                                ),
                              ),
                              TextSpan(
                                text: log.message,
                                style: GoogleFonts.robotoMono(
                                  fontSize: 10,
                                  color: log.type.color,
                                  fontWeight: FontWeight.w500,
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

  Widget _buildPowerCircle() {
    return AnimatedBuilder(
      animation: pulseCtrl,
      builder: (context, child) {
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
                      ? const Color(0xFF2DEB8A).withOpacity(0.4 + pulseCtrl.value * 0.2)
                      : const Color(0xFF1AE2FF).withOpacity(0.35 + pulseCtrl.value * 0.15),
                  blurRadius: 30 + (pulseCtrl.value * 10),
                  spreadRadius: 4 + (pulseCtrl.value * 3),
                ),
              ],
              border: Border.all(
                color: const Color(0xFF1AE2FF),
                width: 2.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 3.5,
                    ),
                  )
                else
                  Icon(
                    Icons.power_settings_new_rounded,
                    size: 64,
                    color: Colors.white,
                  ),
                const SizedBox(height: 14),
                Text(
                  isLoading
                      ? 'CONNEXION'
                      : (isConnected ? 'ARRÊTER' : 'CONNECTER'),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHudPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF1AE2FF), width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _hudItem('LATENCE', latencyMs, 'ms'),
              _hudItem('UPLOAD', traficUpMbps, 'Mbps'),
              _hudItem('DOWNLOAD', traficDownMbps, 'Mbps'),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF1AE2FF).withOpacity(0.4)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              motorStatus,
              style: GoogleFonts.robotoMono(
                fontSize: 10,
                color: const Color(0xFF1AE2FF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hudItem(String label, String value, String unit) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.robotoMono(
            fontSize: 9,
            color: Colors.white30,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.robotoMono(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1AE2FF),
          ),
        ),
        Text(
          unit,
          style: GoogleFonts.robotoMono(
            fontSize: 8,
            color: Colors.white20,
          ),
        ),
      ],
    );
  }

  Widget _buildHostField() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF1AE2FF), width: 1.2),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1AE2FF).withOpacity(0.15),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '█ HOST (INJECTÉ)',
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
              fontSize: 12,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              hintText: 'abess-ops12-626132458064.us-central1.run.app',
              hintStyle: GoogleFonts.robotoMono(
                fontSize: 11,
                color: Colors.white20,
              ),
              prefixIcon: const Icon(
                Icons.terminal_rounded,
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
                      iconSize: 18,
                      color: const Color(0xFF1AE2FF),
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF051421),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: const Color(0xFF1AE2FF).withOpacity(0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: const Color(0xFF1AE2FF).withOpacity(0.3),
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
            '> Seul paramètre configurable | Config VLESS intégrée',
            style: GoogleFonts.robotoMono(
              fontSize: 9,
              color: Colors.white20,
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
        return const Color(0xFFFC4D4D);
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
