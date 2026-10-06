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
      theme: ThemeData.dark(useMaterial3: true).copyWith(scaffoldBackgroundColor: const Color(0xFF0F172A)),
      home: const MainScreen(),
    );
  }
}

class VpnProfile {
  String id, name, host, rawLink, jsonConfig;
  VpnProfile({required this.id, required this.name, required this.host, required this.rawLink, required this.jsonConfig});
  Map<String,dynamic> toMap() => {'id':id,'name':name,'host':host,'rawLink':rawLink,'jsonConfig':jsonConfig};
  static VpnProfile fromMap(Map m) => VpnProfile(id:m['id'], name:m['name'], host:m['host'], rawLink:m['rawLink'], jsonConfig:m['jsonConfig']);
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int index = 0;
  late FlutterV2ray v2ray;
  String status = "DÉCONNECTÉ";
  bool isConnected = false;
  String? activeProfileId;
  List<VpnProfile> profiles = [];
  List<String> logs = ["[Bébé Tunnel] Mode Profil Page 👶"];

  @override
  void initState() {
    super.initState();
    v2ray = FlutterV2ray(onStatusChanged: (s){
      if(!mounted) return;
      setState((){ status=s.state; isConnected=s.state=="CONNECTED"; logs.add("[${DateTime.now().toString().substring(11,19)}] $status"); });
    });
    v2ray.initializeV2Ray();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList('profiles')?? [];
    setState(() => profiles = list.map((e)=>VpnProfile.fromMap(jsonDecode(e))).toList());
  }
  Future<void> _saveProfiles() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('profiles', profiles.map((e)=>jsonEncode(e.toMap())).toList());
  }

  String? buildBaseJson(String raw) {
    try {
      if(raw.trim().startsWith("{")) return raw.trim();
      return FlutterV2ray.parseFromURL(raw.trim()).getFullConfiguration();
    } catch(e){ return null; }
  }

  String patchHost(String jsonStr, String host) {
    try{
      final j = jsonDecode(jsonStr);
      if(j["outbounds"]!=null && j["outbounds"].isNotEmpty){
        final outbound = j["outbounds"][0];
        final stream = Map<String,dynamic>.from(outbound["streamSettings"]??{});
        final net = stream["network"]??"ws";
        if(net=="ws"){ stream["wsSettings"]??={}; stream["wsSettings"]["headers"]??={}; stream["wsSettings"]["headers"]["Host"]=host.trim(); }
        if(stream["security"]=="tls"){ stream["tlsSettings"]??={}; stream["tlsSettings"]["serverName"]=host.trim(); stream["tlsSettings"]["allowInsecure"]=true; }
        outbound["streamSettings"]=stream;
        outbound["mux"]={"enabled":false};
        j["outbounds"][0]=outbound;
      }
      return jsonEncode(j);
    }catch(e){ return jsonStr; }
  }

  void _openProfilePage(VpnProfile profile, int idx) {
    Navigator.push(context, MaterialPageRoute(builder: (_)=> ProfileDetailPage(
      profile: profile,
      status: status,
      isConnected: activeProfileId==profile.id && isConnected,
      onSave: (updated){ setState(()=> profiles[idx]=updated); _saveProfiles(); },
      onConnect: (p) async {
        if(await v2ray.requestPermission()){
          await v2ray.startV2Ray(remark:p.name, config:p.jsonConfig, blockedApps:[], bypassSubnets:[], proxyOnly:false);
          setState(()=> activeProfileId=p.id);
        }
      },
      onDisconnect: () async => await v2ray.stopV2Ray(),
      patchHost: patchHost,
    )));
  }

  Future<void> _showImportDialog() async {
    final linkCtrl = TextEditingController();
    final nameCtrl = TextEditingController(text:"MTN ${profiles.length+1}");
    await showDialog(context: context, builder: (c)=>AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      title: Text("Importer VLESS", style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: linkCtrl, maxLines: 4, decoration: _dec("vless://....", Icons.link_rounded)),
        const SizedBox(height:12),
        TextField(controller: nameCtrl, decoration: _dec("Nom", Icons.badge_rounded)),
      ]),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(c), child: const Text("Annuler")),
        ElevatedButton(onPressed: (){
          final base = buildBaseJson(linkCtrl.text.trim());
          if(base==null){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text("Lien invalide"))); return; }
          final p = VpnProfile(id:DateTime.now().millisecondsSinceEpoch.toString(), name:nameCtrl.text, host:"", rawLink:linkCtrl.text, jsonConfig:base);
          setState(()=>profiles.add(p)); _saveProfiles(); Navigator.pop(c);
        }, child: const Text("CONVERTIR EN JSON")),
      ],
    ));
  }

  InputDecoration _dec(String hint, IconData ic) => InputDecoration(hintText:hint, prefixIcon:Icon(ic,size:18), filled:true, fillColor:const Color(0xFF0F172A), border:OutlineInputBorder(borderRadius:BorderRadius.circular(12), borderSide:BorderSide.none));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: index==0? FloatingActionButton.extended(onPressed:_showImportDialog, backgroundColor:const Color(0xFF10B981), icon:const Icon(Icons.add_link_rounded), label:Text("Importer", style:GoogleFonts.spaceGrotesk(fontWeight:FontWeight.bold))) : null,
      body: index==0? buildList() : buildLogs(),
      bottomNavigationBar: NavigationBar(selectedIndex:index, onDestinationSelected:(i)=>setState(()=>index=i), backgroundColor:const Color(0xFF1E293B), destinations:const[NavigationDestination(icon:Icon(Icons.list_alt_rounded), label:"Profils"), NavigationDestination(icon:Icon(Icons.terminal_rounded), label:"Logs")]),
    );
  }

  Widget buildList(){
    return SafeArea(child: Column(children:[
      Padding(padding: const EdgeInsets.all(20), child: Row(children:[
        ClipRRect(borderRadius:BorderRadius.circular(8), child:Image.asset("assets/logo.png", width:32, height:32, errorBuilder:(c,e,s)=>const Text("👶", style:TextStyle(fontSize:28)))),
        const SizedBox(width:10),
        Text("BEBE TUNNEL", style:GoogleFonts.spaceGrotesk(fontWeight:FontWeight.bold,fontSize:18)),
        const Spacer(),
        Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5), decoration:BoxDecoration(color:isConnected?const Color(0xFF10B981):Colors.white10, borderRadius:BorderRadius.circular(20)), child:Text(status, style:GoogleFonts.spaceGrotesk(fontSize:10))),
      ])),
      Expanded(child: profiles.isEmpty? Center(child:Text("Aucun profil\nClique Importer", textAlign:TextAlign.center, style:GoogleFonts.spaceGrotesk(color:Colors.white38))) : ListView.builder(padding:const EdgeInsets.all(12), itemCount:profiles.length, itemBuilder:(c,i){
        final p = profiles[i]; final isActive = p.id==activeProfileId && isConnected;
        return InkWell(onTap: ()=>_openProfilePage(p,i), child: Container(margin:const EdgeInsets.only(bottom:12), padding:const EdgeInsets.all(16), decoration:BoxDecoration(color:const Color(0xFF1E293B), borderRadius:BorderRadius.circular(16), border:Border.all(color:isActive?const Color(0xFF10B981):Colors.white10)), child:Row(children:[
          Container(width:48,height:48,decoration:BoxDecoration(shape:BoxShape.circle,color:isActive?const Color(0xFF10B981):const Color(0xFF0F172A)), child:Icon(isActive? Icons.vpn_lock_rounded: Icons.vpn_key_rounded, color:Colors.white)),
          const SizedBox(width:12),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[Text(p.name, style:GoogleFonts.spaceGrotesk(fontWeight:FontWeight.bold)), Text(p.host.isEmpty?"Host vide - clique pour ajouter":p.host, style:GoogleFonts.robotoMono(fontSize:11,color:p.host.isEmpty?Colors.orangeAccent:Colors.white38))])),
          const Icon(Icons.chevron_right_rounded, color:Colors.white24),
        ])));
      })),
    ]));
  }

  Widget buildLogs(){
    return SafeArea(child:Column(children:[
      Padding(padding:const EdgeInsets.all(16), child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween, children:[Text("Logs", style:GoogleFonts.spaceGrotesk(fontSize:22,fontWeight:FontWeight.bold)), IconButton(icon:const Icon(Icons.delete_outline), onPressed:()=>setState(()=>logs.clear()))])),
      Expanded(child:Container(margin:const EdgeInsets.all(12),padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.black,borderRadius:BorderRadius.circular(12)), child:ListView.builder(itemCount:logs.length, itemBuilder:(c,i)=>Text(logs[i], style:const TextStyle(color:Color(0xFF86EFAC),fontFamily:'monospace',fontSize:11))))),
    ]));
  }
}

class ProfileDetailPage extends StatefulWidget {
  final VpnProfile profile;
  final String status;
  final bool isConnected;
  final Function(VpnProfile) onSave;
  final Function(VpnProfile) onConnect;
  final Function() onDisconnect;
  final String Function(String,String) patchHost;
  const ProfileDetailPage({super.key, required this.profile, required this.status, required this.isConnected, required this.onSave, required this.onConnect, required this.onDisconnect, required this.patchHost});
  @override
  State<ProfileDetailPage> createState() => _ProfileDetailPageState();
}

class _ProfileDetailPageState extends State<ProfileDetailPage> {
  late TextEditingController nameCtrl, hostCtrl, jsonCtrl;
  @override
  void initState(){
    super.initState();
    nameCtrl=TextEditingController(text:widget.profile.name);
    hostCtrl=TextEditingController(text:widget.profile.host);
    jsonCtrl=TextEditingController(text: const JsonEncoder.withIndent(' ').convert(jsonDecode(widget.profile.jsonConfig)));
  }
  @override
  Widget build(BuildContext context){
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(backgroundColor: const Color(0xFF1E293B), title: Text(widget.profile.name, style:GoogleFonts.spaceGrotesk(fontWeight:FontWeight.bold)), actions: [
        IconButton(icon: Icon(widget.isConnected? Icons.stop_circle_rounded: Icons.play_circle_fill_rounded, color: widget.isConnected? Colors.redAccent: const Color(0xFF10B981), size:32), onPressed: (){
          if(widget.isConnected) widget.onDisconnect(); else widget.onConnect(widget.profile);
          setState((){});
        })
      ]),
      body: ListView(padding:const EdgeInsets.all(16), children:[
        Container(padding:const EdgeInsets.all(14), decoration:BoxDecoration(color:const Color(0xFF1E293B), borderRadius:BorderRadius.circular(16)), child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
          Text("CONFIGURATION PROFIL", style:GoogleFonts.spaceGrotesk(fontSize:11,color:Colors.white38,fontWeight:FontWeight.bold)),
          const SizedBox(height:12),
          TextField(controller:nameCtrl, decoration: InputDecoration(labelText:"Nom profil", filled:true, fillColor:const Color(0xFF0F172A), border:OutlineInputBorder(borderRadius:BorderRadius.circular(12), borderSide:BorderSide.none))),
          const SizedBox(height:12),
          TextField(controller:hostCtrl, decoration: InputDecoration(labelText:"HOST - yamo.mtn.cm", hintText:"yamo.mtn.cm", prefixIcon: const Icon(Icons.language_rounded), filled:true, fillColor:const Color(0xFF0F172A), border:OutlineInputBorder(borderRadius:BorderRadius.circular(12), borderSide:BorderSide.none))),
          const SizedBox(height:12),
          SizedBox(width:double.infinity, child:ElevatedButton.icon(icon:const Icon(Icons.auto_fix_high_rounded), label:Text("Appliquer HOST dans JSON", style:GoogleFonts.spaceGrotesk(fontWeight:FontWeight.bold)), style:ElevatedButton.styleFrom(backgroundColor:const Color(0xFF10B981), padding:const EdgeInsets.symmetric(vertical:14)), onPressed:(){
            final patched = widget.patchHost(jsonCtrl.text, hostCtrl.text);
            setState(()=> jsonCtrl.text = const JsonEncoder.withIndent(' ').convert(jsonDecode(patched)));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text("Host injecté dans JSON ✅")));
          })),
        ])),
        const SizedBox(height:16),
        Container(padding:const EdgeInsets.all(14), decoration:BoxDecoration(color:const Color(0xFF1E293B), borderRadius:BorderRadius.circular(16)), child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween, children:[
            Text("JSON CONFIG", style:GoogleFonts.spaceGrotesk(fontSize:11,color:Colors.white38,fontWeight:FontWeight.bold)),
            Text(widget.status, style:GoogleFonts.robotoMono(fontSize:10,color:widget.isConnected?const Color(0xFF10B981):Colors.white38)),
          ]),
          const SizedBox(height:12),
          Container(height:350, decoration:BoxDecoration(color:Colors.black, borderRadius:BorderRadius.circular(12)), padding:const EdgeInsets.all(10), child:TextField(controller:jsonCtrl, maxLines:null, expands:true, style:GoogleFonts.robotoMono(fontSize:11, color:const Color(0xFF86EFAC)), decoration: const InputDecoration(border:InputBorder.none))),
        ])),
        const SizedBox(height:20),
        SizedBox(width:double.infinity, child:ElevatedButton(onPressed:(){
          try{
            jsonDecode(jsonCtrl.text);
            final updated = VpnProfile(id:widget.profile.id, name:nameCtrl.text, host:hostCtrl.text, rawLink:widget.profile.rawLink, jsonConfig:jsonCtrl.text);
            widget.onSave(updated);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text("Profil sauvegardé ✅")));
          }catch(e){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text("JSON invalide: $e"))); }
        }, style:ElevatedButton.styleFrom(backgroundColor:Colors.white, foregroundColor:Colors.black, padding:const EdgeInsets.symmetric(vertical:16)), child:Text("SAUVEGARDER PROFIL", style:GoogleFonts.spaceGrotesk(fontWeight:FontWeight.bold)))),
      ]),
    );
  }
}
