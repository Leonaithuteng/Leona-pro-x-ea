import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String apiBaseUrl = 'https://leona-pro-x-api.onrender.com';

void main() => runApp(const LeonaProXApp());

class LeonaProXApp extends StatelessWidget {
  const LeonaProXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Leona Pro X EA',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF080C11),
        colorScheme: const ColorScheme.dark(
          primary: Colors.greenAccent,
          secondary: Colors.greenAccent,
        ),
        cardColor: const Color(0xFF121922),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF0D131B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const EntryPage(),
    );
  }
}

class EntryPage extends StatefulWidget {
  const EntryPage({super.key});
  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  String? token;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      token = p.getString('session_token');
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return token == null
        ? const LoginPage()
        : DashboardPage(token: token!);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String error = '';

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    setState(() {
      busy = true;
      error = '';
    });

    try {
      final r = await http
          .post(
            Uri.parse('$apiBaseUrl/api/v1/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username.text.trim(),
              'password': password.text,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (r.statusCode != 200) {
        throw Exception('HTTP ${r.statusCode}');
      }

      final access = jsonDecode(r.body)['access_token']?.toString();
      if (access == null || access.isEmpty) {
        throw Exception('Missing access token');
      }

      final p = await SharedPreferences.getInstance();
      await p.setString('session_token', access);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => DashboardPage(token: access)),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Login failed. Check your Leona Pro X account.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.smart_toy,
                      size: 64,
                      color: Colors.greenAccent,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'LEONA PRO X EA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Autonomous synthetic scalping control',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: username,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    if (error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: busy ? null : login,
                      child: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('SIGN IN'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  final String token;
  const DashboardPage({super.key, required this.token});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool connected = false;
  bool robotActive = false;
  bool loading = true;
  bool commandLoading = false;

  double balance = 0;
  double equity = 0;
  double profit = 0;
  double drawdown = 0;
  double openProfit = 0;
  double atr = 0;
  double spread = 0;
  int openPositions = 0;
  int signalScore = 0;

  String connectionMessage = 'Connecting...';
  String lastAction = 'No commands sent yet';
  String deviceId = '';
  String broker = 'Weltrade';
  String account = '';
  String symbol = 'FX Vol 20';

  String sizingMode = 'RISK';
  double lotSize = 0.01;
  double riskPercent = 1.0;
  int slPoints = 150;
  int tpPoints = 250;
  double maxDailyLoss = 3.0;
  double maxDrawdown = 10.0;

  List<Map<String, dynamic>> activity = [];
  Timer? refreshTimer;

  Map<String, String> authHeaders() => {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _restoreLocalSymbol();
    loadEverything();
    refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => loadEverything(),
    );
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _restoreLocalSymbol() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('selected_symbol');
    final savedBroker = p.getString('selected_broker');
    if (!mounted) return;
    setState(() {
      if (saved != null && saved.isNotEmpty) symbol = saved;
      if (savedBroker != null && savedBroker.isNotEmpty) broker = savedBroker;
    });
  }

  Future<void> loadEverything() async {
    await Future.wait([
      loadStatus(),
      loadDevices(),
      loadActivity(),
    ]);
  }

  Future<void> loadStatus() async {
    try {
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/api/v1/ea/status'),
            headers: authHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      if (!mounted) return;

      setState(() {
        connected = data['connected'] == true;
        loading = false;
        connectionMessage = connected
            ? 'MT5 bridge online'
            : 'Waiting for MT5 heartbeat';
        balance = _number(data['balance']);
        equity = _number(data['equity']);
        profit = _number(data['profit']);
        drawdown = _number(data['drawdown']);
        openProfit = _number(data['open_profit']);
        atr = _number(data['atr']);
        spread = _number(data['spread']);
        openPositions = _intNumber(data['open_positions']);
        signalScore = _intNumber(data['signal_score']);
        if ((data['symbol'] ?? '').toString().isNotEmpty) {
          symbol = data['symbol'].toString();
        }
        robotActive = data['ea_active'] == true;
        if ((data['device_id'] ?? '').toString().isNotEmpty) {
          deviceId = data['device_id'].toString();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        connected = false;
        loading = false;
        connectionMessage = 'Connection unavailable';
      });
    }
  }

  Future<void> loadDevices() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/v1/devices'),
        headers: authHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body);
      final items = (body['items'] as List?) ?? const [];
      if (items.isEmpty || !mounted) return;

      final d = Map<String, dynamic>.from(items.first as Map);
      setState(() {
        deviceId = (d['device_id'] ?? deviceId).toString();
        broker = (d['broker'] ?? broker).toString();
        account = (d['account'] ?? '').toString();
        sizingMode = (d['sizing_mode'] ?? sizingMode).toString();
        lotSize = _number(d['lot_size'], lotSize);
        riskPercent = _number(d['risk_percent'], riskPercent);
        slPoints = _intNumber(d['sl_points'], slPoints);
        tpPoints = _intNumber(d['tp_points'], tpPoints);
        maxDailyLoss = _number(d['max_daily_loss'], maxDailyLoss);
        maxDrawdown = _number(d['max_drawdown'], maxDrawdown);
      });
    } catch (_) {}
  }

  Future<void> loadActivity() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/v1/activity'),
        headers: authHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body);
      final items = (body['items'] as List?) ?? const [];
      if (!mounted) return;

      setState(() {
        activity = items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .take(20)
            .toList();
      });
    } catch (_) {}
  }

  double _number(dynamic value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  int _intNumber(dynamic value, [int fallback = 0]) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  Future<void> sendCommand(
    String command, {
    Map<String, dynamic> payload = const {},
    String successMessage = 'Command queued',
  }) async {
    if (commandLoading) return;

    setState(() => commandLoading = true);

    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/api/v1/ea/command'),
            headers: authHeaders(),
            body: jsonEncode({
              'command': command,
              'device_id': deviceId.isEmpty ? null : deviceId,
              'payload': payload,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }

      if (!mounted) return;
      setState(() {
        if (command == 'START_ROBOT') robotActive = true;
        if (command == 'STOP_ROBOT') robotActive = false;
        lastAction = successMessage;
      });

      showMessage(successMessage);
      await loadEverything();
    } catch (_) {
      if (mounted) showMessage('Command failed. Check the MT5 bridge.');
    } finally {
      if (mounted) setState(() => commandLoading = false);
    }
  }

  Future<void> updateSettings() async {
    try {
      final response = await http.put(
        Uri.parse('$apiBaseUrl/api/v1/devices/$deviceId/settings'),
        headers: authHeaders(),
        body: jsonEncode({
          'sizing_mode': sizingMode,
          'lot_size': lotSize,
          'risk_percent': riskPercent,
          'sl_points': slPoints,
          'tp_points': tpPoints,
          'max_daily_loss': maxDailyLoss,
          'max_drawdown': maxDrawdown,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }

      if (mounted) {
        setState(() => lastAction = 'Trading settings update queued');
        showMessage('Trading settings queued for the EA');
      }
      await loadEverything();
    } catch (_) {
      if (mounted) showMessage('Could not update trading settings');
    }
  }

  Future<void> selectInstrument() async {
    final symbolController = TextEditingController(text: symbol);
    String selectedBroker = broker.toLowerCase() == 'deriv'
        ? 'Deriv'
        : 'Weltrade';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Synthetic instrument'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedBroker,
                decoration: const InputDecoration(labelText: 'Broker'),
                items: const [
                  DropdownMenuItem(value: 'Weltrade', child: Text('Weltrade')),
                  DropdownMenuItem(value: 'Deriv', child: Text('Deriv')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setDialogState(() => selectedBroker = v);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: symbolController,
                decoration: const InputDecoration(
                  labelText: 'MT5 synthetic symbol',
                  hintText: 'Example: FX Vol 20',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'broker': selectedBroker,
                'symbol': symbolController.text.trim(),
              }),
              child: const Text('APPLY'),
            ),
          ],
        ),
      ),
    );

    symbolController.dispose();

    if (result == null || result['symbol']!.isEmpty) return;

    final p = await SharedPreferences.getInstance();
    await p.setString('selected_symbol', result['symbol']!);
    await p.setString('selected_broker', result['broker']!);

    if (!mounted) return;
    setState(() {
      symbol = result['symbol']!;
      broker = result['broker']!;
    });

    await sendCommand(
      'SET_INSTRUMENT',
      payload: {
        'broker': result['broker'],
        'symbol': result['symbol'],
      },
      successMessage: 'Instrument change queued: ${result['symbol']}',
    );
  }

  Future<void> editSettings() async {
    final lot = TextEditingController(text: lotSize.toString());
    final risk = TextEditingController(text: riskPercent.toString());
    final sl = TextEditingController(text: slPoints.toString());
    final tp = TextEditingController(text: tpPoints.toString());
    final daily = TextEditingController(text: maxDailyLoss.toString());
    final dd = TextEditingController(text: maxDrawdown.toString());

    String mode = sizingMode;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('EA trading settings'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: mode,
                  decoration: const InputDecoration(labelText: 'Sizing mode'),
                  items: const [
                    DropdownMenuItem(value: 'RISK', child: Text('Risk %')),
                    DropdownMenuItem(value: 'FIXED_LOT', child: Text('Fixed lot')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => mode = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: lot,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Lot size'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: risk,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Risk %'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: sl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Stop loss points'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Take profit points'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: daily,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Daily loss %'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: dd,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Max drawdown %'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'mode': mode,
                'lot': lot.text,
                'risk': risk.text,
                'sl': sl.text,
                'tp': tp.text,
                'daily': daily.text,
                'dd': dd.text,
              }),
              child: const Text('SAVE'),
            ),
          ],
        ),
      ),
    );

    lot.dispose();
    risk.dispose();
    sl.dispose();
    tp.dispose();
    daily.dispose();
    dd.dispose();

    if (result == null) return;

    setState(() {
      sizingMode = result['mode']!;
      lotSize = double.tryParse(result['lot']!) ?? lotSize;
      riskPercent = double.tryParse(result['risk']!) ?? riskPercent;
      slPoints = int.tryParse(result['sl']!) ?? slPoints;
      tpPoints = int.tryParse(result['tp']!) ?? tpPoints;
      maxDailyLoss = double.tryParse(result['daily']!) ?? maxDailyLoss;
      maxDrawdown = double.tryParse(result['dd']!) ?? maxDrawdown;
    });

    await updateSettings();
  }

  Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('session_token');
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Widget statusDot(bool ok) => Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ok ? Colors.greenAccent : Colors.redAccent,
          boxShadow: [
            BoxShadow(
              color: (ok ? Colors.greenAccent : Colors.redAccent)
                  .withOpacity(0.35),
              blurRadius: 8,
            ),
          ],
        ),
      );

  Widget metricCard(String title, String value, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 19, color: Colors.greenAccent),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 5),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget actionButton(String label, IconData icon, VoidCallback action, Color color) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: commandLoading ? null : action,
        icon: Icon(icon, size: 19),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engineOnline = connected && robotActive;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF080C11),
        title: const Text(
          'LEONA PRO X',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        actions: [
          IconButton(
            onPressed: loadEverything,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadEverything,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(17),
                child: Row(
                  children: [
                    statusDot(connected),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MT5 EXECUTION BRIDGE',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.7,
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
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(17),
                child: Row(
                  children: [
                    Icon(
                      engineOnline ? Icons.bolt : Icons.pause_circle_outline,
                      size: 38,
                      color: engineOnline
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AUTONOMOUS EA ENGINE',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            engineOnline
                                ? 'RUNNING — automatic execution enabled'
                                : robotActive
                                    ? 'EA active — bridge reconnecting'
                                    : 'STOPPED',
                            style: TextStyle(
                              color: engineOnline
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'The phone is the control centre; the MT5 execution engine trades automatically.',
                            style: TextStyle(
                              color: Colors.white45,
                              fontSize: 11,
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
                          : (value) => sendCommand(
                                value ? 'START_ROBOT' : 'STOP_ROBOT',
                                successMessage: value
                                    ? 'Autonomous EA start queued'
                                    : 'EA stop queued',
                              ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: selectInstrument,
                child: Padding(
                  padding: const EdgeInsets.all(17),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.candlestick_chart,
                        color: Colors.greenAccent,
                        size: 30,
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ACTIVE MARKET',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              symbol,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              broker,
                              style: const TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                metricCard('Balance', balance.toStringAsFixed(2), Icons.account_balance_wallet),
                const SizedBox(width: 8),
                metricCard('Equity', equity.toStringAsFixed(2), Icons.show_chart),
              ],
            ),
            Row(
              children: [
                metricCard('P/L', profit.toStringAsFixed(2), Icons.trending_up),
                const SizedBox(width: 8),
                metricCard('Drawdown', '${drawdown.toStringAsFixed(2)}%', Icons.warning_amber),
              ],
            ),


            const SizedBox(height: 8),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LIVE MARKET ENGINE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _telemetry('OPEN TRADES', openPositions.toString(), Icons.layers),
                        ),
                        Expanded(
                          child: _telemetry('OPEN P/L', openProfit.toStringAsFixed(2), Icons.account_balance),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _telemetry('AI SCORE', signalScore.toString(), Icons.psychology),
                        ),
                        Expanded(
                          child: _telemetry('SPREAD', spread.toStringAsFixed(1), Icons.swap_horiz),
                        ),
                        Expanded(
                          child: _telemetry('ATR', atr.toStringAsFixed(2), Icons.show_chart),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                actionButton(
                  'START',
                  Icons.play_arrow,
                  () => sendCommand(
                    'START_ROBOT',
                    successMessage: 'Autonomous EA start queued',
                  ),
                  Colors.greenAccent,
                ),
                const SizedBox(width: 8),
                actionButton(
                  'STOP',
                  Icons.stop,
                  () => sendCommand(
                    'STOP_ROBOT',
                    successMessage: 'EA stop queued',
                  ),
                  Colors.orangeAccent,
                ),
              ],
            ),

            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: commandLoading
                    ? null
                    : () => sendCommand(
                          'CLOSE_ALL',
                          successMessage: 'Close-all command queued',
                        ),
                icon: const Icon(Icons.close),
                label: const Text('CLOSE ALL POSITIONS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'EA CONFIGURATION',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: editSettings,
                          icon: const Icon(Icons.edit, size: 17),
                          label: const Text('EDIT'),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white10),
                    _settingRow('Sizing', sizingMode == 'RISK' ? 'Risk %' : 'Fixed lot'),
                    _settingRow('Lot size', lotSize.toStringAsFixed(3)),
                    _settingRow('Risk per trade', '${riskPercent.toStringAsFixed(2)}%'),
                    _settingRow('SL', '$slPoints points'),
                    _settingRow('TP', '$tpPoints points'),
                    _settingRow('Daily loss', '${maxDailyLoss.toStringAsFixed(2)}%'),
                    _settingRow('Max drawdown', '${maxDrawdown.toStringAsFixed(2)}%'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ENGINE ACTIVITY',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (activity.isEmpty)
                      const Text(
                        'No recent activity recorded.',
                        style: TextStyle(color: Colors.white45),
                      )
                    else
                      ...activity.take(8).map(
                            (item) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                _activityIcon(item['type']?.toString()),
                                size: 20,
                                color: _activityColor(item['status']?.toString()),
                              ),
                              title: Text(
                                item['message']?.toString() ??
                                    item['type']?.toString() ??
                                    'EA event',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                item['status']?.toString() ?? '',
                                style: const TextStyle(color: Colors.white38),
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(17),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.greenAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Account: ${account.isEmpty ? 'MT5 account connected' : account}\nDevice: ${deviceId.isEmpty ? 'Waiting for device' : deviceId}',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            Center(
              child: Text(
                'Leona Pro X EA • Autonomous Mobile Control',
                style: const TextStyle(
                  color: Colors.white30,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _telemetry(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: Colors.greenAccent),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white45, fontSize: 10)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
      ],
    );
  }

  Widget _settingRow(String name, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(name, style: const TextStyle(color: Colors.white60))),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  IconData _activityIcon(String? type) {
    final t = (type ?? '').toUpperCase();
    if (t.contains('COMMAND')) return Icons.bolt;
    if (t.contains('RISK')) return Icons.tune;
    return Icons.circle_outlined;
  }

  Color _activityColor(String? status) {
    final s = (status ?? '').toUpperCase();
    if (s.contains('SUCCESS') || s.contains('DONE') || s.contains('EXECUTED')) {
      return Colors.greenAccent;
    }
    if (s.contains('FAIL') || s.contains('ERROR') || s.contains('REJECT')) {
      return Colors.redAccent;
    }
    return Colors.orangeAccent;
  }
}
