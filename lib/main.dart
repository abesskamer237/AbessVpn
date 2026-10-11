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
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF07131F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1D4ED8),
          brightness: Brightness.dark,
        ),
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
  int index = 0;
  late FlutterV2ray v2ray;
  final hostCtrl = TextEditingController(text: "www.yahoo.com");
  final serverCtrl = TextEditingController();
  String status = "DÉCONNECTÉ";
  bool isConnected = false;
  bool isLoading = false;
  List<String> logs = ["[10:59] AbessVPN démarré 🔐", "[10:59] Moteur XV2ray OK"];

  @override
  void initState() {
    super.initState();
    v2ray = FlutterV2ray(
      onStatusChanged: (s) {
        if (!mounted) return;
        setState(() {
          status = s.state;
          isConnected = s.state == "CONNECTED";
          isLoading = s.state == "CONNECTING";
          logs.add("[${DateTime.now().toString().substring(11, 19)}] $status");
        });
      },
    );
    _initV2Ray();
  }

  Future<void> _initV2Ray() async {
    await v2ray.initializeV2Ray();
    final p = await SharedPreferences.getInstance();
    setState(() {
      hostCtrl.text = p.getString('host') ?? "www.yahoo.com";
      serverCtrl.text = p.getString('server') ?? "";
    });
    try {
      final ver = await v2ray.getCoreVersion();
      logs.add("[CORE] Xray v$ver prêt");
    } catch (_) {}
  }

  String? buildFinalConfig(String raw, String host) {
    try {
      String full;
      if (raw.trim().startsWith("{")) {
        full = raw.trim();
      } else {
        if (!raw.startsWith("vless://") &&
            !raw.startsWith("vmess://") &&
            !raw.startsWith("trojan://") &&
            !raw.startsWith("ss://")) {
          return null;
        }
        final parser = FlutterV2ray.parseFromURL(raw.trim());
        full = parser.getFullConfiguration();
      }

      final Map<String, dynamic> json = jsonDecode(full);

      if (host.isNotEmpty && json["outbounds"] != null && json["outbounds"].isNotEmpty) {
        final outbound = json["outbounds"][0];
        final stream = Map<String, dynamic>.from(outbound["streamSettings"] ?? {});
        final network = stream["network"] ?? "ws";

        if (network == "ws") {
          stream["wsSettings"] ??= {};
          stream["wsSettings"]["headers"] ??= {};
          stream["wsSettings"]["headers"]["Host"] = host.trim();
        } else if (network == "http" || network == "h2") {
          stream["httpSettings"] ??= {};
          stream["httpSettings"]["host"] = [host.trim()];
        }

        if (stream["security"] == "tls") {
          stream["tlsSettings"] ??= {};
          stream["tlsSettings"]["serverName"] = host.trim();
          stream["tlsSettings"]["allowInsecure"] = true;
        }

        outbound["streamSettings"] = stream;
        outbound["mux"] = {"enabled": false};
        json["outbounds"][0] = outbound;
      }
      return jsonEncode(json);
    } catch (e) {
      logs.add("[ERREUR MOTEUR] $e");
      return null;
    }
  }

  Future<void> connect() async {
    if (serverCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Colle ton lien VLESS d'abord!")));
      return;
    }
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', hostCtrl.text);
    await prefs.setString('server', serverCtrl.text);

    final safeLink = serverCtrl.text.length > 25 ? serverCtrl.text.substring(0, 25) : serverCtrl.text;
    logs.add("[${DateTime.now().toString().substring(11, 19)}] Host: ${hostCtrl.text}");
    logs.add("[${DateTime.now().toString().substring(11, 19)}] Lien: $safeLink...");

    final finalConf = buildFinalConfig(serverCtrl.text.trim(), hostCtrl.text.trim());

    if (finalConf == null) {
      setState(() {
        isLoading = false;
        status = "LIEN INVALIDE";
      });
      logs.add("[ERREUR] Lien invalide");
      return;
    }

    logs.add("[${DateTime.now().toString().substring(11, 19)}] JSON patché OK - Moteur XV2ray");

    try {
      if (await v2ray.requestPermission()) {
        await v2ray.startV2Ray(
          remark: "AbessVpn",
          config: finalConf,
          blockedApps: [],
          bypassSubnets: [],
          proxyOnly: false,
        );
      } else {
        setState(() => isLoading = false);
        logs.add("[PERMISSION] Refusée");
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        status = "ECHEC";
      });
      logs.add("[ERREUR START] $e");
    }
  }

  Future<void> disconnect() async {
    await v2ray.stopV2Ray();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: index == 0 ? buildVPN() : buildLogs(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        backgroundColor: const Color(0xFF0B172A),
        indicatorColor: const Color(0xFF2563EB),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.vpn_lock_rounded), label: "VPN"),
          NavigationDestination(icon: Icon(Icons.terminal_rounded), label: "Logs"),
        ],
      ),
    );
  }

  Widget buildVPN() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(colors: [Color(0xFF38BDF8), Color(0xFF2563EB)]),
                  boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withOpacity(0.4), blurRadius: 16)],
                ),
                child: const Center(child: Text("A", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("ABESSVPN", style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 26)),
                  Text("Secure tunnel", style: GoogleFonts.robotoMono(fontSize: 10, color: Colors.white54)),
                ],
              ),
              const Spacer(),
              Icon(isConnected ? Icons.shield_rounded : Icons.shield_outlined, color: isConnected ? const Color(0xFF22C55E) : Colors.white30),
            ]),
            const SizedBox(height: 18),
            Align(alignment: Alignment.centerLeft, child: Text(status, style: GoogleFonts.robotoMono(fontSize: 11, color: isConnected ? const Color(0xFF22C55E) : Colors.white38))),
            const SizedBox(height: 24),
            _inputCard("1. VOTRE HOST (injecté)", hostCtrl, "yamo.mtn.cm", Icons.language_rounded),
            const Spacer(),
            GestureDetector(
              onTap: isLoading ? null : (isConnected ? disconnect : connect),
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isConnected
                        ? [const Color(0xFF22C55E), const Color(0xFF15803D)]
                        : [const Color(0xFF1D4ED8), const Color(0xFF0F172A)],
                  ),
                  boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withOpacity(0.35), blurRadius: 28)],
                  border: Border.all(color: Colors.white12, width: 2),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (isLoading)
                    const CircularProgressIndicator(color: Colors.white)
                  else
                    Icon(Icons.power_settings_new_rounded, size: 52, color: Colors.white),
                  const SizedBox(height: 8),
                  Text(isLoading ? "CONNEXION..." : (isConnected ? "STOP" : "START"), style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 18)),
                ]),
              ),
            ),
            const Spacer(),
            _inputCard("2. LIEN VLESS / VMESS", serverCtrl, "vless:// ou vmess://...", Icons.dns_rounded, maxLines: 4),
          ],
        ),
      ),
    );
  }

  Widget buildLogs() {
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Logs", style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => logs.clear())),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF020817), borderRadius: BorderRadius.circular(14)),
            child: ListView(
              children: logs.map((line) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(line, style: GoogleFonts.robotoMono(fontSize: 12, color: Colors.white70)),
              )).toList(),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _inputCard(String title, TextEditingController ctrl, String hint, IconData icon, {int maxLines = 1}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.spaceGrotesk(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: GoogleFonts.robotoMono(fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 18, color: const Color(0xFF60A5FA)),
            filled: true,
            fillColor: const Color(0xFF0A1324),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ]),
    );
  }
}
