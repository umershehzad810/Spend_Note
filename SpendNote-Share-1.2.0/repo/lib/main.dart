import 'dart:math';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'store.dart';
import 'security.dart';
import 'drive_setup.dart';
import 'errors.dart';
import 'mobile_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  await store.open();
  runApp(SpendNote(store));
}

const ink = Color(0xFF183C36), green = Color(0xFF26755D);
const colors = [
  Color(0xFF26755D),
  Color(0xFFE8AB65),
  Color(0xFF829BE0),
  Color(0xFFCE82A5),
  Color(0xFF62B8BC),
  Color(0xFF9AA178),
];
const icons = [
  Icons.restaurant_rounded,
  Icons.directions_bus_rounded,
  Icons.receipt_long_rounded,
  Icons.shopping_bag_rounded,
  Icons.favorite_rounded,
  Icons.category_rounded,
];

class SpendNote extends StatefulWidget {
  const SpendNote(this.store, {super.key});
  final Store store;
  @override
  State<SpendNote> createState() => _SpendNoteState();
}

class _SpendNoteState extends State<SpendNote> with WidgetsBindingObserver {
  final security = Security();
  late final Backups cloud = Backups(widget.store, security);
  bool locked = true, ready = false;
  String? startupError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    cloud.addListener(cloudChanged);
    initialize();
  }

  void cloudChanged() {
    if (mounted) setState(() {});
  }

  Future<void> initialize() async {
    if (mounted) setState(() => startupError = null);
    try {
      await cloud.initialize();
      final v = await security.hasPin();
      if (mounted) {
        setState(() {
          locked = v;
          ready = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => startupError =
              'Could not open secure settings. Unlock your device and try again.',
        );
      }
    }
  }

  @override
  void dispose() {
    cloud.removeListener(cloudChanged);
    cloud.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) cloud.schedule();
    if (state == AppLifecycleState.paused) {
      security.hasPin().then((v) {
        if (mounted && v) setState(() => locked = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (_, _) => MaterialApp(
      title: 'SpendNote',
      debugShowCheckedModeBanner: false,
      themeMode: widget.store.settings['dark'] == 'true'
          ? ThemeMode.dark
          : ThemeMode.light,
      builder: (context, child) =>
          PhoneViewport(child: child ?? const SizedBox()),
      theme: spendNoteTheme(),
      darkTheme: spendNoteTheme(dark: true),
      home: startupError != null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(startupError!),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: initialize,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : !ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : locked
          ? LockScreen(security, () => setState(() => locked = false))
          : !cloud.connected || !cloud.configured
          ? DriveSetup(cloud)
          : widget.store.settings['onboarded'] != 'true'
          ? Setup(widget.store)
          : Home(
              widget.store,
              security,
              () => setState(() => locked = true),
              cloud: cloud,
            ),
    ),
  );
}

class LockScreen extends StatefulWidget {
  const LockScreen(this.security, this.unlock, {super.key});
  final Security security;
  final VoidCallback unlock;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final pin = TextEditingController();
  String? error;
  int attempts = 0;
  DateTime? until;
  @override
  void dispose() {
    pin.dispose();
    super.dispose();
  }

  Future<void> verify() async {
    if (until != null && DateTime.now().isBefore(until!)) {
      setState(() => error = 'Please wait 30 seconds before trying again.');
      return;
    }
    if (await widget.security.verify(pin.text)) {
      widget.unlock();
    } else {
      attempts++;
      if (attempts % 5 == 0) {
        until = DateTime.now().add(const Duration(seconds: 30));
      }
      setState(() => error = 'Incorrect PIN');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SizedBox(
        width: 340,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 52, color: green),
              const SizedBox(height: 24),
              const Text(
                'Your money. Your privacy.',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'PIN', errorText: error),
                onSubmitted: (_) => verify(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: verify,
                child: const Text('Unlock SpendNote'),
              ),
              TextButton.icon(
                onPressed: () async {
                  try {
                    if (await LocalAuthentication().authenticate(
                          localizedReason: 'Unlock your financial records',
                          options: const AuthenticationOptions(
                            biometricOnly: true,
                          ),
                        ) &&
                        mounted) {
                      widget.unlock();
                    }
                  } catch (_) {
                    setState(
                      () => error = 'Biometrics unavailable. Use your PIN.',
                    );
                  }
                },
                icon: const Icon(Icons.fingerprint),
                label: const Text('Use biometrics'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class Setup extends StatefulWidget {
  const Setup(this.store, {super.key});
  final Store store;
  @override
  State<Setup> createState() => _SetupState();
}

class _SetupState extends State<Setup> {
  final name = TextEditingController(),
      account = TextEditingController(text: 'Cash'),
      opening = TextEditingController(text: '0');
  String currency = 'PKR', error = '';
  bool saving = false;
  @override
  void dispose() {
    name.dispose();
    account.dispose();
    opening.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: SizedBox(
          width: 430,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.spa_rounded, color: green, size: 52),
              const SizedBox(height: 24),
              const Text(
                'A little clarity.\nA lot more possibility.',
                style: TextStyle(
                  fontSize: 38,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Welcome to SpendNote. Track your money, build better habits, and make room for what matters. All offline.',
              ),
              const SizedBox(height: 28),
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'What should we call you?',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: currency,
                decoration: const InputDecoration(labelText: 'Currency'),
                items: ['PKR', 'USD', 'EUR', 'GBP', 'AED', 'INR']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => currency = v!,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: account,
                decoration: const InputDecoration(
                  labelText: 'Your first account',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: opening,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Opening balance'),
              ),
              if (error.isNotEmpty)
                Text(error, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setState(() {
                            saving = true;
                            error = '';
                          });
                          try {
                            if (name.text.trim().isEmpty ||
                                account.text.trim().isEmpty) {
                              throw const FormatException(
                                'Please enter your name and account name.',
                              );
                            }
                            await widget.store.setup(
                              name.text.trim(),
                              currency,
                              account.text.trim(),
                              money(opening.text),
                            );
                          } catch (e) {
                            if (mounted) {
                              setState(() => error = friendlyError(e));
                            }
                          } finally {
                            if (mounted) setState(() => saving = false);
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      saving ? 'Setting up...' : 'Let’s get started  →',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Private by default · Encrypted Drive backup',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class Home extends StatefulWidget {
  const Home(this.s, this.security, this.lock, {super.key, this.cloud});
  final Backups? cloud;
  final Store s;
  final Security security;
  final VoidCallback lock;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int page = 0;
  DateTime period = DateTime(DateTime.now().year, DateTime.now().month);
  String search = '', typeFilter = 'all';
  final searchController = TextEditingController();
  int? accountFilter;
  DateTimeRange? range;
  late final Backups backup = widget.cloud ?? Backups(s, widget.security);
  @override
  void dispose() {
    scroll.dispose();
    searchController.dispose();
    if (widget.cloud == null) backup.dispose();
    super.dispose();
  }

  Store get s => widget.s;
  String get month => DateFormat('yyyy-MM').format(period);
  String cash(int value) =>
      '${s.settings['currency'] ?? 'PKR'} ${NumberFormat('#,##0.00').format(value / 100)}';
  Future<void> act(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<bool> confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;
  Future<String?> prompt(String title, {bool secret = false}) async {
    final c = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, obscureText: secret, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    // Dialog exit animation may still reference its controller.
    return value;
  }

  Widget title(String eyebrow, String heading, [Widget? action]) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: const TextStyle(
                  letterSpacing: .5,
                  fontSize: 13,
                  color: green,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                heading,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        ?action,
      ],
    ),
  );
  Widget panel(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
  Widget heading(String name, [VoidCallback? add]) => Row(
    children: [
      Expanded(
        child: Text(
          name,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      if (add != null)
        IconButton(onPressed: add, icon: const Icon(Icons.add_circle_outline)),
    ],
  );
  Widget empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.grey),
      ),
    ),
  );
  Widget monthPicker() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Previous month',
        onPressed: () =>
            setState(() => period = DateTime(period.year, period.month - 1)),
        icon: const Icon(Icons.chevron_left),
      ),
      Text(
        DateFormat('MMM yyyy').format(period),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      IconButton(
        tooltip: 'Next month',
        onPressed: () =>
            setState(() => period = DateTime(period.year, period.month + 1)),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
  final scroll = ScrollController();
  void go(int destination) {
    if (scroll.hasClients) scroll.jumpTo(0);
    setState(() => page = destination);
  }

  @override
  Widget build(BuildContext context) {
    final views = [
      dashboard,
      history,
      accountsPage,
      planning,
      reports,
      settings,
      morePage,
    ];
    final subpage = page == 2 || page == 4 || page == 5;
    final navIndex = page == 0
        ? 0
        : page == 1
        ? 1
        : page == 3
        ? 2
        : 3;
    return PopScope(
      canPop: page == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) go(subpage ? 6 : 0);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: subpage
              ? IconButton(
                  tooltip: 'Back',
                  onPressed: () => go(6),
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : null,
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.spa_rounded, color: green, size: 25),
              SizedBox(width: 8),
              Text(
                'SpendNote',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.6,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Settings',
              onPressed: () => go(5),
              icon: const Icon(Icons.tune_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                child: views[page](),
              ),
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: navIndex,
          onDestinationSelected: (i) => go([0, 1, 3, 6][i]),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Activity',
            ),
            NavigationDestination(
              icon: Icon(Icons.flag_outlined),
              selectedIcon: Icon(Icons.flag_rounded),
              label: 'Plan',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'More',
            ),
          ],
        ),
        floatingActionButton: page == 1
            ? FloatingActionButton(
                tooltip: 'Add transaction',
                onPressed: () => editEntry(),
                child: const Icon(Icons.add_rounded, size: 30),
              )
            : null,
      ),
    );
  }

  Widget morePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title('Your personal finance space', 'More'),
      panel(
        Column(
          children: [
            menuRow(
              Icons.account_balance_wallet_outlined,
              'Accounts',
              'Cash, banks & wallets',
              2,
            ),
            const Divider(height: 1),
            menuRow(
              Icons.bar_chart_rounded,
              'Reports',
              'Trends & spending insights',
              4,
            ),
            const Divider(height: 1),
            menuRow(
              Icons.settings_outlined,
              'Settings',
              'Profile, security & Google Drive',
              5,
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: green.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_done_outlined, color: green, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your records, protected',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(backup.status, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
  Widget menuRow(
    IconData icon,
    String name,
    String subtitle,
    int destination,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 12),
    leading: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: green.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: green),
    ),
    title: Text(
      name,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(subtitle, style: const TextStyle(fontSize: 13)),
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => go(destination),
  );

  Widget dashboard() {
    final income = s.total('income', month),
        expense = s.total('expense', month);
    final balance = s.accounts
        .where((a) => a['archived'] == 0)
        .fold<int>(0, (sum, a) => sum + s.balance(a['id'] as int));
    final budgets = s.budgets.where((b) => b['month'] == month).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title('Let’s make today count', 'Hi, ${s.settings['name']}'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF193F35), Color(0xFF21765A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Expanded(
                    child: Text(
                      'Available balance',
                      style: TextStyle(fontSize: 15, color: Color(0xFFD0E8DB)),
                    ),
                  ),
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Color(0xFFD0E8DB),
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  cash(balance),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Icon(Icons.circle, size: 7, color: Color(0xFFAAE8BC)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${s.accounts.where((a) => a['archived'] == 0).length} active accounts',
                      style: const TextStyle(
                        color: Color(0xFFD0E8DB),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => go(2),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Text(
                            'View wallets',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(
              child: Text(
                'This month',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            monthPicker(),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: summaryCard(
                'Income',
                income,
                Icons.south_west_rounded,
                green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: summaryCard(
                'Spent',
                expense,
                Icons.north_east_rounded,
                const Color(0xFFCA744E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Net cash flow: ${cash(income - expense)}',
            style: const TextStyle(fontSize: 13, color: green),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            quickAction(Icons.remove_rounded, 'Expense', 'expense'),
            const SizedBox(width: 10),
            quickAction(Icons.add_rounded, 'Income', 'income'),
            const SizedBox(width: 10),
            quickAction(Icons.swap_horiz_rounded, 'Transfer', 'transfer'),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Recent activity',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(onPressed: () => go(1), child: const Text('See all')),
          ],
        ),
        const SizedBox(height: 8),
        panel(
          Column(
            children: [
              if (s.entries.isEmpty)
                empty(
                  'Add your first transaction.\nA clearer picture starts here.',
                ),
              ...s.entries.take(4).map(entryTile),
            ],
          ),
        ),
        const SizedBox(height: 24),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Monthly budgets', () => editBudget()),
              if (budgets.isEmpty)
                empty('Set a limit for the things you spend on.'),
              ...budgets.take(3).map(budgetTile),
            ],
          ),
        ),
        const SizedBox(height: 20),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Spending breakdown'),
              const SizedBox(height: 16),
              spendingChart(),
            ],
          ),
        ),
      ],
    );
  }

  Widget quickAction(IconData icon, String label, String type) => Expanded(
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => editEntry(null, type),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: green, size: 26),
              const SizedBox(height: 7),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget summaryCard(String label, int value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 19),
                const SizedBox(width: 7),
                Text(label, style: const TextStyle(fontSize: 14)),
              ],
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                cash(value),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
  Widget metric(String name, int amount, {bool light = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        name,
        style: TextStyle(
          fontSize: 13,
          color: light ? Colors.white70 : Colors.grey,
        ),
      ),
      const SizedBox(height: 8),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          cash(amount),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: light ? Colors.white : null,
          ),
        ),
      ),
    ],
  );

  Widget entryTile(Map<String, Object?> e) {
    final transfer = e['type'] == 'transfer', income = e['type'] == 'income';
    final category = s.categories
        .where((c) => c['id'] == e['category_id'])
        .firstOrNull;
    final color = transfer
        ? colors[2]
        : income
        ? green
        : colors[(category?['color'] as int? ?? 1) % colors.length];
    return InkWell(
      onTap: () => editEntry(e),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                transfer
                    ? Icons.swap_horiz_rounded
                    : income
                    ? Icons.south_west_rounded
                    : icons[(category?['icon'] as int? ?? 0) % icons.length],
                color: color,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (e['note'] as String).isNotEmpty
                        ? e['note'] as String
                        : s.categoryName(e['category_id']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    transfer
                        ? '${s.accountName(e['account_id'])} to ${s.accountName(e['destination_id'])}'
                        : '${s.categoryName(e['category_id'])} · ${s.accountName(e['account_id'])}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${transfer
                          ? ''
                          : income
                          ? '+'
                          : '-'}${cash(e['amount'] as int)}',
                      style: TextStyle(
                        color: income ? green : null,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    DateFormat(
                      'dd MMM',
                    ).format(DateTime.parse(e['date'] as String)),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget history() {
    final entries = s.entries.where((e) {
      final date = DateTime.parse(e['date'] as String);
      return (typeFilter == 'all' || e['type'] == typeFilter) &&
          (accountFilter == null ||
              e['account_id'] == accountFilter ||
              e['destination_id'] == accountFilter) &&
          (range == null ||
              (!date.isBefore(range!.start) &&
                  date.isBefore(range!.end.add(const Duration(days: 1))))) &&
          '${e['note']} ${s.categoryName(e['category_id'])}'
              .toLowerCase()
              .contains(search.toLowerCase());
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title('Every rupee, in one place', 'Activity'),
        TextField(
          controller: searchController,
          decoration: InputDecoration(
            hintText: 'Search transactions',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: 'Filter transactions',
              onPressed: transactionFilters,
              icon: const Icon(Icons.tune_rounded),
            ),
          ),
          onChanged: (v) => setState(() => search = v),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final t in ['all', 'expense', 'income', 'transfer'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      t == 'all' ? 'All' : t[0].toUpperCase() + t.substring(1),
                    ),
                    selected: typeFilter == t,
                    onSelected: (_) => setState(() => typeFilter = t),
                  ),
                ),
            ],
          ),
        ),
        if (accountFilter != null || range != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              children: [
                if (accountFilter != null)
                  InputChip(
                    label: Text(s.accountName(accountFilter)),
                    onDeleted: () => setState(() => accountFilter = null),
                  ),
                if (range != null)
                  InputChip(
                    label: Text(
                      '${DateFormat('dd MMM').format(range!.start)} - ${DateFormat('dd MMM').format(range!.end)}',
                    ),
                    onDeleted: () => setState(() => range = null),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                '${entries.length} transactions',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ),
            TextButton.icon(
              onPressed: transactionFilters,
              icon: const Icon(Icons.filter_list_rounded, size: 18),
              label: const Text('Filters'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: .08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    size: 40,
                    color: green,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'A fresh start',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your transactions will appear here.\nTap + to add your first entry.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          )
        else
          panel(Column(children: entries.map(entryTile).toList())),
      ],
    );
  }

  Future<void> transactionFilters() async {
    int? account = accountFilter;
    DateTimeRange? dates = range;
    await form(
      'Filter activity',
      (update) => [
        select<int>('Account', account ?? -1, [
          const DropdownMenuItem(value: -1, child: Text('All accounts')),
          ...s.accounts.map(
            (a) => DropdownMenuItem(
              value: a['id'] as int,
              child: Text(a['name'] as String),
            ),
          ),
        ], (v) => update(() => account = v == -1 ? null : v)),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDateRangePicker(
              context: context,
              initialDateRange: dates,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) update(() => dates = picked);
          },
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(
            dates == null
                ? 'Choose date range'
                : '${DateFormat('dd MMM').format(dates!.start)} - ${DateFormat('dd MMM').format(dates!.end)}',
          ),
        ),
        TextButton(
          onPressed: () => update(() {
            account = null;
            dates = null;
          }),
          child: const Text('Clear filters'),
        ),
      ],
      () async {
        setState(() {
          accountFilter = account;
          range = dates;
        });
      },
    );
  }

  Widget accountsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'A place for every rupee',
        'Your accounts',
        IconButton(
          onPressed: () => editAccount(),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ),
      ...s.accounts.map(
        (a) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => editAccount(a),
            child: panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: green.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_outlined,
                          color: green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a['name'] as String,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${a['type']}${a['archived'] == 1 ? ' · Archived' : ''}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.more_horiz_rounded),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      cash(s.balance(a['id'] as int)),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 24),
      heading('Categories', () => editCategory()),
      ...s.categories.map(
        (c) => ListTile(
          leading: Icon(
            icons[(c['icon'] as int) % icons.length],
            color: colors[(c['color'] as int) % colors.length],
          ),
          title: Text('${c['name']}${c['archived'] == 1 ? ' · Archived' : ''}'),
          subtitle: Text(c['type'] as String),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => editCategory(c),
        ),
      ),
      const SizedBox(height: 90),
    ],
  );
  Widget budgetTile(Map<String, Object?> b) {
    final used = s.total(
          'expense',
          b['month'] as String,
          category: b['category_id'] as int,
        ),
        limit = b['amount'] as int;
    final ratio = used / limit,
        color = ratio >= 1
            ? Colors.redAccent
            : ratio >= .8
            ? Colors.orange
            : green;
    return InkWell(
      onTap: () => editBudget(b),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.categoryName(b['category_id']),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${(ratio * 100).round()}%',
                  style: TextStyle(color: color),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: ratio.clamp(0, 1),
              color: color,
              backgroundColor: color.withValues(alpha: .12),
              minHeight: 7,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(height: 9),
            Text(
              '${cash(used)} of ${cash(limit)} · ${cash((limit - used).abs())} ${used > limit ? 'over budget' : 'left'}',
              style: TextStyle(fontSize: 13, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget planning() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title('Build the life you want', 'Plan & save'),
      monthPicker(),
      const SizedBox(height: 16),
      panel(
        Column(
          children: [
            heading('Category budgets', () => editBudget()),
            ...s.budgets.where((b) => b['month'] == month).map(budgetTile),
            if (!s.budgets.any((b) => b['month'] == month))
              empty('No budgets for this month. Add one to get started.'),
          ],
        ),
      ),
      const SizedBox(height: 24),
      heading('Savings goals', () => editGoal()),
      const Text(
        'Contributions are allocations, so they do not reduce account balances or count as expenses.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 16),
      ...s.goals.map((g) {
        final saved = s.saved(g['id'] as int), target = g['target'] as int;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flag_outlined, color: green),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        g['name'] as String,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => editGoal(g),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('${cash(saved)} / ${cash(target)}'),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: (saved / target).clamp(0, 1),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 12),
                Text(
                  saved >= target
                      ? '✓ Goal completed!'
                      : '${cash(target - saved)} to go${g['date'] == null ? '' : ' · Target ${g['date']}'}',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => contribute(g),
                  icon: const Icon(Icons.add),
                  label: const Text('Add contribution'),
                ),
                ...s.contributions
                    .where((c) => c['goal_id'] == g['id'])
                    .map(
                      (c) => ListTile(
                        dense: true,
                        title: Text(cash(c['amount'] as int)),
                        subtitle: Text((c['date'] as String).substring(0, 10)),
                        trailing: IconButton(
                          tooltip: 'Remove contribution',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => act(() async {
                            if (await confirm(
                              'Remove contribution?',
                              'This allocation will be removed from the goal.',
                            )) {
                              await s.remove(
                                'goal_contributions',
                                c['id'] as int,
                              );
                            }
                          }),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        );
      }),
      if (s.goals.isEmpty)
        empty('A new laptop? A rainy-day fund?\nGive your next goal a name.'),
    ],
  );
  Widget spendingChart() {
    final values =
        s.categories
            .map(
              (c) => MapEntry(
                c,
                s.total('expense', month, category: c['id'] as int),
              ),
            )
            .where((e) => e.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    if (values.isEmpty) {
      return empty(
        'Your spending picture will appear\nafter your first expense.',
      );
    }
    final total = values.fold<int>(0, (sum, e) => sum + e.value);
    return Column(
      children: [
        SizedBox(
          height: 170,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(170, 170),
                painter: RingPainter(
                  values.map((e) => e.value).toList(),
                  values
                      .map(
                        (e) => colors[(e.key['color'] as int) % colors.length],
                      )
                      .toList(),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'SPENT',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cash(total),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ...values.map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 4,
                  backgroundColor:
                      colors[(e.key['color'] as int) % colors.length],
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    e.key['name'] as String,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Text(
                  '${(e.value / total * 100).round()}%  ·  ${cash(e.value)}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget reports() {
    final income = s.total('income', month),
        expense = s.total('expense', month);
    final periods = List.generate(
      6,
      (i) => DateTime(period.year, period.month - 5 + i),
    );
    final maxValue = periods.fold<int>(
      1,
      (m, d) => max(
        m,
        max(
          s.total('income', DateFormat('yyyy-MM').format(d)),
          s.total('expense', DateFormat('yyyy-MM').format(d)),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title('See the bigger picture', 'Financial reports'),
        monthPicker(),
        const SizedBox(height: 20),
        panel(
          Row(
            children: [
              Expanded(child: metric('Income', income)),
              Expanded(child: metric('Expenses', expense)),
              Expanded(child: metric('Net cash flow', income - expense)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Six-month cash flow'),
              const Text(
                'Green: income   ·   Amber: expenses',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 26),
              SizedBox(
                height: 190,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: periods.map((d) {
                    final m = DateFormat('yyyy-MM').format(d);
                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (final t in ['income', 'expense'])
                                  Tooltip(
                                    message: '$t: ${cash(s.total(t, m))}',
                                    child: Container(
                                      width: 12,
                                      height:
                                          150 * s.total(t, m) / maxValue + 2,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: t == 'income'
                                            ? green
                                            : colors[1],
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(5),
                                            ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            DateFormat('MMM').format(d),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        panel(
          Column(children: [heading('Spending by category'), spendingChart()]),
        ),
        const SizedBox(height: 20),
        panel(
          Column(
            children: [
              heading('Balances by account'),
              ...s.accounts.map(
                (a) => ListTile(
                  title: Text(
                    '${a['name']}${a['archived'] == 1 ? ' (archived)' : ''}',
                  ),
                  trailing: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(cash(s.balance(a['id'] as int))),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> form(
    String title,
    List<Widget> Function(void Function(void Function())) fields,
    Future<void> Function() save, {
    Future<void> Function()? remove,
  }) async {
    String? error;
    bool busy = false;
    final route = ModalBottomSheetRoute<void>(
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  MediaQuery.sizeOf(ctx).height * .92 -
                  MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  height: 4,
                  width: 36,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: busy ? null : () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...fields(
                          update,
                        ).expand((w) => [w, const SizedBox(height: 16)]),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(ctx).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: Row(
                      children: [
                        if (remove != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: IconButton.filledTonal(
                              tooltip: 'Delete',
                              onPressed: busy
                                  ? null
                                  : () async {
                                      if (!await confirm(
                                        'Delete this record?',
                                        'This cannot be undone.',
                                      )) {
                                        return;
                                      }
                                      if (!ctx.mounted) return;
                                      update(() {
                                        busy = true;
                                        error = null;
                                      });
                                      try {
                                        await remove();
                                        if (ctx.mounted) Navigator.pop(ctx);
                                      } catch (e) {
                                        if (ctx.mounted) {
                                          update(() {
                                            busy = false;
                                            error = friendlyError(e);
                                          });
                                        }
                                      }
                                    },
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ),
                        Expanded(
                          child: FilledButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    update(() {
                                      busy = true;
                                      error = null;
                                    });
                                    try {
                                      await save();
                                      if (ctx.mounted) Navigator.pop(ctx);
                                    } catch (e) {
                                      if (ctx.mounted) {
                                        update(() {
                                          busy = false;
                                          error = friendlyError(e);
                                        });
                                      }
                                    }
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(busy ? 'Saving...' : 'Save'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
  }

  Widget field(TextEditingController c, String label, {bool amount = false}) =>
      TextField(
        controller: c,
        decoration: InputDecoration(labelText: label),
        keyboardType: amount
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
      );
  Widget select<T>(
    String label,
    T? value,
    List<DropdownMenuItem<T>> items,
    void Function(T?) onChanged,
  ) => DropdownButtonFormField<T>(
    key: ValueKey('$label-$value-${items.length}'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: items,
    onChanged: onChanged,
  );
  void requiredText(String text) {
    if (text.trim().isEmpty) {
      throw const FormatException('Please fill in all names.');
    }
  }

  int positive(String value) {
    final n = money(value);
    if (n <= 0) {
      throw const FormatException('Amount must be greater than zero.');
    }
    return n;
  }

  Future<void> editEntry([
    Map<String, Object?>? e,
    String initialType = 'expense',
  ]) async {
    if (s.accounts.where((a) => a['archived'] == 0).isEmpty) {
      await editAccount();
      return;
    }
    String type = e?['type'] as String? ?? initialType;
    final amount = TextEditingController(
          text: e == null
              ? ''
              : ((e['amount'] as int) / 100).toStringAsFixed(2),
        ),
        note = TextEditingController(text: e?['note'] as String? ?? '');
    int? account =
            e?['account_id'] as int? ??
            s.accounts.firstWhere((a) => a['archived'] == 0)['id'] as int,
        destination = e?['destination_id'] as int?,
        category = e?['category_id'] as int?;
    DateTime date = e == null
        ? DateTime.now()
        : DateTime.parse(e['date'] as String);
    await form(
      e == null ? 'New transaction' : 'Edit transaction',
      (update) {
        final cats = s.categories
            .where(
              (c) =>
                  c['type'] == type &&
                  (c['archived'] == 0 || c['id'] == category),
            )
            .toList();
        if (!cats.any((c) => c['id'] == category)) {
          category = cats.firstOrNull?['id'] as int?;
        }
        final accts = s.accounts
            .where(
              (a) =>
                  a['archived'] == 0 ||
                  a['id'] == account ||
                  a['id'] == destination,
            )
            .toList();
        return [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'expense', label: Text('Expense')),
              ButtonSegment(value: 'income', label: Text('Income')),
              ButtonSegment(value: 'transfer', label: Text('Transfer')),
            ],
            selected: {type},
            onSelectionChanged: (v) => update(() {
              type = v.first;
              category = null;
            }),
          ),
          field(amount, 'Amount', amount: true),
          select<int>(
            'Account',
            account,
            accts
                .map(
                  (a) => DropdownMenuItem(
                    value: a['id'] as int,
                    child: Text(a['name'] as String),
                  ),
                )
                .toList(),
            (v) => update(() => account = v),
          ),
          if (type == 'transfer')
            select<int>(
              'Destination account',
              destination,
              accts
                  .map(
                    (a) => DropdownMenuItem(
                      value: a['id'] as int,
                      child: Text(a['name'] as String),
                    ),
                  )
                  .toList(),
              (v) => update(() => destination = v),
            )
          else
            select<int>(
              'Category',
              category,
              cats
                  .map(
                    (c) => DropdownMenuItem(
                      value: c['id'] as int,
                      child: Text(c['name'] as String),
                    ),
                  )
                  .toList(),
              (v) => update(() => category = v),
            ),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) update(() => date = picked);
            },
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(DateFormat('dd MMM yyyy').format(date)),
          ),
          field(note, 'Note (optional)'),
        ];
      },
      () async {
        if (type == 'transfer' && destination == null) {
          throw const FormatException('Select a destination account.');
        }
        if (type != 'transfer' && category == null) {
          throw const FormatException('Create or select a category first.');
        }
        await s.transaction({
          'id': e?['id'],
          'type': type,
          'amount': positive(amount.text),
          'account_id': account,
          'destination_id': type == 'transfer' ? destination : null,
          'category_id': type == 'transfer' ? null : category,
          'date': DateFormat('yyyy-MM-dd').format(date),
          'note': note.text.trim(),
        });
      },
      remove: e == null ? null : () => s.remove('transactions', e['id'] as int),
    );
    amount.dispose();
    note.dispose();
  }

  Future<void> editAccount([Map<String, Object?>? a]) async {
    final name = TextEditingController(text: a?['name'] as String? ?? ''),
        opening = TextEditingController(
          text: ((a?['opening'] as int? ?? 0) / 100).toStringAsFixed(2),
        );
    String type = a?['type'] as String? ?? 'Cash';
    bool archived = a?['archived'] == 1;
    await form(
      a == null ? 'New account' : 'Edit account',
      (update) => [
        field(name, 'Account name'),
        select<String>(
          'Account type',
          type,
          [
            'Cash',
            'Bank',
            'Digital Wallet',
          ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          (v) => update(() => type = v!),
        ),
        field(opening, 'Opening balance', amount: true),
        if (a != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Archive account'),
            subtitle: const Text(
              'Keep its history; hide from active balances.',
            ),
            value: archived,
            onChanged: (v) => update(() => archived = v),
          ),
      ],
      () async {
        requiredText(name.text);
        await s.save('accounts', {
          'id': a?['id'],
          'name': name.text.trim(),
          'type': type,
          'opening': money(opening.text),
          'archived': archived ? 1 : 0,
        });
      },
    );
    name.dispose();
    opening.dispose();
  }

  Future<void> editCategory([Map<String, Object?>? c]) async {
    final name = TextEditingController(text: c?['name'] as String? ?? '');
    String type = c?['type'] as String? ?? 'expense';
    int color = c?['color'] as int? ?? 0, icon = c?['icon'] as int? ?? 0;
    bool archived = c?['archived'] == 1;
    await form(
      c == null ? 'New category' : 'Edit category',
      (update) => [
        field(name, 'Category name'),
        if (c == null)
          select<String>(
            'Type',
            type,
            [
              'expense',
              'income',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            (v) => update(() => type = v!),
          ),
        Wrap(
          spacing: 8,
          children: List.generate(
            colors.length,
            (i) => ChoiceChip(
              label: Icon(Icons.circle, color: colors[i]),
              selected: color == i,
              onSelected: (_) => update(() => color = i),
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          children: List.generate(
            icons.length,
            (i) => ChoiceChip(
              label: Icon(icons[i]),
              selected: icon == i,
              onSelected: (_) => update(() => icon = i),
            ),
          ),
        ),
        if (c != null)
          SwitchListTile(
            title: const Text('Archive category'),
            value: archived,
            onChanged: (v) => update(() => archived = v),
          ),
      ],
      () async {
        requiredText(name.text);
        await s.save('categories', {
          'id': c?['id'],
          'name': name.text.trim(),
          'type': type,
          'color': color,
          'icon': icon,
          'archived': archived ? 1 : 0,
        });
      },
    );
    name.dispose();
  }

  Future<void> editBudget([Map<String, Object?>? b]) async {
    final amount = TextEditingController(
      text: b == null ? '' : ((b['amount'] as int) / 100).toStringAsFixed(2),
    );
    int? category = b?['category_id'] as int?;
    final cats = s.categories
        .where(
          (c) =>
              c['type'] == 'expense' &&
              (c['archived'] == 0 || c['id'] == category),
        )
        .toList();
    category ??= cats.firstOrNull?['id'] as int?;
    await form(
      'Budget · ${b?['month'] ?? month}',
      (update) => [
        select<int>(
          'Expense category',
          category,
          cats
              .map(
                (c) => DropdownMenuItem(
                  value: c['id'] as int,
                  child: Text(c['name'] as String),
                ),
              )
              .toList(),
          (v) => update(() => category = v),
        ),
        field(amount, 'Monthly limit', amount: true),
      ],
      () async {
        if (category == null) {
          throw const FormatException('Select an expense category.');
        }
        if (s.budgets.any(
          (x) =>
              x['id'] != b?['id'] &&
              x['category_id'] == category &&
              x['month'] == (b?['month'] ?? month),
        )) {
          throw const FormatException(
            'This category already has a budget for this month.',
          );
        }
        await s.save('budgets', {
          'id': b?['id'],
          'category_id': category,
          'month': b?['month'] ?? month,
          'amount': positive(amount.text),
        });
      },
      remove: b == null ? null : () => s.remove('budgets', b['id'] as int),
    );
    amount.dispose();
  }

  Future<void> editGoal([Map<String, Object?>? g]) async {
    final name = TextEditingController(text: g?['name'] as String? ?? ''),
        amount = TextEditingController(
          text: g == null
              ? ''
              : ((g['target'] as int) / 100).toStringAsFixed(2),
        );
    DateTime? date = g?['date'] == null
        ? null
        : DateTime.parse(g!['date'] as String);
    await form(
      g == null ? 'New savings goal' : 'Edit savings goal',
      (update) => [
        field(name, 'Goal name'),
        field(amount, 'Target amount', amount: true),
        OutlinedButton(
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: date ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (d != null) update(() => date = d);
          },
          child: Text(
            date == null
                ? 'Set target date (optional)'
                : DateFormat('dd MMM yyyy').format(date!),
          ),
        ),
        if (date != null)
          TextButton(
            onPressed: () => update(() => date = null),
            child: const Text('Remove date'),
          ),
      ],
      () async {
        requiredText(name.text);
        await s.save('savings_goals', {
          'id': g?['id'],
          'name': name.text.trim(),
          'target': positive(amount.text),
          'date': date == null ? null : DateFormat('yyyy-MM-dd').format(date!),
        });
      },
      remove: g == null
          ? null
          : () => s.remove('savings_goals', g['id'] as int),
    );
    name.dispose();
    amount.dispose();
  }

  Future<void> contribute(Map<String, Object?> goal) async {
    final amount = TextEditingController();
    await form(
      'Contribute to ${goal['name']}',
      (_) => [
        field(amount, 'Amount', amount: true),
        const Text('This is a savings allocation, not a transaction.'),
      ],
      () => s.save('goal_contributions', {
        'goal_id': goal['id'],
        'amount': positive(amount.text),
        'date': DateTime.now().toIso8601String(),
      }),
    );
    amount.dispose();
  }

  Widget settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title('Just the way you like it', 'Settings'),
      panel(
        Column(
          children: [
            heading('Profile & preferences'),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Display name'),
              subtitle: Text(s.settings['name'] ?? ''),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => act(() async {
                final name = await prompt('Your display name');
                if (name != null) {
                  requiredText(name);
                  await s.preference('name', name.trim());
                }
              }),
            ),
            select<String>(
              'Display currency (does not convert amounts)',
              s.settings['currency'] ?? 'PKR',
              [
                'PKR',
                'USD',
                'EUR',
                'GBP',
                'AED',
                'INR',
              ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              (v) => act(() async {
                if (await confirm(
                  'Change display currency?',
                  'Existing amounts will keep their numeric values. No exchange conversion is performed.',
                )) {
                  await s.preference('currency', v!);
                }
              }),
            ),
            SwitchListTile(
              title: const Text('Dark appearance'),
              value: s.settings['dark'] == 'true',
              onChanged: (v) => s.preference('dark', '$v'),
            ),
            SwitchListTile(
              title: const Text('Notification preference'),
              subtitle: const Text('Saved for optional reminder features.'),
              value: s.settings['notifications'] == 'true',
              onChanged: (v) => s.preference('notifications', '$v'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      panel(
        Column(
          children: [
            heading('Privacy & security'),
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: const Text('Set or change app PIN'),
              subtitle: const Text(
                'Biometrics available when enrolled on your device',
              ),
              onTap: () => act(() async {
                if (await widget.security.hasPin()) {
                  final current = await prompt('Current PIN', secret: true);
                  if (current == null) return;
                  if (!await widget.security.verify(current)) {
                    throw const FormatException('Incorrect PIN.');
                  }
                }
                final pin = await prompt('New PIN (4–8 digits)', secret: true);
                if (pin == null) return;
                final repeat = await prompt('Confirm new PIN', secret: true);
                if (pin != repeat) {
                  throw const FormatException('PINs do not match.');
                }
                await widget.security.setPin(pin);
              }),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Lock now'),
              onTap: () => act(() async {
                if (!await widget.security.hasPin()) {
                  throw const FormatException('Set an app PIN first.');
                }
                widget.lock();
              }),
            ),
            ListTile(
              leading: const Icon(Icons.lock_open),
              title: const Text('Disable app lock'),
              onTap: () => act(() async {
                final pin = await prompt('Current PIN', secret: true);
                if (pin != null && await widget.security.verify(pin)) {
                  await widget.security.storage.delete(key: 'pin');
                } else if (pin != null) {
                  throw const FormatException('Incorrect PIN.');
                }
              }),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading('Google Drive backup'),
            Text(
              backup.status,
              style: const TextStyle(color: green, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Changes back up automatically while the app is open. Offline changes retry when you reopen the app. Keep your passphrase for restoring on another device.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () => act(() async {
                    await backup.connect();
                    if (mounted) setState(() {});
                  }),
                  icon: const Icon(Icons.cloud_outlined),
                  label: Text(backup.email ?? 'Connect Google'),
                ),
                if (backup.connected)
                  TextButton(
                    onPressed: () => act(() async {
                      await backup.disconnect();
                      if (mounted) setState(() {});
                    }),
                    child: const Text('Disconnect'),
                  ),
                FilledButton(
                  onPressed: () => act(() async {
                    await backup.sync(force: true);
                    if (backup.status != 'All changes backed up') {
                      throw const FormatException(
                        'Backup pending. Check your connection and try again.',
                      );
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Encrypted backup uploaded successfully.',
                          ),
                        ),
                      );
                    }
                  }),
                  child: const Text('Back up now'),
                ),
                OutlinedButton(
                  onPressed: restoreBackup,
                  child: const Text('Restore backup'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...s.backups
                .take(5)
                .map(
                  (b) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      b['status'] == 'Successful'
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: b['status'] == 'Successful' ? green : Colors.red,
                    ),
                    title: Text(b['status'] as String),
                    subtitle: Text(b['date'] as String),
                  ),
                ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const Center(
        child: Text(
          'SpendNote 1.2.0\nA calmer relationship with your money.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ),
    ],
  );
  Future<void> restoreBackup() => act(() async {
    final files = await backup.list();
    if (!mounted) return;
    if (files.isEmpty) {
      throw const FormatException('No backups found in this Google account.');
    }
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose backup'),
        children: files
            .map(
              (f) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, f.id),
                child: Text(f.name ?? 'Backup'),
              ),
            )
            .toList(),
      ),
    );
    if (id == null) return;
    final password = await prompt('Backup passphrase', secret: true);
    if (password == null) return;
    final snapshot = await backup.read(id, password);
    if (!await confirm(
      'Replace all local financial data?',
      'The encrypted file has been authenticated. Restoring replaces your current records and preferences. This cannot be undone.',
    )) {
      return;
    }
    if (backup.busy) {
      throw const FormatException(
        'Wait for the current backup to finish, then restore.',
      );
    }
    await s.restore(snapshot);
    await widget.security.storage.delete(key: backup.storageKey('revision'));
    backup.schedule();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup restored successfully.')),
      );
    }
  });
}

class RingPainter extends CustomPainter {
  RingPainter(this.values, this.colors);
  final List<int> values;
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    var start = -pi / 2;
    final total = values.fold<int>(0, (a, b) => a + b);
    final rect = Rect.fromLTWH(13, 13, size.width - 26, size.height - 26);
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * pi * 2;
      canvas.drawArc(
        rect,
        start,
        max(0, sweep - .035),
        false,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 15
          ..strokeCap = StrokeCap.round,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant RingPainter oldDelegate) => true;
}
