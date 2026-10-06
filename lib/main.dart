import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const BebeTunnelApp());

class BebeTunnelApp extends StatelessWidget {
  const BebeTunnelApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
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
  List<String> logs = ["[10:59] Bébé Tunnel démarré 👶", "[10:59] Moteur XV2ray OK"];

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
          logs.add("[${DateTime.now().toString().substring(11,19)}] $status");
        });
      },
    );
    _initV2Ray();
  }

  Future<void> _initV2Ray() async {
    await v2ray.initializeV2Ray();
    final p = await SharedPreferences.getInstance();
    setState(() {
      hostCtrl.text = p.getString('host')?? "www.yahoo.com";
      serverCtrl.text = p.getString('server')?? "";
    });
    try {
      final ver = await v2ray.getCoreVersion();
      logs.add("[CORE] Xray v$ver prêt");
    } catch(_){}
  }

  // MOTEUR FIXÉ - MARCHE AVEC JSON + VLESS
  String? buildFinalConfig(String raw, String host) {
    try {
      String full;
      if (raw.trim().startsWith("{")) {
        full = raw.trim();
      } else {
        if (!raw.startsWith("vless://") &&!raw.startsWith("vmess://") &&!raw.startsWith("trojan://") &&!raw.startsWith("ss://")) {
          return null;
        }
        final parser = FlutterV2ray.parseFromURL(raw.trim());
        full = parser.getFullConfiguration();
      }

      final Map<String, dynamic> json = jsonDecode(full);

      if (host.isNotEmpty && json["outbounds"]!= null && json["outbounds"].isNotEmpty) {
        final outbound = json["outbounds"][0];
        final stream = Map<String, dynamic>.from(outbound["streamSettings"]?? {});
        final network = stream["network"]?? "ws";

        if (network == "ws") {
          stream["wsSettings"]??= {};
          stream["wsSettings"]["headers"]??= {};
          stream["wsSettings"]["headers"]["Host"] = host.trim();
        } else if (network == "http" || network == "h2") {
          stream["httpSettings"]??= {};
          stream["httpSettings"]["host"] = [host.trim()];
        }

        if (stream["security"] == "tls") {
          stream["tlsSettings"]??= {};
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

    final safeLink = serverCtrl.text.length > 25? serverCtrl.text.substring(0,25) : serverCtrl.text;
    logs.add("[${DateTime.now().toString().substring(11,19)}] Host: ${hostCtrl.text}");
    logs.add("[${DateTime.now().toString().substring(11,19)}] Lien: $safeLink...");

    final finalConf = buildFinalConfig(serverCtrl.text.trim(), hostCtrl.text.trim());

    if (finalConf == null) {
      setState(() { isLoading = false; status = "LIEN INVALIDE"; });
      logs.add("[ERREUR] Lien invalide");
      return;
    }

    logs.add("[${DateTime.now().toString().substring(11,19)}] JSON patché OK - Moteur XV2ray");

    try {
      if (await v2ray.requestPermission()) {
        await v2ray.startV2Ray(
          remark: "BebeTunnel",
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
      setState(() { isLoading = false; status = "ECHEC"; });
      logs.add("[ERREUR START] $e");
    }
  }

  Future<void> disconnect() async {
    await v2ray.stopV2Ray();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: index == 0? buildVPN() : buildLogs(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        backgroundColor: const Color(0xFF1E293B),
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
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset("assets/logo.png", width: 32, height: 32, errorBuilder:(c,e,s)=>const Text("👶", style:TextStyle(fontSize:28))),
              ),
              const SizedBox(width: 10),
              Text("BEBE TUNNEL", style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 22)),
              const Spacer(),
              Icon(isConnected? Icons.shield_rounded : Icons.shield_outlined, color: isConnected? const Color(0xFF10B981) : Colors.white24),
            ]),
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: Text(status, style: GoogleFonts.robotoMono(fontSize: 11, color: isConnected? const Color(0xFF10B981) : Colors.white38))),
            const SizedBox(height: 25),
            _inputCard("1. VOTRE HOST (injecté)", hostCtrl, "yamo.mtn.cm", Icons.language_rounded),
            const Spacer(),
            GestureDetector(
              onTap: isLoading? null : (isConnected? disconnect : connect),
              child: Container(
                width: 180, height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: isConnected? [const Color(0xFF10B981), const Color(0xFF059669)] : [const Color(0xFF1E293B), const Color(0xFF0F172A)]),
                  boxShadow: [BoxShadow(color: isConnected? const Color(0xFF10B981).withOpacity(0.4) : Colors.black26, blurRadius: 30)],
                  border: Border.all(color: Colors.white10, width: 2),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (isLoading) const CircularProgressIndicator(color: Colors.orangeAccent)
                  else Icon(Icons.power_settings_new_rounded, size: 50, color: isConnected? Colors.white : Colors.white38),
                  const SizedBox(height: 8),
                  Text(isLoading? "CONNEXION..." : (isConnected? "STOP" : "START"), style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
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
        Padding(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text("Logs", style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.bold)),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => logs.clear())),
        ])),
        Expanded(child: Container(margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)), child: ListView.builder(itemCount: logs.length, itemBuilder: (c,i) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(logs[i], style: const TextStyle(color: Color(0xFF86EFAC), fontFamily: 'monospace', fontSize: 11)))))),
      ]),
    );
  }

  Widget _inputCard(String title, TextEditingController ctrl, String hint, IconData icon, {int maxLines = 1}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.spaceGrotesk(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(controller: ctrl, maxLines: maxLines, style: GoogleFonts.robotoMono(fontSize: 12), decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon, size: 18), filled: true, fillColor: const Color(0xFF0F172A), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      ]),
    );
  }
}
