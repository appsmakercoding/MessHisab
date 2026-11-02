import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'common.dart';
import 'config.dart';

class Rpt {
  final String title;
  final List<String> notes, head;
  final List<List<String>> rows;
  final List<String> ids;
  Rpt(this.title, this.notes, this.head, this.rows, this.ids);
  List<List<String>> get vis => [for (var i = 0; i < rows.length; i++) if (Me.role != 'boarder' || ids[i] == Me.uid) rows[i]];
}

Future<Map<String, Rpt>> buildReports(String ym) async {
  final mid = Me.mid;
  final res = await Future.wait([
    db.ref('messes/$mid/members').get(),
    db.ref('messes/$mid/meals').orderByKey().startAt(ym).endAt('$ym\uf8ff').get(),
    db.ref('messes/$mid/entries').get(),
  ]);
  final ms = m(res[0].value), meals = m(res[1].value);
  final es = [for (final v in m(res[2].value).values) m(v)];
  final act = [for (final e in ms.entries) if (m(e.value)['active'] != false) '${e.key}'];
  String nm(String u) => '${m(ms[u])['name'] ?? '-'}';
  bool inM(Map e) => '${e['date']}'.startsWith(ym);
  Iterable<Map> month(String t) => es.where((e) => e['type'] == t && inM(e));
  Iterable<Map> sel(String t) => es.where((e) => e['type'] == t && (inM(e) || e['open'] == true));
  Iterable<Map> allT(String t) => es.where((e) => e['type'] == t);
  double sum(Iterable<Map> l) => l.fold(0.0, (a, e) => a + dn(e['amount']));
  double byU(Iterable<Map> l, String u) => sum(l.where((e) => e['uid'] == u));
  String f0(double v) => v.toStringAsFixed(0);
  final mc = <String, int>{};
  int total = 0;
  meals.forEach((d, day) => m(day).forEach((u, v) {
        final x = n(m(v)['b']) + n(m(v)['l']) + n(m(v)['d']);
        mc['$u'] = (mc['$u'] ?? 0) + x;
        total += x;
      }));
  final mk = sum(month('market'));
  final rate = total > 0 ? mk / total : 0.0;
  final meal = Rpt('মিল হিসাব', ['মোট মিল: $total', 'মোট বাজার: ${f0(mk)}', 'মিল রেট: ${rate.toStringAsFixed(2)}'],
      ['নাম', 'মিল', 'জমা', 'চাল(কেজি)', 'খরচ', 'পাওনা(+)/দেনা(-)'],
      [for (final u in act) [nm(u), '${mc[u] ?? 0}', f0(byU(sel('deposit'), u)), byU(sel('rice'), u).toStringAsFixed(1), f0((mc[u] ?? 0) * rate), f0(byU(sel('deposit'), u) - (mc[u] ?? 0) * rate)]], act);

  Rpt fund(String title, String inT, String outT, bool share) {
    final out = month(outT).toList();
    final tout = sum(out), tin = sum(sel(inT));
    final per = act.isEmpty ? 0.0 : tout / act.length;
    return Rpt(title, [
      'মোট জমা (পুরনো সহ): ${f0(tin)}', 'এ মাসের খরচ: ${f0(tout)}',
      'মোট অবশিষ্ট (শুরু থেকে): ${f0(sum(allT(inT)) - sum(allT(outT)))}',
      if (share) 'জনপ্রতি ভাগ: ${per.toStringAsFixed(1)}',
      '— খরচের তালিকা —', for (final e in out) '${e['date']} ${e['note'] ?? ''}: ${e['amount']}',
    ], share ? ['নাম', 'দিয়েছে', 'ভাগ', 'বাকি'] : ['নাম', 'দিয়েছে'],
        [for (final u in act) [nm(u), f0(byU(sel(inT), u)), if (share) ...[per.toStringAsFixed(0), (per - byU(sel(inT), u)).toStringAsFixed(0)]]], act);
  }

  final rentDue = [for (final u in act) dn(m(ms[u])['rent'])].fold(0.0, (a, b) => a + b);
  final rent = Rpt('ভাড়া / অগ্রিম / মালিক', [
    'মোট ধার্য ভাড়া: ${f0(rentDue)}', 'এ মাসে ভাড়া জমা: ${f0(sum(month('rent')))}',
    'মোট অগ্রিম জমা: ${f0(sum(allT('advance')))}',
    'মালিককে পরিশোধ (এ মাস): ${f0(sum(month('owner')))}', 'মালিককে পরিশোধ (মোট): ${f0(sum(allT('owner')))}',
  ], ['নাম', 'ধার্য', 'জমা', 'বাকি', 'অগ্রিম'],
      [for (final u in act) [nm(u), f0(dn(m(ms[u])['rent'])), f0(byU(month('rent'), u)), f0(dn(m(ms[u])['rent']) - byU(month('rent'), u)), f0(byU(allT('advance'), u))]], act);

  final all = Rpt('মেসের সার্বিক অবস্থা', [
    'সদস্য: ${act.length}', 'মোট মিল: $total', 'মিল রেট: ${rate.toStringAsFixed(2)}',
    'টাকা জমা (মিল): ${f0(sum(sel('deposit')))}', 'বাজার খরচ: ${f0(mk)}',
    'বিল জমা/খরচ: ${f0(sum(sel('bill_in')))} / ${f0(sum(month('bill')))}',
    'জ্বালানি জমা/খরচ: ${f0(sum(sel('fuel_in')))} / ${f0(sum(month('fuel')))}',
    'উন্নয়ন জমা/খরচ: ${f0(sum(sel('dev_in')))} / ${f0(sum(month('dev')))}',
    'ভাড়া ধার্য/জমা: ${f0(rentDue)} / ${f0(sum(month('rent')))}',
    'মালিককে পরিশোধ (এ মাস): ${f0(sum(month('owner')))}',
  ], [], [], []);
  return {if (Me.role != 'boarder') 'all': all, 'meal': meal, 'bill': fund('বিল হিসাব', 'bill_in', 'bill', true), 'fuel': fund('উড/গ্যাস হিসাব', 'fuel_in', 'fuel', true), 'dev': fund('উন্নয়ন হিসাব', 'dev_in', 'dev', false), 'rent': rent};
}

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});
  @override
  State<ReportPage> createState() => _ReportState();
}

class _ReportState extends State<ReportPage> {
  DateTime mo = DateTime.now();
  String cat = 'meal';
  late Future<Map<String, Rpt>> f;
  String get ym => ymd(mo).substring(0, 7);
  @override
  void initState() { super.initState(); f = buildReports(ym); }
  void go(int k) => setState(() { mo = DateTime(mo.year, mo.month + k, 1); f = buildReports(ym); });

  Future<void> pdf(Map<String, Rpt> r) async {
    final font = await PdfGoogleFonts.notoSansBengaliRegular();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      theme: pw.ThemeData.withFont(base: font),
      build: (_) => [
        pw.Text('মেস হিসাব - $ym', style: const pw.TextStyle(fontSize: 20)),
        for (final x in r.values) ...[
          pw.SizedBox(height: 12),
          pw.Text(x.title, style: const pw.TextStyle(fontSize: 16)),
          for (final t in x.notes) pw.Text(t),
          if (x.head.isNotEmpty) pw.TableHelper.fromTextArray(headers: x.head, data: x.vis),
        ],
        pw.SizedBox(height: 16),
        pw.Text(brand),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'mess-$ym.pdf');
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<Map<String, Rpt>>(
        future: f,
        builder: (c, s) {
          if (s.hasError) return Center(child: Text('ত্রুটি: ${s.error}'));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final r = s.data!;
          if (!r.containsKey(cat)) cat = r.keys.first;
          final x = r[cat]!;
          const label = {'all': 'সার্বিক অবস্থা', 'meal': 'মিল', 'bill': 'বিল', 'fuel': 'উড/গ্যাস', 'dev': 'উন্নয়ন', 'rent': 'ভাড়া/অগ্রিম/মালিক'};
          return ListView(padding: const EdgeInsets.all(12), children: [
            Row(children: [
              IconButton(onPressed: () => go(-1), icon: const Icon(Icons.chevron_left)),
              Text(ym, style: const TextStyle(fontSize: 18)),
              IconButton(onPressed: () => go(1), icon: const Icon(Icons.chevron_right)),
              const Spacer(),
              FilledButton.icon(onPressed: () => pdf(r), icon: const Icon(Icons.picture_as_pdf), label: const Text('PDF')),
            ]),
            DropdownButtonFormField<String>(value: cat, items: [for (final k in r.keys) DropdownMenuItem(value: k, child: Text(label[k]!))], onChanged: (v) => setState(() => cat = v!)),
            const SizedBox(height: 8),
            Text(x.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            for (final t in x.notes) Text(t),
            if (x.head.isNotEmpty) SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: [for (final h in x.head) DataColumn(label: Text(h))], rows: [for (final row in x.vis) DataRow(cells: [for (final v in row) DataCell(Text(v))])])),
            Center(child: footer()),
          ]);
        },
      );
}
