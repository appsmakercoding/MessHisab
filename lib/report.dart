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
  final Map<String, int> mc = {};
  final Map<String, double> dep = {}, rice = {}, prev = {}, rentPaid = {}, adv = {}, bin = {}, fin = {}, din = {};
  int total = 0;
  double market = 0, pendingMarket = 0, bill = 0, fuel = 0, dev = 0, ownerPaid = 0, rentDue = 0;
  Map<String, double> prevFund = {'bill': 0, 'fuel': 0, 'dev': 0};
  List<Map> expenses = [];
  Calc(this.ym, this.members, this.act);

  double get rate => total > 0 ? market / total : 0;
  double cost(String u) => (mc[u] ?? 0) * rate;
  double bal(String u) => (prev[u] ?? 0) + (dep[u] ?? 0) - cost(u); // + = পাওনা, - = দেনা
  double share(double out) => act.isEmpty ? 0 : out / act.length;
  double billDue(String u) => share(bill) - (bin[u] ?? 0);
  double fuelDue(String u) => share(fuel) - (fin[u] ?? 0);
  double rentOf(String u) => dn(m(members[u])['rent']);
  double rentDueOf(String u) => rentOf(u) - (rentPaid[u] ?? 0);
  String nm(String u) => '${m(members[u])['name'] ?? '-'}';
  /// মাস শেষে এই সদস্যের মোট দেনা (+) / পাওনা (-) — ভাড়া, বিল, জ্বালানি সহ
  double netDue(String u) => -bal(u) + billDue(u) + fuelDue(u) + rentDueOf(u);
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
    ]);
    final ms = m(r[0].value);
    final act = [for (final e in ms.entries) if (m(e.value)['active'] != false && m(e.value)['role'] != 'owner') '${e.key}'];
    final c = Calc(ym, ms, act);
    m(r[1].value).forEach((day, x) => m(x).forEach((u, v) {
          final k = n(m(v)['b']) + n(m(v)['l']) + n(m(v)['d']) + n(m(v)['g']);
          c.mc['$u'] = (c.mc['$u'] ?? 0) + k;
          c.total += k;
        }));
    final ps = m(r[3].value);
    m(ps['bal']).forEach((u, v) => c.prev['$u'] = dn(v));
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
          if (pending) { c.pendingMarket += a; } else { c.market += a; c.expenses.add(e); }
          break;
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
  final meal = Rpt('মিল হিসাব', ['মোট মিল: ${bn(c.total)}', 'মোট বাজার: ${taka(c.market)}', 'মিল রেট: ${bn(c.rate.toStringAsFixed(2))}', if (c.pendingMarket > 0) 'অনুমোদনের অপেক্ষায় বাজার: ${taka(c.pendingMarket)} (হিসাবে ধরা হয়নি)'],
      ['নাম', 'মিল', 'আগের', 'জমা', 'খরচ', 'পাওনা(+)/দেনা(-)'],
      [for (final u in act) [c.nm(u), bn(c.mc[u] ?? 0), s(c.prev[u] ?? 0), s(c.dep[u] ?? 0), s(c.cost(u)), s(c.bal(u))].map((x) => bn(x)).toList()], act);

  Rpt fund(String title, String k, Map<String, double> inn, double out, bool sh) {
    final tin = inn.values.fold(0.0, (a, b) => a + b);
    return Rpt(title, [
      'এ মাসে জমা: ${taka(tin)}', 'এ মাসের খরচ: ${taka(out)}', 'মোট অবশিষ্ট (আগের সহ): ${taka(c.fundLeft(k, tin, out))}',
      if (sh) 'জনপ্রতি ভাগ: ${bn(c.share(out).toStringAsFixed(1))}',
      if (c.expenses.any((e) => e['type'] == k)) '— খরচের তালিকা —',
      for (final e in c.expenses.where((e) => e['type'] == k)) '${bn(e['date'])} ${e['note'] ?? ''}: ${bn(e['amount'])}',
    ], sh ? ['নাম', 'দিয়েছে', 'ভাগ', 'বাকি'] : ['নাম', 'দিয়েছে'],
        [for (final u in act) [c.nm(u), s(inn[u] ?? 0), if (sh) ...[s(c.share(out)), s(c.share(out) - (inn[u] ?? 0))]].map((x) => bn(x)).toList()], act);
  }

  final rent = Rpt('ভাড়া / অগ্রিম / মালিক', [
    'মোট ধার্য ভাড়া: ${taka(c.rentDue)}', 'এ মাসে ভাড়া জমা: ${taka(c.rentPaid.values.fold(0.0, (a, b) => a + b))}',
    'মালিককে পরিশোধ (এ মাস): ${taka(c.ownerPaid)}',
  ], ['নাম', 'ধার্য', 'জমা', 'বাকি', 'অগ্রিম'],
      [for (final u in act) [c.nm(u), s(c.rentOf(u)), s(c.rentPaid[u] ?? 0), s(c.rentDueOf(u)), s(c.adv[u] ?? 0)].map((x) => bn(x)).toList()], act);

  final net = Rpt('সবার চূড়ান্ত হিসাব', ['ধনাত্মক = সদস্য দেবে, ঋণাত্মক = সদস্য পাবে', '(মিল + বিল + জ্বালানি + ভাড়া মিলিয়ে)'],
      ['নাম', 'মিল', 'বিল', 'জ্বালানি', 'ভাড়া', 'মোট দিতে হবে'],
      [for (final u in act) [c.nm(u), s(-c.bal(u)), s(c.billDue(u)), s(c.fuelDue(u)), s(c.rentDueOf(u)), s(c.netDue(u))].map((x) => bn(x)).toList()], act);

  final all = Rpt('মেসের সার্বিক অবস্থা', [
    'সদস্য: ${bn(act.length)}', 'মোট মিল: ${bn(c.total)}', 'মিল রেট: ${bn(c.rate.toStringAsFixed(2))}',
    'টাকা জমা (মিল): ${taka(c.dep.values.fold(0.0, (a, b) => a + b))}', 'বাজার খরচ: ${taka(c.market)}',
    'বিল খরচ: ${taka(c.bill)}   জ্বালানি খরচ: ${taka(c.fuel)}   উন্নয়ন খরচ: ${taka(c.dev)}',
    'ভাড়া ধার্য/জমা: ${taka(c.rentDue)} / ${taka(c.rentPaid.values.fold(0.0, (a, b) => a + b))}',
  ], [], [], []);
  return {
    if (Me.role != 'boarder') 'all': all,
    'meal': meal,
    'net': net,
    'bill': fund('বিল হিসাব', 'bill', c.bin, c.bill, true),
    'fuel': fund('উড/গ্যাস হিসাব', 'fuel', c.fin, c.fuel, true),
    'dev': fund('উন্নয়ন হিসাব', 'dev', c.din, c.dev, false),
    'rent': rent,
  };
}

/// একজন সদস্যের স্টেটমেন্ট (টেক্সট — হোয়াটসঅ্যাপে পাঠানোর জন্য)
String statementText(Calc c, String u) {
  String s(double v) => bn(v.toStringAsFixed(0));
  final b = c.bal(u), nd = c.netDue(u);
  return '''মেস হিসাব — ${monthLabelYm(c.ym)}
নাম: ${c.nm(u)}
মিল: ${bn(c.mc[u] ?? 0)}  | রেট: ${bn(c.rate.toStringAsFixed(2))}
মিল খরচ: ${s(c.cost(u))}  | জমা: ${s(c.dep[u] ?? 0)}  | আগের: ${s(c.prev[u] ?? 0)}
মিল ${b >= 0 ? 'পাওনা' : 'দেনা'}: ${s(b.abs())}
বিল বাকি: ${s(c.billDue(u))}  | জ্বালানি বাকি: ${s(c.fuelDue(u))}  | ভাড়া বাকি: ${s(c.rentDueOf(u))}
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

class _ReportState extends State<ReportPage> {
  DateTime mo = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String cat = 'meal';
  late Future<Calc> f;
  String get ym => ymOf(mo);
  @override
  void initState() { super.initState(); f = Calc.load(ym); }
  void go(int k) => setState(() { mo = DateTime(mo.year, mo.month + k, 1); f = Calc.load(ym); });

  @override
  Widget build(BuildContext c) => FutureBuilder<Calc>(
        future: f,
        builder: (c, s) {
          if (s.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('লোড হয়নি। নেট দেখুন।\n${s.error}', textAlign: TextAlign.center)));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final calc = s.data!;
          final r = buildReports(calc);
          if (!r.containsKey(cat)) cat = r.keys.first;
          final x = r[cat]!;
          const label = {'all': 'সার্বিক অবস্থা', 'meal': 'মিল', 'net': 'চূড়ান্ত হিসাব', 'bill': 'বিল', 'fuel': 'উড/গ্যাস', 'dev': 'উন্নয়ন', 'rent': 'ভাড়া/মালিক'};
          return RefreshIndicator(
            onRefresh: () async { setState(() => f = Calc.load(ym)); await f; },
            child: ListView(padding: const EdgeInsets.all(12), children: [
              MonthBar(mo, go, trailing: Wrap(spacing: 4, children: [
                IconButton.filledTonal(tooltip: 'মাসের PDF', onPressed: () => sharePdf(calc), icon: const Icon(Icons.picture_as_pdf)),
                if (Me.role == 'boarder') IconButton.filledTonal(tooltip: 'আমার স্টেটমেন্ট', onPressed: () => sharePdf(calc, only: Me.uid), icon: const Icon(Icons.person)),
              ])),
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                for (final k in r.keys) Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(label[k]!), selected: cat == k, onSelected: (_) => setState(() => cat = k))),
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
