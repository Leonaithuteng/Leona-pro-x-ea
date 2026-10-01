
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
      home: const EntryPage(),
    );
  }
}

class EntryPage extends StatefulWidget {
  const EntryPage({super.key});
  @override State<EntryPage> createState() => _EntryPageState();
}
class _EntryPageState extends State<EntryPage> {
  String? token;
  bool loading=true;
  @override void initState(){super.initState(); _restore();}
  Future<void> _restore() async {
    final p=await SharedPreferences.getInstance();
    if(!mounted)return;
    setState((){token=p.getString('session_token');loading=false;});
  }
  @override Widget build(BuildContext context){
    if(loading) return const Scaffold(body:Center(child:CircularProgressIndicator()));
    return token==null ? const LoginPage() : DashboardPage(token: token!);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override State<LoginPage> createState()=>_LoginPageState();
}
class _LoginPageState extends State<LoginPage>{
  final username=TextEditingController();
  final password=TextEditingController();
  bool busy=false;
  String error='';
  Future<void> login() async {
    setState((){busy=true;error='';});
    try{
      final r=await http.post(Uri.parse('$apiBaseUrl/api/v1/auth/login'),
        headers:{'Content-Type':'application/json'},
        body:jsonEncode({'username':username.text.trim(),'password':password.text}))
        .timeout(const Duration(seconds:15));
      if(r.statusCode!=200) throw Exception();
      final access=jsonDecode(r.body)['access_token']?.toString();
      if(access==null||access.isEmpty) throw Exception();
      final p=await SharedPreferences.getInstance();
      await p.setString('session_token',access);
      if(!mounted)return;
      Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>DashboardPage(token:access)));
    }catch(_){
      if(mounted)setState(()=>error='Login failed. Check your Leona Pro X account.');
    }finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context){
    return Scaffold(body:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Card(child:Padding(padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Icon(Icons.smart_toy,size:60,color:Colors.greenAccent),
      const SizedBox(height:12), const Text('LEONA PRO X EA',textAlign:TextAlign.center,style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
      const SizedBox(height:24), TextField(controller:username,decoration:const InputDecoration(labelText:'Username')),
      const SizedBox(height:12), TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'Password')),
      if(error.isNotEmpty) Padding(padding:const EdgeInsets.only(top:12),child:Text(error,style:const TextStyle(color:Colors.redAccent))),
      const SizedBox(height:20), FilledButton(onPressed:busy?null:login,child:busy?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Text('SIGN IN'))
    ]))))));
  }
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

  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
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

  Map<String,String> authHeaders()=>{'Authorization':'Bearer ${widget.token}','Content-Type':'application/json'};

  Future<void> loadStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/v1/ea/status'),
        headers: authHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (!mounted) return;

        setState(() {
          connected = true;
          loading = false;
          connectionMessage = 'Connected';

          balance = _number(data['balance']);
          equity = _number(data['equity']);
          profit = _number(data['profit']);
          drawdown = _number(data['drawdown']);

          robotActive =
              data['ea_active'] == true ||
              data['robot_active'] == true ||
              data['active'] == true;
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

    setState(() {
      commandLoading = true;
    });

    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/api/v1/ea/command'),
            headers: authHeaders(),
            body: jsonEncode({
              'command': command,
              'payload': {},
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (!mounted) return;

        setState(() {
          if (command == 'START_ROBOT') {
            robotActive = true;
            lastAction = 'Robot start command sent';
          } else if (command == 'STOP_ROBOT') {
            robotActive = false;
            lastAction = 'Robot stop command sent';
          } else if (command == 'CLOSE_ALL') {
            lastAction = 'Close-all command sent';
          }
        });

        showMessage('Command sent successfully');
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

  Future<void> logout() async {
    final p=await SharedPreferences.getInstance();
    await p.remove('session_token');
    if(!mounted)return;
    Navigator.pushAndRemoveUntil(context,MaterialPageRoute(builder:(_)=>const LoginPage()),(_)=>false);
  }

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

            Card(
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RISK SETTINGS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text('Risk per trade: 1.0%'),
                    Text('Stop Loss: 150 points'),
                    Text('Take Profit: 250 points'),
                    Text('Max Daily Loss: 3.0%'),
                    Text('Max Drawdown: 10.0%'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            Center(
              child: Text(
                'Leona Pro X EA • API: Connected Architecture',
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
