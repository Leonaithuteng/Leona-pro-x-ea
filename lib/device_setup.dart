import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const String setupApiBaseUrl = 'https://leona-pro-x-api.onrender.com';

class DeviceSetupPage extends StatefulWidget {
  final String token;
  const DeviceSetupPage({super.key, required this.token});
  @override State<DeviceSetupPage> createState() => _DeviceSetupPageState();
}

class _DeviceSetupPageState extends State<DeviceSetupPage> {
  final name = TextEditingController(text: 'My MT5');
  final account = TextEditingController();
  List<dynamic> devices = [];
  bool loading = true;
  bool saving = false;
  String? createdDeviceId;
  String? createdEaToken;

  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + widget.token,
  };

  @override
  void initState() {
    super.initState();
    loadDevices();
  }

  @override
  void dispose() {
    name.dispose();
    account.dispose();
    super.dispose();
  }

  Future<void> loadDevices() async {
    try {
      final r = await http.get(
        Uri.parse(setupApiBaseUrl + '/api/v1/devices'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) throw Exception();
      final d = jsonDecode(r.body);
      if (!mounted) return;
      setState(() {
        devices = d['items'] ?? [];
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> register() async {
    if (name.text.trim().isEmpty) return;
    setState(() => saving = true);
    try {
      final body = {
        'device_name': name.text.trim(),
        'broker': 'Weltrade',
        'account': account.text.trim().isEmpty ? null : account.text.trim(),
      };
      final r = await http.post(
        Uri.parse(setupApiBaseUrl + '/api/v1/devices/register'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode < 200 || r.statusCode >= 300) throw Exception();
      final d = jsonDecode(r.body);
      if (!mounted) return;
      setState(() {
        createdDeviceId = d['device_id']?.toString();
        createdEaToken = d['ea_token']?.toString();
      });
      await loadDevices();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device registration failed.')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> copyValue(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label copied to clipboard.')),
      );
    }
  }

  Widget copyRow(String label, String value) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: SelectableText(value),
        trailing: IconButton(
          icon: const Icon(Icons.copy),
          onPressed: () => copyValue(value, label),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MT5 DEVICE SETUP')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'CONNECT MT5',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white60),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Register this MT5 installation, then copy the Device ID and EA Token into the Leona Pro X EA settings in MetaTrader 5.',
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Device name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: account,
                  decoration: const InputDecoration(
                    labelText: 'Weltrade account (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: saving ? null : register,
                    icon: const Icon(Icons.add_link),
                    label: saving
                        ? const CircularProgressIndicator()
                        : const Text('REGISTER MT5 DEVICE'),
                  ),
                ),
                if (createdDeviceId != null && createdEaToken != null) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'NEW EA CREDENTIALS',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent),
                  ),
                  const SizedBox(height: 8),
                  copyRow('Device ID', createdDeviceId!),
                  copyRow('EA Token', createdEaToken!),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Keep the EA Token private. It is used by MT5 to authenticate with the Leona Pro X API.',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'REGISTERED MT5 DEVICES',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white60),
                ),
                const SizedBox(height: 8),
                if (devices.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No devices registered yet.'),
                    ),
                  )
                else
                  ...devices.map(
                    (d) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.computer),
                        title: Text(d['device_name']?.toString() ?? 'MT5'),
                        subtitle: Text(
                          (d['device_id']?.toString() ?? '') +
                          ' • ' +
                          (d['status']?.toString() ?? 'UNKNOWN'),
                        ),
                        trailing: Text(d['broker']?.toString() ?? 'Weltrade'),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
