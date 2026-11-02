import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';

final db = FirebaseDatabase.instance;
final auth = FirebaseAuth.instance;

class Me {
  static String uid = '', mid = '', role = '', name = '';
  static Map lic = {};
}

String em(String p) => '${p.trim()}@mess.app';
String ymd(DateTime d) => d.toIso8601String().substring(0, 10);
String today() => ymd(DateTime.now());
Map m(Object? v) => v is Map ? v : {};
int n(Object? v) => (v as num?)?.toInt() ?? 0;
double dn(Object? v) => (v as num?)?.toDouble() ?? 0;
void snack(BuildContext c, String t) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t)));
Future<void> safe(BuildContext c, Future<void> Function() f) async {
  try { await f(); } catch (e) { if (c.mounted) snack(c, 'অনুমতি নেই বা মাস বন্ধ আছে'); }
}

const roles = {'monitor': 'মনিটর', 'meal': 'মিল ম্যানেজার', 'bills': 'বিল ম্যানেজার', 'fuel': 'উড/গ্যাস ম্যানেজার', 'dev': 'উন্নয়ন ম্যানেজার', 'boarder': 'বর্ডার'};
const types = {
  'deposit': 'টাকা জমা', 'rice': 'চাল জমা (কেজি)', 'market': 'বাজার খরচ',
  'bill_in': 'বিল জমা', 'bill': 'বিল খরচ', 'fuel_in': 'জ্বালানি জমা', 'fuel': 'জ্বালানি খরচ',
  'dev_in': 'উন্নয়ন জমা', 'dev': 'উন্নয়ন খরচ', 'rent': 'বাড়িভাড়া জমা', 'advance': 'অগ্রিম জমা', 'owner': 'মালিককে পরিশোধ',
};
const canEnter = {
  'monitor': ['deposit', 'rice', 'market', 'bill_in', 'bill', 'fuel_in', 'fuel', 'dev_in', 'dev', 'rent', 'advance', 'owner'],
  'meal': ['deposit', 'rice', 'market'], 'bills': ['bill_in', 'bill'], 'fuel': ['fuel_in', 'fuel'], 'dev': ['dev_in', 'dev'], 'boarder': <String>[],
};
const expenseTypes = ['market', 'bill', 'fuel', 'dev'];
const needWho = ['deposit', 'rice', 'bill_in', 'fuel_in', 'dev_in', 'rent', 'advance'];

Future<void> audit(String act) => db.ref('messes/${Me.mid}/audit').push().set({'by': Me.name, 'act': act, 'ts': ServerValue.timestamp});

Future<bool> confirm(BuildContext c, String t) async =>
    await showDialog<bool>(context: c, builder: (d) => AlertDialog(title: Text(t), actions: [
      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('না')),
      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('হ্যাঁ')),
    ])) ?? false;

Widget footer() => TextButton(
    onPressed: () => launchUrl(Uri.parse(telegram), mode: LaunchMode.externalApplication),
    child: const Text(brand, style: TextStyle(fontSize: 12)));

Widget logo({double s = 80}) => Container(
    width: s, height: s,
    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF00897B), Color(0xFF26A69A)])),
    child: Icon(Icons.restaurant_menu, color: Colors.white, size: s * .5));
