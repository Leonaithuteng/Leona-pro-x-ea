import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String deviceApiBaseUrl = 'https://leona-pro-x-api.onrender.com';

class DeviceSettingsPage extends StatefulWidget {
  final String token;
  const DeviceSettingsPage({super.key, required this.token});
  @override State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage> {
  List<dynamic> devices = [];
  String? selectedDevice;
  bool loading = true, saving = false;
  final risk = TextEditingController(text: '1.0');
  final lot = TextEditingController(text: '0.01');
  String sizingMode = 'RISK';
  final sl = TextEditingController(text: '150');
  final tp = TextEditingController(text: '250');
  final daily = TextEditingController(text: '3.0');
  final dd = TextEditingController(text: '10.0');

  Map<String,String> get headers => {'Content-Type':'application/json','Authorization':'Bearer ' + widget.token};

  @override void initState() { super.initState(); loadDevices(); }
  @override void dispose() { risk.dispose(); lot.dispose(); sl.dispose(); tp.dispose(); daily.dispose(); dd.dispose(); super.dispose(); }

  Future<void> loadDevices() async {
    try {
      final r = await http.get(Uri.parse(deviceApiBaseUrl + '/api/v1/devices'), headers: headers).timeout(const Duration(seconds:10));
      if (r.statusCode != 200) throw Exception();
      final d = jsonDecode(r.body);
      if (!mounted) return;
      setState(() { devices = d['items'] ?? []; if (devices.isNotEmpty) selectedDevice = devices.first['device_id']; loading = false; });
      if (selectedDevice != null) await loadSettings();
    } catch (_) { if (mounted) setState(() => loading = false); }
  }

  Future<void> loadSettings() async {
    if (selectedDevice == null) return;
    final r = await http.get(Uri.parse(deviceApiBaseUrl + '/api/v1/devices/' + selectedDevice! + '/settings'), headers: headers);
    if (r.statusCode != 200 || !mounted) return;
    final d = jsonDecode(r.body);
    setState(() { sizingMode = (d['sizing_mode'] ?? 'RISK').toString(); lot.text = '${d['lot_size'] ?? 0.01}'; risk.text = '${d['risk_percent']}'; sl.text = '${d['sl_points']}'; tp.text = '${d['tp_points']}'; daily.text = '${d['max_daily_loss']}'; dd.text = '${d['max_drawdown']}'; });
  }

  Future<void> save() async {
    if (selectedDevice == null) return;
    setState(() => saving = true);
    try {
      final body = {'sizing_mode':sizingMode,'lot_size':double.tryParse(lot.text) ?? 0.01,'risk_percent':double.tryParse(risk.text) ?? 1.0,'sl_points':int.tryParse(sl.text) ?? 150,'tp_points':int.tryParse(tp.text) ?? 250,'max_daily_loss':double.tryParse(daily.text) ?? 3.0,'max_drawdown':double.tryParse(dd.text) ?? 10.0};
      final r = await http.put(Uri.parse(deviceApiBaseUrl + '/api/v1/devices/' + selectedDevice! + '/settings'), headers: headers, body: jsonEncode(body));
      if (r.statusCode < 200 || r.statusCode >= 300) throw Exception();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved and queued for MT5.')));
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to save settings.'))); }
    finally { if (mounted) setState(() => saving = false); }
  }

  Widget field(TextEditingController c, String label) => Padding(padding: const EdgeInsets.only(bottom:12), child: TextField(controller:c, keyboardType: const TextInputType.numberWithOptions(decimal:true), decoration:InputDecoration(labelText:label,border:const OutlineInputBorder())));

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('MT5 DEVICE & RISK')),
    body: loading ? const Center(child:CircularProgressIndicator()) : ListView(padding:const EdgeInsets.all(16), children:[
      if (devices.isEmpty) const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('No MT5 device is registered yet.')))
      else ...[
        DropdownButtonFormField<String>(initialValue:selectedDevice, decoration:const InputDecoration(labelText:'MT5 Device',border:OutlineInputBorder()), items:devices.map<DropdownMenuItem<String>>((d)=>DropdownMenuItem<String>(value:d['device_id'],child:Text(d['device_name'].toString() + ' • ' + d['status'].toString()))).toList(), onChanged:(v) async { setState(()=>selectedDevice=v); await loadSettings(); }),
        const SizedBox(height:20), const Text('POSITION SIZING & RISK',style:TextStyle(fontWeight:FontWeight.bold)), const SizedBox(height:12),
        DropdownButtonFormField<String>(initialValue:sizingMode, decoration:const InputDecoration(labelText:'Position sizing mode',border:OutlineInputBorder()), items:const [DropdownMenuItem(value:'RISK',child:Text('Risk percentage')),DropdownMenuItem(value:'FIXED_LOT',child:Text('Fixed lot size'))], onChanged:(v){if(v!=null)setState(()=>sizingMode=v);}), const SizedBox(height:12), field(lot,'Fixed lot size'), field(risk,'Risk per trade (%)'), field(sl,'Stop Loss (points)'), field(tp,'Take Profit (points)'), field(daily,'Max Daily Loss (%)'), field(dd,'Max Drawdown (%)'),
        SizedBox(width:double.infinity,child:ElevatedButton(onPressed:saving?null:save,child:saving?const CircularProgressIndicator():const Text('SAVE & SEND TO MT5'))),
      ],
    ]),
  );
}