import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';

final db = FirebaseDatabase.instance;
final auth = FirebaseAuth.instance;

const teal = Color(0xFF00897B);

class Me {
  static String uid = '', mid = '', role = '', name = '';
  static Map lic = {};
  static bool get mon => role == 'monitor';
  static bool get meal => role == 'monitor' || role == 'meal';
}

/// ব্যবহারকারীর সেটিংস (ফোনেই থাকে, ফায়ারবেসে কিছু লাগে না)
class Prefs {
  static final theme = ValueNotifier<ThemeMode>(ThemeMode.system);
  static final bnDigits = ValueNotifier<bool>(false);
  static SharedPreferences? _p;
  static Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
      final t = _p!.getString('theme') ?? 'system';
      theme.value = t == 'dark' ? ThemeMode.dark : t == 'light' ? ThemeMode.light : ThemeMode.system;
      bnDigits.value = _p!.getBool('bn') ?? false;
    } catch (_) {}
  }
  static Future<void> setTheme(ThemeMode t) async {
    theme.value = t;
    try { await _p?.setString('theme', t == ThemeMode.dark ? 'dark' : t == ThemeMode.light ? 'light' : 'system'); } catch (_) {}
  }
  static Future<void> setBn(bool v) async {
    bnDigits.value = v;
    try { await _p?.setBool('bn', v); } catch (_) {}
  }
}

String bn(Object? v) {
  final s = '$v';
  if (!Prefs.bnDigits.value) return s;
  const b = '০১২৩৪৫৬৭৮৯';
  return s.replaceAllMapped(RegExp(r'[0-9]'), (x) => b[int.parse(x[0]!)]);
}

String em(String p) => '${p.replaceAll(RegExp(r'\s'), '')}@mess.app';
String ymd(DateTime d) => d.toIso8601String().substring(0, 10);
String ymOf(DateTime d) => ymd(d).substring(0, 7);
String today() => ymd(DateTime.now());
Map m(Object? v) => v is Map ? v : {};
int n(Object? v) => (v as num?)?.toInt() ?? 0;
double dn(Object? v) => (v as num?)?.toDouble() ?? 0;
String f0(double v) => bn(v.toStringAsFixed(0));
String taka(double v) => '৳${f0(v)}';

const monthNames = ['জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'];
String monthLabel(DateTime d) => '${monthNames[d.month - 1]} ${bn(d.year)}';
String monthLabelYm(String ym) => monthLabel(DateTime(int.parse(ym.substring(0, 4)), int.parse(ym.substring(5, 7)), 1));

void snack(BuildContext c, String t) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t)));
Future<void> safe(BuildContext c, Future<void> Function() f) async {
  try { await f(); } catch (e) { if (c.mounted) snack(c, 'অনুমতি নেই, মাস বন্ধ আছে, বা ইন্টারনেট সমস্যা'); }
}

const roles = {
  'monitor': 'মনিটর', 'meal': 'মিল ম্যানেজার', 'bazari': 'বাজারি', 'bills': 'বিল ম্যানেজার',
  'fuel': 'উড/গ্যাস ম্যানেজার', 'dev': 'উন্নয়ন ম্যানেজার', 'boarder': 'বর্ডার', 'owner': 'বাড়িওয়ালা (শুধু দেখা)',
};
const types = {
  'deposit': 'টাকা জমা', 'rice': 'চাল জমা (কেজি)', 'market': 'বাজার খরচ',
  'bill_in': 'বিল জমা', 'bill': 'বিল খরচ', 'fuel_in': 'জ্বালানি জমা', 'fuel': 'জ্বালানি খরচ',
  'dev_in': 'উন্নয়ন জমা', 'dev': 'উন্নয়ন খরচ', 'rent': 'বাড়িভাড়া জমা', 'advance': 'অগ্রিম জমা', 'owner': 'মালিককে পরিশোধ',
};
const typeIcons = {
  'deposit': Icons.savings, 'rice': Icons.rice_bowl, 'market': Icons.shopping_basket, 'bill_in': Icons.receipt, 'bill': Icons.receipt_long,
  'fuel_in': Icons.local_fire_department, 'fuel': Icons.local_fire_department, 'dev_in': Icons.construction, 'dev': Icons.construction,
  'rent': Icons.home, 'advance': Icons.account_balance_wallet, 'owner': Icons.outbox,
};
const canEnter = {
  'monitor': ['deposit', 'rice', 'market', 'bill_in', 'bill', 'fuel_in', 'fuel', 'dev_in', 'dev', 'rent', 'advance', 'owner'],
  'meal': ['deposit', 'rice', 'market'], 'bazari': ['market'], 'bills': ['bill_in', 'bill'], 'fuel': ['fuel_in', 'fuel'], 'dev': ['dev_in', 'dev'],
  'boarder': <String>[], 'owner': <String>[],
};
const expenseTypes = ['market', 'bill', 'fuel', 'dev'];
const needWho = ['deposit', 'rice', 'bill_in', 'fuel_in', 'dev_in', 'rent', 'advance'];

Future<void> audit(String act) => db.ref('messes/${Me.mid}/audit').push().set({'by': Me.name, 'act': act, 'ts': ServerValue.timestamp});

Future<bool> confirm(BuildContext c, String t) async =>
    await showDialog<bool>(context: c, builder: (d) => AlertDialog(title: Text(t), actions: [
      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('না')),
      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('হ্যাঁ')),
    ])) ?? false;

Future<void> openUrl(String u) => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication).then((_) {}, onError: (_) {});

Widget footer() => TextButton(onPressed: () => openUrl(telegram), child: const Text(brand, style: TextStyle(fontSize: 12)));

Widget logo({double s = 80}) => Container(
    width: s, height: s,
    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF00897B), Color(0xFF26A69A)])),
    child: Icon(Icons.restaurant_menu, color: Colors.white, size: s * .5));

class Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const Empty(this.icon, this.text, {super.key});
  @override
  Widget build(BuildContext c) => Center(
      child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 56, color: Theme.of(c).colorScheme.outline),
        const SizedBox(height: 8),
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(c).colorScheme.outline)),
      ])));
}

class Stat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color? color;
  const Stat(this.label, this.value, this.icon, {this.color, super.key});
  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return Expanded(
        child: Card(
            elevation: 0,
            color: cs.surfaceContainerHighest.withOpacity(.55),
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Column(children: [
                  Icon(icon, color: color ?? cs.primary),
                  const SizedBox(height: 4),
                  FittedBox(child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                  Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                ]))));
  }
}

/// মাস নেভিগেটর (< মাস >)
class MonthBar extends StatelessWidget {
  final DateTime mo;
  final void Function(int) go;
  final Widget? trailing;
  const MonthBar(this.mo, this.go, {this.trailing, super.key});
  @override
  Widget build(BuildContext c) => Row(children: [
        IconButton(onPressed: () => go(-1), icon: const Icon(Icons.chevron_left)),
        Text(monthLabel(mo), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        IconButton(onPressed: () => go(1), icon: const Icon(Icons.chevron_right)),
        const Spacer(),
        if (trailing != null) trailing!,
      ]);
}

/// অফলাইন হলে উপরে হলুদ ব্যানার
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});
  @override
  Widget build(BuildContext c) => StreamBuilder<DatabaseEvent>(
      stream: db.ref('.info/connected').onValue,
      builder: (c, s) {
        if (s.data?.snapshot.value != false) return const SizedBox();
        return Container(
            width: double.infinity, color: Colors.amber.shade200, padding: const EdgeInsets.symmetric(vertical: 4),
            child: const Text('ইন্টারনেট নেই — সেভ করা তথ্য দেখাচ্ছে, নেট এলে আপডেট হবে', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black87)));
      });
}
