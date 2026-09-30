import 'package:flutter/material.dart';

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
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C853),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF080B10),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool robotActive = false;
  int selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'LEONA PRO X EA',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
      ),
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) {
          setState(() => selectedTab = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Trades',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (selectedTab == 1) {
      return _buildTrades();
    }

    if (selectedTab == 2) {
      return _buildSettings();
    }

    return _buildDashboard();
  }

  Widget _buildDashboard() {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        setState(() {});
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusCard(),
          const SizedBox(height: 14),
          _accountCard(),
          const SizedBox(height: 14),
          _riskCard(),
          const SizedBox(height: 14),
          _quickActions(),
          const SizedBox(height: 14),
          _mt5Card(),
        ],
      ),
    );
  }

  Widget _statusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: robotActive
                  ? Colors.green.withOpacity(.18)
                  : Colors.red.withOpacity(.18),
              child: Icon(
                robotActive ? Icons.smart_toy : Icons.smart_toy_outlined,
                color: robotActive ? Colors.greenAccent : Colors.redAccent,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Trading Robot',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    robotActive ? 'ACTIVE' : 'STOPPED',
                    style: TextStyle(
                      color: robotActive
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: robotActive,
              onChanged: (value) {
                setState(() => robotActive = value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ACCOUNT',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'MT5 Connection Pending',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _metric('Balance', '--'),
                _metric('Equity', '--'),
                _metric('P/L', '--'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String title, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _riskCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'RISK MANAGEMENT',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 15),
            _settingRow('Risk per Trade', '1.0%'),
            _settingRow('Stop Loss', '150 points'),
            _settingRow('Take Profit', '250 points'),
            _settingRow('Max Daily Loss', '3.0%'),
            _settingRow('Max Drawdown', '10.0%'),
          ],
        ),
      ),
    );
  }

  Widget _settingRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _quickActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'QUICK ACTIONS',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() => robotActive = true);
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('START'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() => robotActive = false);
                    },
                    icon: const Icon(Icons.stop),
                    label: const Text('STOP'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.close),
                label: const Text('CLOSE ALL POSITIONS'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mt5Card() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.link),
        title: const Text('MT5 Bridge'),
        subtitle: const Text('Waiting for EA connection'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.orange.withOpacity(.15),
          ),
          child: const Text(
            'OFFLINE',
            style: TextStyle(
              color: Colors.orangeAccent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrades() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'OPEN POSITIONS',
          style: TextStyle(
            color: Colors.white60,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('No live positions'),
            subtitle: const Text('MT5 connection required'),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'TRADE HISTORY',
          style: TextStyle(
            color: Colors.white60,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.history),
            title: const Text('No trade history'),
            subtitle: const Text('Waiting for MT5 data'),
          ),
        ),
      ],
    );
  }

  Widget _buildSettings() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'EA SETTINGS',
          style: TextStyle(
            color: Colors.white60,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              _settingTile('Lot Size', '0.01'),
              _settingTile('Risk Percent', '1.0%'),
              _settingTile('Max Spread', '30 points'),
              _settingTile('Stop Loss', '150 points'),
              _settingTile('Take Profit', '250 points'),
              _settingTile('Cooldown', '20 seconds'),
              _settingTile('Max Trades/Hour', '100'),
              _settingTile('Trailing Stop', 'Enabled'),
              _settingTile('Break Even', 'Enabled'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingTile(String title, String value) {
    return ListTile(
      title: Text(title),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}
