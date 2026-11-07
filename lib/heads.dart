import 'package:flutter/material.dart';
import 'common.dart';

/// বিল/খাতের ধরন: কে দেখবে ও জমা নেবে
const headCats = {'bill': 'বিল ম্যানেজার', 'fuel': 'জ্বালানি ম্যানেজার', 'dev': 'উন্নয়ন ম্যানেজার', 'monitor': 'শুধু মনিটর'};
const headModes = {'fix': 'জনপ্রতি নির্দিষ্ট টাকা', 'split': 'মোট বিল সমান ভাগ', 'rent': 'বাড়িভাড়া (সদস্যভেদে)'};
const headSuggest = ['বিদ্যুৎ বিল', 'ওয়াইফাই বিল', 'খালা বিল', 'জ্বালানি', 'উন্নয়ন', 'গ্যাস বিল', 'পানির বিল', 'বাড়িভাড়া'];

IconData headIcon(String name, String mode) {
  if (mode == 'rent' || name.contains('ভাড়া')) return Icons.home;
  if (name.contains('বিদ্যুৎ')) return Icons.bolt;
  if (name.contains('ওয়াইফাই') || name.contains('নেট')) return Icons.wifi;
  if (name.contains('জ্বালানি') || name.contains('গ্যাস')) return Icons.local_fire_department;
  if (name.contains('খালা') || name.contains('বুয়া')) return Icons.cleaning_services;
  if (name.contains('পানি')) return Icons.water_drop;
  if (name.contains('উন্নয়ন')) return Icons.construction;
  return Icons.receipt_long;
}

/// এই ব্যবহারকারী কি এই খাত পরিচালনা করতে পারবে
bool canHead(Map h) =>
    Me.mon || (h['cat'] == 'bill' && Me.role == 'bills') || (h['cat'] == 'fuel' && Me.role == 'fuel') || (h['cat'] == 'dev' && Me.role == 'dev');

/// একটি বিল/খাতের (একটি চক্রের) হিসাব
class HV {
  final String id;
  final Map h, members;
  HV(this.id, this.h, this.members);
  String get name => '${h['name']}';
  String get mode => '${h['mode']}';
  bool get closed => h['closed'] == true;
  /// যারা এই বিলে অংশীদার (ক্লোজ করলে তালিকা স্থির হয়ে যায়)
  late final List<String> part = () {
    final p = m(h['part']);
    if (p.isNotEmpty) return [for (final k in p.keys) '$k'];
    return [for (final e in members.entries) if (m(e.value)['active'] != false && m(e.value)['role'] != 'owner') '${e.key}'];
  }();
  double dueOf(String u) {
    if (!part.contains(u)) return 0;
    if (mode == 'rent') return dn(m(members[u])['rent']);
    if (mode == 'split') return part.isEmpty ? 0 : dn(h['total']) / part.length;
    return dn(h['amt']);
  }
  late final Map<String, double> paid = () {
    final r = <String, double>{};
    m(h['pay']).forEach((k, v) { final u = '${m(v)['uid']}'; r[u] = (r[u] ?? 0) + dn(m(v)['amt']); });
    return r;
  }();
  double get paidTotal => paid.values.fold(0.0, (a, b) => a + b);
  double get spent => m(h['exp']).values.fold(0.0, (a, v) => a + dn(m(v)['amt']));
  double get carry => dn(h['carry']);
  double get dueTotal => part.fold(0.0, (a, u) => a + dueOf(u));
  double get left => carry + paidTotal - spent; // হাতে আছে
  double dueLeft(String u) => dueOf(u) - (paid[u] ?? 0);
}
