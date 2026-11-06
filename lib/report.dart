import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'common.dart';
import 'config.dart';

/// এক মাসের সব হিসাব একসাথে (হোম, রিপোর্ট, মাস ক্লোজ — সবাই এটাই ব্যবহার করে)
class Calc {
  final String ym;
  final Map members;
  final List<String> act; // সক্রিয় সদস্য (বাড়িওয়ালা বাদে)
  final Map<String, int> mc = {}, mb = {}, ml = {}, md = {}, mg = {};
  final Map<String, double> dep = {}, rice = {}, prev = {}, prevRice = {}, rentPaid = {}, adv = {}, bin = {}, fin = {}, din = {};
  int total = 0;
  double mGiven = 0, mSpentG = 0; // বাজারির হাতে দেওয়া টাকা ও তার খরচ
  double market = 0, pendingMarket = 0, bill = 0, fuel = 0, dev = 0, ownerPaid = 0, rentDue = 0;
  double extra = 0, xIn = 0, xOut = 0, riceExtra = 0;
  bool fixedMode = true; // true = মিটিংয়ে ঠিক করা ফিক্সড মিল চার্জ; false = বাজার ÷ মিল রেট
  Map<String, double> price = {'b': 0, 'l': 0, 'd': 0}; // প্রতি মিলের চার্জ (টাকা)
  Map<String, double> grams = {'b': 100, 'l': 250, 'd': 150}; // প্রতি মিলে চাল (গ্রাম)
  Map<String, double> prevFund = {'bill': 0, 'fuel': 0, 'dev': 0};
  Map<String, double> fixed = {'bill': 0, 'fuel': 0, 'dev': 0}; // জনপ্রতি মাসিক চাঁদা (মনিটর ঠিক করে)
  List<Map> expenses = [];
  Calc(this.ym, this.members, this.act);

  double get rate => total > 0 ? market / total : 0;
  /// মাসের অতিরিক্ত পুল: মশলা + খুচরা খরচ − অন্য আয়; সবার মধ্যে সমান ভাগ
  double get extraPool => extra + xOut - xIn;
  double get extraShare => act.isEmpty ? 0 : extraPool / act.length;
  double get riceExtraShare => act.isEmpty ? 0 : riceExtra / act.length;
  double baseCost(String u) => fixedMode
      ? (mb[u] ?? 0) * price['b']! + (ml[u] ?? 0) * price['l']! + (md[u] ?? 0) * price['d']! + (mg[u] ?? 0) * price['l']!
      : (mc[u] ?? 0) * rate;
  double cost(String u) => baseCost(u) + (fixedMode ? extraShare : 0);
  double get totalCharge => act.fold(0.0, (a, u) => a + cost(u));
  double bal(String u) => (prev[u] ?? 0) + (dep[u] ?? 0) - cost(u); // + = পাওনা, - = দেনা
  /// চাল (কেজি): মিল × গ্রাম + অতিরিক্ত চালের ভাগ
  double riceUsed(String u) => ((mb[u] ?? 0) * grams['b']! + (ml[u] ?? 0) * grams['l']! + (md[u] ?? 0) * grams['d']! + (mg[u] ?? 0) * grams['l']!) / 1000;
  double riceCost(String u) => riceUsed(u) + riceExtraShare;
  double riceBal(String u) => (prevRice[u] ?? 0) + (rice[u] ?? 0) - riceCost(u);
  double dueOf(String k, Map<String, double> inn, String u) { final v = (fixed[k] ?? 0) - (inn[u] ?? 0); return v > 0 ? v : 0.0; }
  double billDue(String u) => dueOf('bill', bin, u);
  double fuelDue(String u) => dueOf('fuel', fin, u);
  double devDue(String u) => dueOf('dev', din, u);
  double rentOf(String u) => dn(m(members[u])['rent']);
  double rentDueOf(String u) => rentOf(u) - (rentPaid[u] ?? 0);
  String nm(String u) => '${m(members[u])['name'] ?? '-'}';
  /// মাস শেষে এই সদস্যের মোট দেনা (+) / পাওনা (-) — মিল, তহবিলের বাকি চাঁদা ও ভাড়া সহ
  double netDue(String u) => -bal(u) + billDue(u) + fuelDue(u) + devDue(u) + rentDueOf(u);
  double fundLeft(String k, double inn, double out) => (prevFund[k] ?? 0) + inn - out;

  static Future<Calc> load(String ym) async {
    final mid = Me.mid;
    final d = DateTime(int.parse(ym.substring(0, 4)), int.parse(ym.substring(5, 7)), 1);
    final pym = ymOf(DateTime(d.year, d.month - 1, 1));
    final r = await Future.wait([
      db.ref('messes/$mid/members').get(),
      db.ref('messes/$mid/meals/$ym').get(),
      db.ref('messes/$mid/entries/$ym').get(),
      db.ref('messes/$mid/summary/$pym').get(),
      db.ref('messes/$mid/cfg').get(),
    ]);
    final ms = m(r[0].value);
    final act = [for (final e in ms.entries) if (m(e.value)['active'] != false && m(e.value)['role'] != 'owner') '${e.key}'];
    final c = Calc(ym, ms, act);
    final cfg = m(r[4].value);
    c.fixedMode = '${cfg['mode']}' != 'rate';
    for (final k in ['bill', 'fuel', 'dev']) { if (cfg[k] != null) c.fixed[k] = dn(cfg[k]); }
    for (final k in ['b', 'l', 'd']) {
      if (cfg['p$k'] != null) c.price[k] = dn(cfg['p$k']);
      if (cfg['r$k'] != null) c.grams[k] = dn(cfg['r$k']);
    }
    m(r[1].value).forEach((day, x) => m(x).forEach((u, v) {
          final w = m(v);
          final key = '$u';
          c.mb[key] = (c.mb[key] ?? 0) + n(w['b']);
          c.ml[key] = (c.ml[key] ?? 0) + n(w['l']);
          c.md[key] = (c.md[key] ?? 0) + n(w['d']);
          c.mg[key] = (c.mg[key] ?? 0) + n(w['g']);
          final k = n(w['b']) + n(w['l']) + n(w['d']) + n(w['g']);
          c.mc[key] = (c.mc[key] ?? 0) + k;
          c.total += k;
        }));
    final ps = m(r[3].value);
    m(ps['bal']).forEach((u, v) => c.prev['$u'] = dn(v));
    m(ps['rbal']).forEach((u, v) => c.prevRice['$u'] = dn(v));
    m(ps['fund']).forEach((k, v) => c.prevFund['$k'] = dn(v));
    void add(Map<String, double> mp, String u, double a) => mp[u] = (mp[u] ?? 0) + a;
    for (final v0 in m(r[2].value).values) {
      final e = m(v0);
      final a = dn(e['amount']), u = '${e['uid']}';
      final pending = e['st'] == 'p';
      switch (e['type']) {
        case 'deposit': if (!pending) add(c.dep, u, a); break;
        case 'rice': add(c.rice, u, a); break;
        case 'market':
          if (pending) { c.pendingMarket += a; } else {
            c.market += a; c.expenses.add(e);
            if (dn(e['given']) > 0) { c.mGiven += dn(e['given']); c.mSpentG += a; }
          }
          break;
        case 'extra': c.extra += a; break;
        case 'rice_extra': c.riceExtra += a; break;
        case 'x_in': c.xIn += a; break;
        case 'x_out': c.xOut += a; break;
        case 'bill_in': add(c.bin, u, a); break;
        case 'bill': c.bill += a; c.expenses.add(e); break;
        case 'fuel_in': add(c.fin, u, a); break;
        case 'fuel': c.fuel += a; c.expenses.add(e); break;
        case 'dev_in': add(c.din, u, a); break;
        case 'dev': c.dev += a; c.expenses.add(e); break;
        case 'rent': add(c.rentPaid, u, a); break;
        case 'advance': add(c.adv, u, a); break;
        case 'owner': c.ownerPaid += a; break;
      }
    }
    c.rentDue = c.act.fold(0.0, (s, u) => s + c.rentOf(u));
    return c;
  }
}

class Rpt {
  final String title;
  final List<String> notes, head;
  final List<List<String>> rows;
  final List<String> ids;
  Rpt(this.title, this.notes, this.head, this.rows, this.ids);
  List<List<String>> get vis => [for (var i = 0; i < rows.length; i++) if (Me.role != 'boarder' || ids[i] == Me.uid) rows[i]];
}

Map<String, Rpt> buildReports(Calc c) {
  final act = c.act;
  String s(double v) => v.toStringAsFixed(0);
  String s2(double v) => bn(v.toStringAsFixed(2));
  final unset = c.price.values.every((v) => v == 0);
  final meal = c.fixedMode
      ? Rpt('মিল হিসাব', [
          'প্রতি মিলের চার্জ: সকাল ${taka(c.price['b']!)} • দুপুর ${taka(c.price['l']!)} • রাত ${taka(c.price['d']!)}',
          if (unset) '⚠ মিল চার্জ ঠিক করা হয়নি (সেটিংস → মিল চার্জ ও চালের নিয়ম)',
          'মোট মিল: ${bn(c.total)} • মোট মিল চার্জ: ${taka(c.totalCharge)}',
          'অতিরিক্ত: মশলা ${taka(c.extra)} + খুচরা ${taka(c.xOut)} − অন্য আয় ${taka(c.xIn)} = ${taka(c.extraPool)} → জনপ্রতি ${s2(c.extraShare)}',
          if (c.mGiven > 0) 'বাজারির হাতে দেওয়া: ${taka(c.mGiven)} | খরচ: ${taka(c.mSpentG)} | ${c.mGiven >= c.mSpentG ? 'ফেরত' : 'বাজারি নিজের পকেট থেকে দিয়েছে'}: ${taka((c.mGiven - c.mSpentG).abs())}',
        ], ['নাম', 'মিল (স/দু/রা/অতিথি)', 'মিল চার্জ', 'অতিরিক্ত ভাগ', 'আগের', 'জমা', 'পাওনা(+)/দেনা(-)'],
          [for (final u in act) [c.nm(u), '${bn(c.mb[u] ?? 0)}/${bn(c.ml[u] ?? 0)}/${bn(c.md[u] ?? 0)}/${bn(c.mg[u] ?? 0)}', s(c.baseCost(u)), s(c.extraShare), s(c.prev[u] ?? 0), s(c.dep[u] ?? 0), s(c.bal(u))].map((x) => bn(x)).toList()], act)
      : Rpt('মিল হিসাব', ['মোট মিল: ${bn(c.total)}', 'মোট বাজার: ${taka(c.market)}', 'মিল রেট: ${bn(c.rate.toStringAsFixed(2))}', if (c.pendingMarket > 0) 'অনুমোদনের অপেক্ষায় বাজার: ${taka(c.pendingMarket)} (হিসাবে ধরা হয়নি)'],
          ['নাম', 'মিল', 'আগের', 'জমা', 'খরচ', 'পাওনা(+)/দেনা(-)'],
          [for (final u in act) [c.nm(u), bn(c.mc[u] ?? 0), s(c.prev[u] ?? 0), s(c.dep[u] ?? 0), s(c.cost(u)), s(c.bal(u))].map((x) => bn(x)).toList()], act);

  final riceR = Rpt('চালের হিসাব', [
    'প্রতি মিলে চাল: সকাল ${bn(c.grams['b']!.toStringAsFixed(0))} • দুপুর ${bn(c.grams['l']!.toStringAsFixed(0))} • রাত ${bn(c.grams['d']!.toStringAsFixed(0))} গ্রাম',
    'মোট অতিরিক্ত চাল: ${s2(c.riceExtra)} কেজি → জনপ্রতি ${s2(c.riceExtraShare)} কেজি',
  ], ['নাম', 'খাওয়া (কেজি)', 'অতিরিক্ত ভাগ', 'আগের', 'জমা', 'বাকি(+)/ঘাটতি(-)'],
      [for (final u in act) [c.nm(u), s2(c.riceUsed(u)), s2(c.riceExtraShare), s2(c.prevRice[u] ?? 0), s2(c.rice[u] ?? 0), s2(c.riceBal(u))]], act);

  Rpt fund(String title, String k, Map<String, double> inn, double out) {
    final tin = inn.values.fold(0.0, (a, b) => a + b);
    final fx = c.fixed[k] ?? 0;
    return Rpt(title, [
      'আগের মাসের জের: ${taka(c.prevFund[k] ?? 0)}', 'এ মাসে জমা: ${taka(tin)}', 'এ মাসের খরচ: ${taka(out)}',
      'তহবিলে অবশিষ্ট (পরের মাসে যাবে): ${taka(c.fundLeft(k, tin, out))}',
      if (fx > 0) 'জনপ্রতি নির্ধারিত চাঁদা: ${taka(fx)}',
      if (c.expenses.any((e) => e['type'] == k)) '— খরচের তালিকা —',
      for (final e in c.expenses.where((e) => e['type'] == k)) '${bn(e['date'])} ${e['note'] ?? ''}: ${bn(e['amount'])}',
    ], fx > 0 ? ['নাম', 'নির্ধারিত', 'দিয়েছে', 'বাকি'] : ['নাম', 'দিয়েছে'],
        [for (final u in act) [c.nm(u), if (fx > 0) s(fx), s(inn[u] ?? 0), if (fx > 0) s(c.dueOf(k, inn, u))].map((x) => bn(x)).toList()], act);
  }

  final rent = Rpt('ভাড়া / অগ্রিম / মালিক', [
    'মোট ধার্য ভাড়া: ${taka(c.rentDue)}', 'এ মাসে ভাড়া জমা: ${taka(c.rentPaid.values.fold(0.0, (a, b) => a + b))}',
    'মালিককে পরিশোধ (এ মাস): ${taka(c.ownerPaid)}',
  ], ['নাম', 'ধার্য', 'জমা', 'বাকি', 'অগ্রিম'],
      [for (final u in act) [c.nm(u), s(c.rentOf(u)), s(c.rentPaid[u] ?? 0), s(c.rentDueOf(u)), s(c.adv[u] ?? 0)].map((x) => bn(x)).toList()], act);

  final net = Rpt('সবার চূড়ান্ত হিসাব', ['ধনাত্মক = সদস্য দেবে, ঋণাত্মক = সদস্য পাবে', '(মিল + তহবিলের বাকি চাঁদা + ভাড়া মিলিয়ে)'],
      ['নাম', 'মিল', 'বিল', 'জ্বালানি', 'উন্নয়ন', 'ভাড়া', 'মোট দিতে হবে'],
      [for (final u in act) [c.nm(u), s(-c.bal(u)), s(c.billDue(u)), s(c.fuelDue(u)), s(c.devDue(u)), s(c.rentDueOf(u)), s(c.netDue(u))].map((x) => bn(x)).toList()], act);

  final all = Rpt('মেসের সার্বিক অবস্থা', [
    'সদস্য: ${bn(act.length)}', 'মোট মিল: ${bn(c.total)}', c.fixedMode ? 'মোট মিল চার্জ: ${taka(c.totalCharge)}' : 'মিল রেট: ${bn(c.rate.toStringAsFixed(2))}',
    'টাকা জমা (মিল): ${taka(c.dep.values.fold(0.0, (a, b) => a + b))}', 'বাজার খরচ: ${taka(c.market)}',
    'বিল খরচ: ${taka(c.bill)}   জ্বালানি খরচ: ${taka(c.fuel)}   উন্নয়ন খরচ: ${taka(c.dev)}',
    'জ্বালানি তহবিলে অবশিষ্ট: ${taka(c.fundLeft('fuel', c.fin.values.fold(0.0, (a, b) => a + b), c.fuel))}',
    'ভাড়া ধার্য/জমা: ${taka(c.rentDue)} / ${taka(c.rentPaid.values.fold(0.0, (a, b) => a + b))}',
  ], [], [], []);
  final full = {
    'all': all,
    'meal': meal,
    'rice': riceR,
    'net': net,
    'bill': fund('বিল তহবিল', 'bill', c.bin, c.bill),
    'fuel': fund('জ্বালানি তহবিল', 'fuel', c.fin, c.fuel),
    'dev': fund('উন্নয়ন তহবিল', 'dev', c.din, c.dev),
    'rent': rent,
  };
  // যার যে কাজ, সে শুধু সেই রিপোর্ট দেখবে (বর্ডার শুধু নিজের সারি দেখে)
  const see = {
    'monitor': ['all', 'meal', 'rice', 'net', 'bill', 'fuel', 'dev', 'rent'],
    'meal': ['meal', 'rice'], 'bazari': ['meal'], 'bills': ['bill'], 'fuel': ['fuel'], 'dev': ['dev'],
    'boarder': ['meal', 'rice', 'net', 'bill', 'fuel', 'dev'], 'owner': ['rent'],
  };
  final ok = see[Me.role] ?? ['meal'];
  return {for (final k in ok) k: full[k]!};
}

/// একজন সদস্যের স্টেটমেন্ট (টেক্সট — হোয়াটসঅ্যাপে পাঠানোর জন্য)
String statementText(Calc c, String u) {
  String s(double v) => bn(v.toStringAsFixed(0));
  final b = c.bal(u), nd = c.netDue(u);
  return '''মেস হিসাব — ${monthLabelYm(c.ym)}
নাম: ${c.nm(u)}
মিল: ${bn(c.mb[u] ?? 0)}/${bn(c.ml[u] ?? 0)}/${bn(c.md[u] ?? 0)}/${bn(c.mg[u] ?? 0)} (স/দু/রা/অতিথি)  ${c.fixedMode ? '| অতিরিক্ত ভাগ: ${s(c.extraShare)}' : '| রেট: ${bn(c.rate.toStringAsFixed(2))}'}
চাল: ${bn(c.riceBal(u).toStringAsFixed(2))} কেজি ${c.riceBal(u) >= 0 ? 'বাকি' : 'ঘাটতি'}
মিল খরচ: ${s(c.cost(u))}  | জমা: ${s(c.dep[u] ?? 0)}  | আগের: ${s(c.prev[u] ?? 0)}
মিল ${b >= 0 ? 'পাওনা' : 'দেনা'}: ${s(b.abs())}
বিল বাকি: ${s(c.billDue(u))}  | জ্বালানি বাকি: ${s(c.fuelDue(u))}  | উন্নয়ন বাকি: ${s(c.devDue(u))}  | ভাড়া বাকি: ${s(c.rentDueOf(u))}
${nd >= 0 ? 'মোট দিতে হবে' : 'মোট পাবেন'}: ৳${s(nd.abs())}
— $brand''';
}

Future<void> sharePdf(Calc c, {String? only}) async {
  final font = await PdfGoogleFonts.notoSansBengaliRegular();
  final doc = pw.Document();
  final r = buildReports(c);
  final list = only == null ? c.act : [only];
  doc.addPage(pw.MultiPage(
    theme: pw.ThemeData.withFont(base: font),
    build: (_) => [
      pw.Text('মেস হিসাব — ${monthLabelYm(c.ym)}', style: const pw.TextStyle(fontSize: 20)),
      if (only != null) ...[pw.SizedBox(height: 10), for (final l in statementText(c, only).split('\n')) pw.Text(l)]
      else for (final x in r.values) ...[
        pw.SizedBox(height: 12),
        pw.Text(x.title, style: const pw.TextStyle(fontSize: 16)),
        for (final t in x.notes) pw.Text(t),
        if (x.head.isNotEmpty) pw.TableHelper.fromTextArray(headers: x.head, data: x.vis),
      ],
      if (only == null && list.isNotEmpty) pw.SizedBox(height: 8),
      pw.SizedBox(height: 16),
      pw.Text(brand),
    ],
  ));
  await Printing.sharePdf(bytes: await doc.save(), filename: 'mess-${c.ym}${only == null ? '' : '-${c.nm(only)}'}.pdf');
}

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});
  @override
  State<ReportPage> createState() => _ReportState();
}

const reportLabel = {'all': 'সার্বিক অবস্থা', 'meal': 'মিল হিসাব', 'rice': 'চালের হিসাব', 'net': 'চূড়ান্ত হিসাব (কে কত দেবে)', 'bill': 'বিল তহবিল', 'fuel': 'জ্বালানি তহবিল', 'dev': 'উন্নয়ন তহবিল', 'rent': 'ভাড়া / মালিক'};

class _ReportState extends State<ReportPage> {
  DateTime mo = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String? cat = Me.mon ? null : 'meal'; // মনিটর নিজে বাছলে তবেই রিপোর্ট খোলে
  Future<Calc>? f;
  String get ym => ymOf(mo);
  @override
  void initState() { super.initState(); if (cat != null) f = Calc.load(ym); }
  void go(int k) => setState(() { mo = DateTime(mo.year, mo.month + k, 1); f = Calc.load(ym); });

  @override
  Widget build(BuildContext c) {
    if (cat == null) {
      return ListView(padding: const EdgeInsets.all(12), children: [
        const Padding(padding: EdgeInsets.all(8), child: Text('কোন রিপোর্ট দেখবেন?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        for (final e in reportLabel.entries)
          Card(child: ListTile(title: Text(e.value), trailing: const Icon(Icons.chevron_right), onTap: () => setState(() { cat = e.key; f = Calc.load(ym); }))),
      ]);
    }
    return FutureBuilder<Calc>(
        future: f,
        builder: (c, s) {
          if (s.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('লোড হয়নি। নেট দেখুন।\n${s.error}', textAlign: TextAlign.center)));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final calc = s.data!;
          final r = buildReports(calc);
          if (!r.containsKey(cat)) cat = r.keys.first;
          final x = r[cat]!;
          return RefreshIndicator(
            onRefresh: () async { setState(() => f = Calc.load(ym)); await f; },
            child: ListView(padding: const EdgeInsets.all(12), children: [
              if (Me.mon) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => cat = null), icon: const Icon(Icons.arrow_back), label: const Text('সব রিপোর্ট'))),
              MonthBar(mo, go, trailing: Wrap(spacing: 4, children: [
                IconButton.filledTonal(tooltip: 'মাসের PDF', onPressed: () => sharePdf(calc), icon: const Icon(Icons.picture_as_pdf)),
                if (Me.role == 'boarder') IconButton.filledTonal(tooltip: 'আমার স্টেটমেন্ট', onPressed: () => sharePdf(calc, only: Me.uid), icon: const Icon(Icons.person)),
              ])),
              if (!Me.mon) SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                for (final k in r.keys) Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(reportLabel[k]!), selected: cat == k, onSelected: (_) => setState(() => cat = k))),
              ])),
              const SizedBox(height: 8),
              Text(x.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              for (final t in x.notes) Padding(padding: const EdgeInsets.symmetric(vertical: 1), child: Text(t)),
              if (x.head.isNotEmpty) SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columnSpacing: 18, columns: [for (final h in x.head) DataColumn(label: Text(h))], rows: [for (final row in x.vis) DataRow(cells: [for (final v in row) DataCell(Text(v))])])),
              if (Me.mon && cat == 'net') ...[
                const SizedBox(height: 8),
                const Text('সদস্যকে হোয়াটসঅ্যাপে স্টেটমেন্ট পাঠান', style: TextStyle(fontWeight: FontWeight.w600)),
                for (final u in calc.act)
                  ListTile(dense: true, title: Text(calc.nm(u)), trailing: IconButton(icon: const Icon(Icons.send, color: Colors.green), onPressed: () {
                    var ph = '${m(calc.members[u])['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
                    if (ph.startsWith('0')) ph = '88$ph';
                    openUrl('https://wa.me/$ph?text=${Uri.encodeComponent(statementText(calc, u))}');
                  })),
              ],
              Center(child: footer()),
            ]),
          );
        },
      );
  }
}
