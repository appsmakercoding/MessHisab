import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'common.dart';
import 'config.dart';
import 'firebase_options.dart';
import 'meal.dart';
import 'ledger.dart';
import 'report.dart';
import 'settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  try { db.setPersistenceEnabled(true); db.setPersistenceCacheSizeBytes(10 * 1024 * 1024); } catch (_) {}
  await Prefs.load();
  runApp(const MessApp());
}

class MessApp extends StatelessWidget {
  const MessApp({super.key});
  ThemeData th(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: teal, brightness: b),

        inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        appBarTheme: const AppBarTheme(centerTitle: true),
      );
  @override
  Widget build(BuildContext c) => ValueListenableBuilder<ThemeMode>(
        valueListenable: Prefs.theme,
        builder: (_, tm, __) => ValueListenableBuilder<bool>(
          valueListenable: Prefs.bnDigits,
          builder: (_, __, ___) => MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'মেস হিসাব',
            theme: th(Brightness.light),
            darkTheme: th(Brightness.dark),
            themeMode: tm,
            home: StreamBuilder<User?>(
                stream: auth.authStateChanges(),
                builder: (c, s) => s.connectionState == ConnectionState.waiting
                    ? const Scaffold(body: Center(child: CircularProgressIndicator()))
                    : s.data == null ? const LoginPage() : Gate(s.data!.uid)),
          ),
        ),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginState();
}

class _LoginState extends State<LoginPage> {
  final nm = TextEditingController(), ph = TextEditingController(), ps = TextEditingController();
  bool reg = false, busy = false, hide = true;
  Future<void> go() async {
    if (ph.text.trim().isEmpty || ps.text.length < 6 || (reg && nm.text.trim().isEmpty)) { snack(context, 'সব ঘর পূরণ করুন (পাসওয়ার্ড কমপক্ষে ৬ অক্ষর)'); return; }
    setState(() => busy = true);
    try {
      if (reg) {
        final u = (await auth.createUserWithEmailAndPassword(email: em(ph.text), password: ps.text)).user!.uid;
        final name = nm.text.trim();
        await db.ref('users/$u').set({'messId': u, 'role': 'monitor', 'name': name, 'active': true});
        await db.ref('messes/$u/members/$u').set({'name': name, 'role': 'monitor', 'phone': ph.text.trim(), 'active': true, 'rent': 0, 'def': {'b': 1, 'l': 1, 'd': 1}});
        await db.ref('licenses/$u').set({'active': false, 'maxBoarders': 100});
      } else {
        await auth.signInWithEmailAndPassword(email: em(ph.text), password: ps.text);
      }
    } on FirebaseAuthException catch (e) {
      final msg = {'invalid-credential': 'মোবাইল বা পাসওয়ার্ড ভুল', 'wrong-password': 'পাসওয়ার্ড ভুল', 'user-not-found': 'এই নম্বরে অ্যাকাউন্ট নেই', 'email-already-in-use': 'এই নম্বরে আগেই অ্যাকাউন্ট আছে'}[e.code];
      if (mounted) snack(context, msg ?? e.message ?? 'ত্রুটি');
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        body: Container(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [teal.withOpacity(.18), Theme.of(c).colorScheme.surface])),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  logo(s: 96),
                  const SizedBox(height: 12),
                  const Text('মেস হিসাব', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                  const Text('মিল • বাজার • জমা • হিসাব — সব এক জায়গায়', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 24),
                  if (reg) TextField(controller: nm, decoration: const InputDecoration(labelText: 'আপনার নাম', prefixIcon: Icon(Icons.person))),
                  if (reg) const SizedBox(height: 12),
                  TextField(controller: ph, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'মোবাইল নম্বর', prefixIcon: Icon(Icons.phone))),
                  const SizedBox(height: 12),
                  TextField(controller: ps, obscureText: hide, decoration: InputDecoration(labelText: 'পাসওয়ার্ড (কমপক্ষে ৬)', prefixIcon: const Icon(Icons.lock), suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => hide = !hide)))),
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: busy ? null : go, child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(reg ? 'মনিটর হিসেবে রেজিস্টার' : 'লগইন'))),
                  TextButton(onPressed: () => setState(() => reg = !reg), child: Text(reg ? 'অ্যাকাউন্ট আছে? লগইন' : 'নতুন মেস? রেজিস্টার করুন')),
                  if (!reg) const Text('সদস্য হলে মনিটরের দেওয়া মোবাইল ও পাসওয়ার্ড দিয়ে লগইন করুন', style: TextStyle(fontSize: 11), textAlign: TextAlign.center),
                  footer(),
                ]),
              ),
            ),
          ),
        ),
      );
}

class Gate extends StatelessWidget {
  final String uid;
  const Gate(this.uid, {super.key});
  @override
  Widget build(BuildContext c) {
    const wait = Scaffold(body: Center(child: CircularProgressIndicator()));
    return StreamBuilder<DatabaseEvent>(
      stream: db.ref('users/$uid').onValue,
      builder: (c, s) {
        if (!s.hasData) return wait;
        final p = m(s.data!.snapshot.value);
        if (p.isEmpty) return const LockPage('', 'অ্যাকাউন্ট পাওয়া যায়নি। মনিটরের সাথে যোগাযোগ করুন।');
        if (p['active'] == false) return const LockPage('', 'আপনার অ্যাকাউন্ট বন্ধ আছে। মনিটরের সাথে যোগাযোগ করুন।');
        final mid = p['messId'] as String;
        return StreamBuilder<DatabaseEvent>(
          stream: db.ref('licenses/$mid').onValue,
          builder: (c, s2) {
            if (!s2.hasData) return wait;
            final l = m(s2.data!.snapshot.value);
            final exp = l['expiry'] as String?;
            final ok = l['active'] == true && (exp == null || exp.compareTo(today()) >= 0);
            return ok ? Shell(uid, mid, p, l) : LockPage(mid, p['role'] == 'monitor' ? 'অ্যাক্টিভেশনের জন্য নিচের Mess ID টেলিগ্রামে পাঠান।' : 'মেসের লাইসেন্স সক্রিয় নেই। মনিটরের সাথে যোগাযোগ করুন।');
          },
        );
      },
    );
  }
}

class LockPage extends StatelessWidget {
  final String mid, msg;
  const LockPage(this.mid, this.msg, {super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              logo(),
              const SizedBox(height: 16),
              Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              if (mid.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(mid, style: const TextStyle(fontWeight: FontWeight.bold)),
                TextButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: mid)); snack(c, 'কপি হয়েছে'); }, icon: const Icon(Icons.copy), label: const Text('Mess ID কপি')),
              ],
              FilledButton.icon(onPressed: () => openUrl(telegram), icon: const Icon(Icons.send), label: const Text('টেলিগ্রামে যোগাযোগ $telegramName')),
              TextButton(onPressed: auth.signOut, child: const Text('লগআউট')),
              footer(),
            ]),
          ),
        ),
      );
}

class Shell extends StatefulWidget {
  final String uid, mid;
  final Map p, l;
  const Shell(this.uid, this.mid, this.p, this.l, {super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int i = 0;
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  /// ব্যাকগ্রাউন্ডে গেলে ফায়ারবেস সংযোগ বন্ধ — ফ্রি লিমিট বাঁচাতে
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    try {
      if (s == AppLifecycleState.paused) { db.goOffline(); } else if (s == AppLifecycleState.resumed) { db.goOnline(); }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext c) {
    Me.uid = widget.uid; Me.mid = widget.mid; Me.role = '${widget.p['role']}'; Me.name = '${widget.p['name']}'; Me.lic = widget.l;
    final isOwner = Me.role == 'owner';
    final pages = <Widget>[const HomePage(), const MealPage(), const LedgerPage(), const ReportPage(), const SettingsPage()];
    const titles = ['মেস হিসাব', 'মিল', 'এন্ট্রি / হিসাব', 'রিপোর্ট', 'সেটিংস'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[i]), toolbarHeight: 48),
      body: SafeArea(child: Column(children: [const OfflineBanner(), Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: KeyedSubtree(key: ValueKey(i), child: pages[i])))])),
      bottomNavigationBar: NavigationBar(selectedIndex: i, onDestinationSelected: (v) => setState(() => i = v), destinations: [
        const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'হোম'),
        NavigationDestination(icon: const Icon(Icons.restaurant_outlined), selectedIcon: const Icon(Icons.restaurant), label: isOwner ? 'মিল' : 'মিল'),
        const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'এন্ট্রি'),
        const NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'রিপোর্ট'),
        const NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'সেটিংস'),
      ]),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomeState();
}

class _HomeState extends State<HomePage> {
  late Future<Calc> f;
  @override
  void initState() { super.initState(); f = Calc.load(ymOf(DateTime.now())); }

  Widget action(IconData ic, String t, VoidCallback go) => Expanded(
      child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: go,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(children: [
            CircleAvatar(radius: 24, backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: Icon(ic)),
            const SizedBox(height: 4),
            Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          ]))));

  @override
  Widget build(BuildContext c) {
    final mid = Me.mid, ym = ymOf(DateTime.now()), cs = Theme.of(c).colorScheme;
    final hr = DateTime.now().hour;
    final greet = hr < 5 ? 'শুভ রাত্রি' : hr < 12 ? 'শুভ সকাল' : hr < 17 ? 'শুভ দুপুর' : hr < 20 ? 'শুভ সন্ধ্যা' : 'শুভ রাত্রি';
    return RefreshIndicator(
      onRefresh: () async { setState(() => f = Calc.load(ym)); await f; },
      child: ListView(padding: const EdgeInsets.all(14), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: const LinearGradient(colors: [Color(0xFF00695C), Color(0xFF26A69A)])),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(greet, style: const TextStyle(color: Colors.white70)),
              Text(Me.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              Text('${roles[Me.role]} • ${monthLabel(DateTime.now())}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
            const Icon(Icons.restaurant_menu, color: Colors.white54, size: 44),
          ]),
        ),
        // আপডেট নোটিশ (কনসোলের config/app থেকে)
        StreamBuilder<DatabaseEvent>(
          stream: db.ref('config/app').onValue,
          builder: (c, s) {
            final x = m(s.data?.snapshot.value);
            if (n(x['ver']) <= appBuild) return const SizedBox();
            return Card(color: cs.tertiaryContainer, child: ListTile(leading: const Icon(Icons.system_update), title: Text('${x['msg'] ?? 'নতুন আপডেট এসেছে'}'), trailing: x['url'] == null ? null : TextButton(onPressed: () => openUrl('${x['url']}'), child: const Text('ডাউনলোড'))));
          },
        ),
        StreamBuilder<DatabaseEvent>(
          stream: db.ref('messes/$mid/notice').onValue,
          builder: (c, s) {
            final t = '${s.data?.snapshot.value ?? ''}';
            return t.isEmpty ? const SizedBox() : Card(color: Colors.amber.shade100, child: ListTile(leading: const Icon(Icons.campaign, color: Colors.black87), title: Text(t, style: const TextStyle(color: Colors.black87))));
          },
        ),
        StreamBuilder<DatabaseEvent>(
          stream: db.ref('messes/$mid/menu/${today()}').onValue,
          builder: (c, s) {
            final x = m(s.data?.snapshot.value);
            final has = x.isNotEmpty;
            if (!has && !Me.meal) return const SizedBox();
            return Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.restaurant_menu, size: 18),
                    const SizedBox(width: 6),
                    const Expanded(child: Text('আজকের মেনু', style: TextStyle(fontWeight: FontWeight.w600))),
                    if (Me.meal) IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit, size: 18), onPressed: () => editMenu(c)),
                  ]),
                  if (!has) const Text('মেনু দেওয়া হয়নি — পেন্সিল চেপে দিন', style: TextStyle(fontSize: 12)),
                  if (x['b'] != null) Text('সকাল: ${x['b']}'),
                  if (x['l'] != null) Text('দুপুর: ${x['l']}'),
                  if (x['d'] != null) Text('রাত: ${x['d']}'),
                ]),
              ),
            );
          },
        ),
        StreamBuilder<DatabaseEvent>(
          stream: db.ref('messes/$mid/locked/$ym').onValue,
          builder: (c, s) => s.data?.snapshot.value == true ? const Card(child: ListTile(leading: Icon(Icons.lock), title: Text('এ মাস ক্লোজ করা — এন্ট্রি বদলানো যাবে না'))) : const SizedBox(),
        ),
        const SizedBox(height: 10),
        const Text('আজকের মিল', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        StreamBuilder<DatabaseEvent>(
          stream: db.ref('messes/$mid/meals/$ym/${today()}').onValue,
          builder: (c, s) {
            int b = 0, l = 0, d = 0, g = 0, mine = 0;
            m(s.data?.snapshot.value).forEach((u, v) {
              b += n(m(v)['b']); l += n(m(v)['l']); d += n(m(v)['d']); g += n(m(v)['g']);
              if (u == Me.uid) mine = n(m(v)['b']) + n(m(v)['l']) + n(m(v)['d']);
            });
            return Column(children: [
              Row(children: [Stat('সকাল', bn(b), Icons.wb_twilight), Stat('দুপুর', bn(l), Icons.wb_sunny), Stat('রাত', bn(d), Icons.nights_stay), Stat('গেস্ট', bn(g), Icons.people)]),
              Text('আজ আমার মিল: ${bn(mine)}', style: const TextStyle(fontSize: 12)),
            ]);
          },
        ),
        const SizedBox(height: 10),
        const Text('এ মাসের অবস্থা', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        FutureBuilder<Calc>(
          future: f,
          builder: (c, s) {
            if (s.hasError) return const Padding(padding: EdgeInsets.all(12), child: Text('হিসাব লোড হয়নি (নেট দেখুন, নিচে টেনে রিফ্রেশ করুন)'));
            if (!s.hasData) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
            final k = s.data!;
            final b = k.bal(Me.uid);
            final mine = Me.role != 'owner' && k.act.contains(Me.uid);
            return Column(children: [
              Row(children: [
                Stat('মোট মিল', bn(k.total), Icons.restaurant),
                if (k.fixedMode) ...[Stat('মোট মিল চার্জ', taka(k.totalCharge), Icons.payments), Stat('অতিরিক্ত/জন', taka(k.extraShare), Icons.soup_kitchen)]
                else ...[Stat('মিল রেট', bn(k.rate.toStringAsFixed(2)), Icons.percent), Stat('মোট বাজার', taka(k.market), Icons.shopping_basket)],
              ]),
              if (mine) Container(
                margin: const EdgeInsets.only(top: 6, bottom: 2),
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(colors: k.netDue(Me.uid) > 0.5 ? const [Color(0xFFC62828), Color(0xFFEF5350)] : const [Color(0xFF2E7D32), Color(0xFF66BB6A)]),
                ),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k.netDue(Me.uid).abs() < 0.5 ? 'আপনার কোনো বাকি নেই' : k.netDue(Me.uid) > 0 ? 'এ মাসে আপনার দেওয়ার বাকি' : 'এ মাসে আপনি পাবেন', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(taka(k.netDue(Me.uid).abs()), style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold)),
                  ])),
                  IconButton(tooltip: 'হোয়াটসঅ্যাপে শেয়ার', icon: const Icon(Icons.share, color: Colors.white), onPressed: () => openUrl('https://wa.me/?text=${Uri.encodeComponent(statementText(k, Me.uid))}')),
                ]),
              ),
              if (mine) Card(
                color: b >= 0 ? Colors.green.withOpacity(.15) : Colors.red.withOpacity(.15),
                child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('আমার হিসাব', style: Theme.of(c).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('আমার মিল: ${bn(k.mc[Me.uid] ?? 0)}'), Text('মিল খরচ: ${taka(k.cost(Me.uid))}')]),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('আমার জমা: ${taka((k.dep[Me.uid] ?? 0) + (k.prev[Me.uid] ?? 0))}'), Text('${b >= 0 ? 'পাওনা' : 'দেনা'}: ${taka(b.abs())}', style: TextStyle(fontWeight: FontWeight.bold, color: b >= 0 ? Colors.green.shade700 : Colors.red.shade700))]),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('আমার চাল: ${bn(k.riceCost(Me.uid).toStringAsFixed(2))} কেজি'), Text('${k.riceBal(Me.uid) >= 0 ? 'চাল বাকি' : 'চাল ঘাটতি'}: ${bn(k.riceBal(Me.uid).abs().toStringAsFixed(2))} কেজি')]),
                  const Divider(),
                  Text('মাস শেষে মোট ${k.netDue(Me.uid) >= 0 ? 'দিতে হবে' : 'পাবেন'}: ${taka(k.netDue(Me.uid).abs())}  (তহবিলের বাকি চাঁদা ও ভাড়া সহ)', style: const TextStyle(fontSize: 12)),
                ])),
              ),
              if (Me.meal && k.pendingMarket > 0) Card(color: Colors.amber.shade100, child: ListTile(leading: const Icon(Icons.pending_actions, color: Colors.black87), title: Text('অনুমোদনের অপেক্ষায় বাজার: ${taka(k.pendingMarket)}', style: const TextStyle(color: Colors.black87)), subtitle: const Text('এন্ট্রি ট্যাবে গিয়ে অনুমোদন দিন', style: TextStyle(color: Colors.black54)))),
            ]);
          },
        ),
        if (Me.mon) StreamBuilder<DatabaseEvent>(
          stream: db.ref('messes/$mid/members').onValue,
          builder: (c, s) {
            if (!s.hasData || m(s.data!.snapshot.value).length > 1) return const SizedBox();
            return Card(
              color: cs.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.person_add),
                title: const Text('সদস্য যোগ করুন'),
                subtitle: const Text('নাম, মোবাইল ও পাসওয়ার্ড দিয়ে সদস্যদের যোগ করুন'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const MembersPage())),
              ),
            );
          },
        ),
        if (Me.mon) ...[
          const SizedBox(height: 14),
          const Text('কাজ বেছে নিন', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const MonitorHome(),
        ],
        const SizedBox(height: 10),
        Card(
          child: Padding(padding: const EdgeInsets.all(8), child: Row(children: [
            action(Icons.shopping_cart, 'বাজারের তালিকা', () => Navigator.push(c, MaterialPageRoute(builder: (_) => const BazarListPage()))),
            action(Icons.picture_as_pdf, 'মাসের PDF', () async { try { await sharePdf(await Calc.load(ym)); } catch (e) { if (c.mounted) snack(c, 'PDF হয়নি, নেট দেখুন'); } }),
            if (Me.role != 'owner') action(Icons.share, 'আমার হিসাব শেয়ার', () async {
              try {
                final k = await Calc.load(ym);
                await openUrl('https://wa.me/?text=${Uri.encodeComponent(statementText(k, Me.uid))}');
              } catch (e) { if (c.mounted) snack(c, 'হয়নি, নেট দেখুন'); }
            }),
            action(Icons.send, 'যোগাযোগ', () => openUrl(telegram)),
          ])),
        ),
        Center(child: footer()),
      ]),
    );
  }
}

/// মনিটরের প্রথম পেজ: কোনো হিসাব/এন্ট্রি আপনা-আপনি আসে না, বাছলে তবেই খোলে
class MonitorHome extends StatelessWidget {
  const MonitorHome({super.key});
  Widget tile(BuildContext c, IconData ic, String t, Color col, VoidCallback go) => InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: go,
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: col.withOpacity(.16)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircleAvatar(radius: 26, backgroundColor: col, child: Icon(ic, color: Colors.white, size: 28)),
          const SizedBox(height: 8),
          Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      ));

  void page(BuildContext c, String title, Widget body) =>
      Navigator.push(c, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: SafeArea(child: Column(children: [const OfflineBanner(), Expanded(child: body)])))));
  void led(BuildContext c, String title, List<String> only) =>
      Navigator.push(c, MaterialPageRoute(builder: (_) => Scaffold(body: SafeArea(child: Column(children: [const OfflineBanner(), Expanded(child: LedgerPage(only: only, title: title))])))));

  @override
  Widget build(BuildContext c) {
    const st = SettingsPage();
    final items = <List<Object>>[
      [Icons.restaurant, 'মিল', const Color(0xFF00897B), () => page(c, 'মিল', const MealPage())],
      [Icons.savings, 'টাকা জমা', const Color(0xFF43A047), () => led(c, 'টাকা জমা', ['deposit', 'rice'])],
      [Icons.shopping_basket, 'বাজার', const Color(0xFFEF6C00), () => led(c, 'বাজার', ['market'])],
      [Icons.soup_kitchen, 'মশলা ও অতিরিক্ত', const Color(0xFFD84315), () => led(c, 'মশলা ও অতিরিক্ত', ['extra', 'rice_extra', 'x_in', 'x_out'])],
      [Icons.tune, 'মিল চার্জ নিয়ম', const Color(0xFF3949AB), () => st.mealRules(c)],
      [Icons.receipt_long, 'বিল', const Color(0xFF3949AB), () => led(c, 'বিল', ['bill_in', 'bill'])],
      [Icons.local_fire_department, 'জ্বালানি', const Color(0xFFE53935), () => led(c, 'জ্বালানি', ['fuel_in', 'fuel'])],
      [Icons.construction, 'উন্নয়ন', const Color(0xFF6D4C41), () => led(c, 'উন্নয়ন', ['dev_in', 'dev'])],
      [Icons.home, 'ভাড়া ও মালিক', const Color(0xFF8E24AA), () => led(c, 'ভাড়া ও মালিক', ['rent', 'advance', 'owner'])],
      [Icons.bar_chart, 'রিপোর্ট', const Color(0xFF00ACC1), () => page(c, 'রিপোর্ট', const ReportPage())],
      [Icons.group, 'সদস্য', const Color(0xFF1E88E5), () => Navigator.push(c, MaterialPageRoute(builder: (_) => const MembersPage()))],
      [Icons.shopping_cart, 'বাজারের তালিকা', const Color(0xFFFB8C00), () => Navigator.push(c, MaterialPageRoute(builder: (_) => const BazarListPage()))],
      [Icons.campaign, 'নোটিশ', const Color(0xFFFFB300), () => st.notice(c)],
      [Icons.forum, 'অনুরোধ', const Color(0xFF00897B), () => Navigator.push(c, MaterialPageRoute(builder: (_) => const RequestsPage()))],
      [Icons.lock_clock, 'মাস ক্লোজ', const Color(0xFF546E7A), () => st.closeMonth(c)],
      [Icons.settings, 'সেটিংস', const Color(0xFF757575), () => page(c, 'সেটিংস', const SettingsPage())],
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      padding: const EdgeInsets.symmetric(vertical: 8),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: .95,
      children: [for (final i in items) tile(c, i[0] as IconData, i[1] as String, i[2] as Color, i[3] as VoidCallback)],
    );
  }
}
