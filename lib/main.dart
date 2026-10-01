
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'device_settings.dart';
import 'device_setup.dart';

const String apiBaseUrl = 'https://leona-pro-x-api.onrender.com';

void main() {
  runApp(const LeonaProXApp());
}

class LeonaProXApp extends StatelessWidget {
  const LeonaProXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Leona Pro X EA',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0F14),
        colorScheme: const ColorScheme.dark(
          primary: Colors.greenAccent,
          secondary: Colors.greenAccent,
        ),
        cardColor: const Color(0xFF151B23),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? token;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { final p=await SharedPreferences.getInstance(); if(mounted)setState(()=>token=p.getString('access_token')); }
  @override Widget build(BuildContext context) => token == null ? const LoginPage() : DashboardPage(token: token!);
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final u=TextEditingController(), p=TextEditingController(); bool busy=false; String error='';
  Future<void> login() async {
    if(u.text.trim().isEmpty||p.text.isEmpty){setState(()=>error='Enter username and password.');return;}
    setState(() { busy = true; error = ''; });
    try { final r=await http.post(Uri.parse('$apiBaseUrl/api/v1/auth/login'),headers:{'Content-Type':'application/json'},body:jsonEncode({'username':u.text.trim(),'password':p.text})).timeout(const Duration(seconds:10));
      if(r.statusCode!=200) {
        String detail = '';
        try {
          final body = jsonDecode(r.body);
          detail = body['detail']?.toString() ?? '';
        } catch (_) {}
        if (r.statusCode == 401) {
          throw Exception('Invalid username or password');
        }
        if (detail.isNotEmpty) {
          throw Exception('Server error ${r.statusCode}: $detail');
        }
        throw Exception('Server error ${r.statusCode}');
      }
      final d=jsonDecode(r.body);
      final sp=await SharedPreferences.getInstance();
      await sp.setString('access_token',d['access_token']);
      if(mounted)Navigator.of(context).pushReplacement(MaterialPageRoute(builder:(_)=>DashboardPage(token:d['access_token'])));
    } catch(e){
      if(mounted)setState(()=>error=e is TimeoutException
        ? 'Connection timed out. Check internet and try again.'
        : 'Login failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(body:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(28),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:430),child:Column(children:[const Icon(Icons.auto_graph,size:64,color:Colors.greenAccent),const SizedBox(height:18),const Text('LEONA PRO X EA',style:TextStyle(fontSize:25,fontWeight:FontWeight.bold,letterSpacing:2)),const SizedBox(height:30),TextField(controller:u,decoration:const InputDecoration(labelText:'Username',border:OutlineInputBorder())),const SizedBox(height:14),TextField(controller:p,obscureText:true,decoration:const InputDecoration(labelText:'Password',border:OutlineInputBorder())),if(error.isNotEmpty)Padding(padding:const EdgeInsets.only(top:12),child:Text(error,style:const TextStyle(color:Colors.redAccent))),const SizedBox(height:20),SizedBox(width:double.infinity,child:ElevatedButton(onPressed:busy?null:login,child:busy?const CircularProgressIndicator():const Text('SIGN IN')))])))));
}

class DashboardPage extends StatefulWidget {
  final String token;
  const DashboardPage({super.key, required this.token});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool robotActive = false;
  bool connected = false;
  bool loading = true;
  bool commandLoading = false;

  double balance = 0;
  double equity = 0;
  double profit = 0;
  double drawdown = 0;

  String connectionMessage = 'Connecting...';
  String lastAction = 'None';
  List<dynamic> devices = [];
  String? selectedDeviceId;
  String selectedBroker = 'Weltrade';
  String selectedSymbol = 'FX Vol 20';
  bool instrumentLoading = false;

  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    loadDevices();
    loadStatus();

    refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => loadStatus(),
    );
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  Map<String,String> get headers => {'Content-Type':'application/json','Authorization':'Bearer ${widget.token}'};

  Future<void> loadDevices() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/v1/devices'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      if (!mounted) return;
      setState(() {
        devices = data['items'] ?? [];
        if (selectedDeviceId == null && devices.isNotEmpty) {
          selectedDeviceId = devices.first['device_id']?.toString();
        }
      });
    } catch (_) {}
  }

  Future<void> loadStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/v1/ea/status${selectedDeviceId == null ? '' : '?device_id=$selectedDeviceId'}'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (!mounted) return;

        setState(() {
          connected = data['connected'] == true;
          loading = false;
          connectionMessage = connected ? 'MT5 EA online' : 'Waiting for MT5 EA';

          balance = _number(data['balance']);
          equity = _number(data['equity']);
          profit = _number(data['profit']);
          drawdown = _number(data['drawdown']);

          if (selectedDeviceId == null && data['device_id'] != null) {
            selectedDeviceId = data['device_id'].toString();
          }

          robotActive = data['ea_active'] == true;
          if (data['broker'] != null && data['broker'].toString().isNotEmpty) {
            selectedBroker = data['broker'].toString();
          }
          if (data['symbol'] != null && data['symbol'].toString().isNotEmpty) {
            selectedSymbol = data['symbol'].toString();
          }
        });
      } else {
        throw Exception('API returned ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        connected = false;
        loading = false;
        connectionMessage = 'Connection unavailable';
      });
    }
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> sendCommand(String command) async {
    if (commandLoading) return;
    if (selectedDeviceId == null) {
      showMessage('Register and select an MT5 device first.');
      return;
    }

    setState(() {
      commandLoading = true;
    });

    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/api/v1/ea/command'),
            headers: headers,
            body: jsonEncode({
              'command': command,
              'device_id': selectedDeviceId,
              'payload': {},
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (!mounted) return;

        setState(() {
          if (command == 'START_ROBOT') {
            lastAction = 'Start command queued for MT5 EA';
          } else if (command == 'STOP_ROBOT') {
            lastAction = 'Stop command queued for MT5 EA';
          } else if (command == 'CLOSE_ALL') {
            lastAction = 'Close-all command queued for MT5 EA';
          }
        });

        showMessage(connected ? 'Command sent to MT5 EA' : 'Command queued — MT5 EA is offline');
        await loadStatus();
      } else {
        throw Exception(
          'Command failed: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      if (!mounted) return;
      showMessage('Command failed. Check API connection.');
    } finally {
      if (mounted) {
        setState(() {
          commandLoading = false;
        });
      }
    }
  }

  static const Map<String, List<String>> syntheticSymbols = {
    'Weltrade': [
      'FX Vol 20', 'FX Vol 30', 'FX Vol 40', 'FX Vol 50', 'FX Vol 60',
      'FX Vol 70', 'FX Vol 80', 'FX Vol 90', 'FX Vol 99',
      'SFX Vol 20', 'SFX Vol 30', 'SFX Vol 40', 'SFX Vol 50',
      'SFX Vol 60', 'SFX Vol 70', 'SFX Vol 80', 'SFX Vol 90', 'SFX Vol 99',
    ],
    'Deriv': [
      'Volatility 10 Index', 'Volatility 25 Index', 'Volatility 50 Index',
      'Volatility 75 Index', 'Volatility 100 Index', 'Volatility 150 Index',
      'Volatility 250 Index',
    ],
  };

  Future<void> selectInstrument(String broker, String symbol) async {
    if (selectedDeviceId == null || instrumentLoading) {
      showMessage('Register and select an MT5 device first.');
      return;
    }

    setState(() {
      instrumentLoading = true;
      selectedBroker = broker;
      selectedSymbol = symbol;
    });

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/v1/ea/command'),
        headers: headers,
        body: jsonEncode({
          'command': 'SET_INSTRUMENT',
          'device_id': selectedDeviceId,
          'payload': {
            'broker': broker,
            'symbol': symbol,
          },
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        lastAction = 'Instrument switch queued: $broker • $symbol';
        showMessage('Switch queued — MT5 will move to $symbol');
        await loadStatus();
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (_) {
      showMessage('Could not queue instrument switch.');
    } finally {
      if (mounted) setState(() => instrumentLoading = false);
    }
  }

  Widget instrumentSelector() {
    final symbols = syntheticSymbols[selectedBroker] ?? const <String>[];
    final displayedSymbol = symbols.contains(selectedSymbol)
        ? selectedSymbol
        : (symbols.isNotEmpty ? symbols.first : '');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bolt, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text(
                  'SYNTHETIC MARKET',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose the broker and volatility index the EA should trade.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: selectedBroker,
              decoration: const InputDecoration(
                labelText: 'BROKER',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.account_balance),
              ),
              items: syntheticSymbols.keys.map((broker) {
                return DropdownMenuItem<String>(
                  value: broker,
                  child: Text(broker),
                );
              }).toList(),
              onChanged: instrumentLoading ? null : (broker) {
                if (broker == null) return;
                final first = syntheticSymbols[broker]!.first;
                setState(() {
                  selectedBroker = broker;
                  selectedSymbol = first;
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: displayedSymbol.isEmpty ? null : displayedSymbol,
              decoration: const InputDecoration(
                labelText: 'VOLATILITY INDEX',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.show_chart),
              ),
              items: symbols.map((symbol) {
                return DropdownMenuItem<String>(
                  value: symbol,
                  child: Text(symbol),
                );
              }).toList(),
              onChanged: instrumentLoading ? null : (symbol) {
                if (symbol != null) setState(() => selectedSymbol = symbol);
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: instrumentLoading
                    ? null
                    : () => selectInstrument(selectedBroker, selectedSymbol),
                icon: instrumentLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.swap_horiz),
                label: Text(
                  instrumentLoading ? 'SWITCHING...' : 'APPLY INSTRUMENT',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'MT5 must be logged into the selected broker and the exact symbol must be available in Market Watch.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> logout() async { final sp=await SharedPreferences.getInstance(); await sp.remove('access_token'); if(mounted)Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder:(_)=>const LoginPage()),(_)=>false); }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget metricCard(
    String title,
    String value, {
    IconData? icon,
  }) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 18,
                      color: Colors.greenAccent,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget actionButton(
    String text,
    VoidCallback onPressed,
    Color color,
  ) {
    return Expanded(
      child: ElevatedButton(
        onPressed: commandLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
        child: commandLoading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
            : Text(
                text,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F14),
        title: const Text(
          'LEONA PRO X EA',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        actions: [
          IconButton(onPressed: loadStatus, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadStatus,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: connected
                            ? Colors.greenAccent
                            : Colors.redAccent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MT5 CONNECTION',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            connectionMessage,
                            style: TextStyle(
                              color: connected
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (loading)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            if (devices.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<String>(
                    value: selectedDeviceId,
                    decoration: const InputDecoration(
                      labelText: 'ACTIVE MT5 DEVICE',
                      border: OutlineInputBorder(),
                    ),
                    items: devices.map<DropdownMenuItem<String>>((d) {
                      return DropdownMenuItem<String>(
                        value: d['device_id']?.toString(),
                        child: Text(
                          (d['device_name']?.toString() ?? 'MT5') +
                          ' • ' +
                          (d['status']?.toString() ?? 'UNKNOWN'),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) async {
                      setState(() => selectedDeviceId = value);
                      await loadStatus();
                    },
                  ),
                ),
              ),

            if (devices.isNotEmpty) const SizedBox(height: 16),

            instrumentSelector(),

            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TRADING ROBOT',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            robotActive ? 'RUNNING' : 'STOPPED',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: robotActive
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: robotActive,
                      activeColor: Colors.greenAccent,
                      onChanged: commandLoading
                          ? null
                          : (value) {
                              sendCommand(
                                value
                                    ? 'START_ROBOT'
                                    : 'STOP_ROBOT',
                              );
                            },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                metricCard(
                  'Balance',
                  balance.toStringAsFixed(2),
                  icon: Icons.account_balance_wallet,
                ),
                const SizedBox(width: 10),
                metricCard(
                  'Equity',
                  equity.toStringAsFixed(2),
                  icon: Icons.show_chart,
                ),
              ],
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                metricCard(
                  'P/L',
                  profit.toStringAsFixed(2),
                  icon: Icons.trending_up,
                ),
                const SizedBox(width: 10),
                metricCard(
                  'Drawdown',
                  '${drawdown.toStringAsFixed(2)}%',
                  icon: Icons.warning_amber,
                ),
              ],
            ),

            const SizedBox(height: 20),

            const Text(
              'QUICK ACTIONS',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white60,
              ),
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                actionButton(
                  'START',
                  () => sendCommand('START_ROBOT'),
                  Colors.greenAccent,
                ),
                const SizedBox(width: 10),
                actionButton(
                  'STOP',
                  () => sendCommand('STOP_ROBOT'),
                  Colors.orangeAccent,
                ),
              ],
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: commandLoading
                    ? null
                    : () => sendCommand('CLOSE_ALL'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 15,
                  ),
                ),
                child: const Text(
                  'CLOSE ALL POSITIONS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LAST ACTION',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      lastAction,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DeviceSetupPage(token: widget.token),
                  ),
                ).then((_) => loadDevices()),
                icon: const Icon(Icons.link),
                label: const Text('MT5 DEVICE SETUP & EA TOKEN'),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DeviceSettingsPage(token: widget.token),
                  ),
                ),
                icon: const Icon(Icons.settings),
                label: const Text('MT5 DEVICE & RISK SETTINGS'),
              ),
            ),

            const SizedBox(height: 30),

            Center(
              child: Text(
                'Leona Pro X EA • Weltrade + Deriv Synthetic Control',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
