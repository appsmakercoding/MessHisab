import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
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
  db.setPersistenceEnabled(true);
  runApp(const MessApp());
}

class MessApp extends StatelessWidget {
  const MessApp({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'মেস হিসাব',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF00897B)),
        home: StreamBuilder<User?>(
            stream: auth.authStateChanges(),
            builder: (c, s) => s.connectionState == ConnectionState.waiting
                ? const Scaffold(body: Center(child: CircularProgressIndicator()))
                : s.data == null ? const LoginPage() : Gate(s.data!.uid)),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginState();
}

class _LoginState extends State<LoginPage> {
  final nm = TextEditingController(), ph = TextEditingController(), ps = TextEditingController();
  bool reg = false, busy = false;
  Future<void> go() async {
    setState(() => busy = true);
    try {
      if (reg) {
        final u = (await auth.createUserWithEmailAndPassword(email: em(ph.text), password: ps.text)).user!.uid;
        final name = nm.text.trim();
        await db.ref('users/$u').set({'messId': u, 'role': 'monitor', 'name': name, 'active': true});
        await db.ref('messes/$u/members/$u').set({'name': name, 'role': 'monitor', 'phone': ph.text.trim(), 'active': true, 'rent': 0});
        await db.ref('licenses/$u').set({'active': false, 'maxBoarders': 100});
      } else {
        await auth.signInWithEmailAndPassword(email: em(ph.text), password: ps.text);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) snack(context, e.message ?? 'ত্রুটি');
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                logo(s: 96),
                const SizedBox(height: 12),
                const Text('মেস হিসাব', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                if (reg) TextField(controller: nm, decoration: const InputDecoration(labelText: 'নাম', border: OutlineInputBorder())),
                if (reg) const SizedBox(height: 12),
                TextField(controller: ph, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'মোবাইল নম্বর', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: ps, obscureText: true, decoration: const InputDecoration(labelText: 'পাসওয়ার্ড (কমপক্ষে ৬)', border: OutlineInputBorder())),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: busy ? null : go, child: Text(reg ? 'মনিটর হিসেবে রেজিস্টার' : 'লগইন'))),
                TextButton(onPressed: () => setState(() => reg = !reg), child: Text(reg ? 'অ্যাকাউন্ট আছে? লগইন' : 'নতুন মেস? রেজিস্টার করুন')),
                footer(),
              ]),
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
              FilledButton.icon(onPressed: () => launchUrl(Uri.parse(telegram), mode: LaunchMode.externalApplication), icon: const Icon(Icons.send), label: const Text('টেলিগ্রামে যোগাযোগ $telegramName')),
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

class _ShellState extends State<Shell> {
  int i = 0;
  @override
  Widget build(BuildContext c) {
    Me.uid = widget.uid; Me.mid = widget.mid; Me.role = '${widget.p['role']}'; Me.name = '${widget.p['name']}'; Me.lic = widget.l;
    final pages = <Widget>[const HomePage(), const MealPage(), const LedgerPage(), const ReportPage(), const SettingsPage()];
    return Scaffold(
      body: SafeArea(child: pages[i]),
      bottomNavigationBar: NavigationBar(selectedIndex: i, onDestinationSelected: (v) => setState(() => i = v), destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: 'হোম'),
        NavigationDestination(icon: Icon(Icons.restaurant), label: 'মিল'),
        NavigationDestination(icon: Icon(Icons.receipt_long), label: 'এন্ট্রি'),
        NavigationDestination(icon: Icon(Icons.bar_chart), label: 'রিপোর্ট'),
        NavigationDestination(icon: Icon(Icons.settings), label: 'সেটিংস'),
      ]),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  Widget box(String t, String v, IconData ic) => Expanded(
      child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [Icon(ic, color: const Color(0xFF00897B)), Text(v, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)), Text(t, textAlign: TextAlign.center)]))));
  @override
  Widget build(BuildContext c) {
    final mid = Me.mid;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [logo(s: 48), const SizedBox(width: 12), const Text('মেস হিসাব', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))]),
      StreamBuilder<DatabaseEvent>(
        stream: db.ref('messes/$mid/notice').onValue,
        builder: (c, s) {
          final t = '${s.data?.snapshot.value ?? ''}';
          return t.isEmpty ? const SizedBox() : Card(color: Colors.amber.shade100, child: ListTile(leading: const Icon(Icons.campaign), title: Text(t)));
        },
      ),
      const SizedBox(height: 8),
      Text('আজকের মিল (${today()})', style: const TextStyle(fontSize: 16)),
      StreamBuilder<DatabaseEvent>(
        stream: db.ref('messes/$mid/meals/${today()}').onValue,
        builder: (c, s) {
          int b = 0, l = 0, d = 0;
          m(s.data?.snapshot.value).forEach((k, v) { b += n(m(v)['b']); l += n(m(v)['l']); d += n(m(v)['d']); });
          return Row(children: [box('সকাল', '$b', Icons.wb_twilight), box('দুপুর', '$l', Icons.wb_sunny), box('রাত', '$d', Icons.nights_stay)]);
        },
      ),
      StreamBuilder<DatabaseEvent>(
        stream: db.ref('messes/$mid/entries').orderByChild('date').equalTo(today()).onValue,
        builder: (c, s) {
          double t = 0;
          m(s.data?.snapshot.value).forEach((k, v) { if (expenseTypes.contains(m(v)['type'])) t += dn(m(v)['amount']); });
          return Row(children: [box('আজকের মোট খরচ (টাকা)', t.toStringAsFixed(0), Icons.payments)]);
        },
      ),
      Center(child: footer()),
    ]);
  }
}
