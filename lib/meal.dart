import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'common.dart';

class MealPage extends StatefulWidget {
  const MealPage({super.key});
  @override
  State<MealPage> createState() => _MealState();
}

class _MealState extends State<MealPage> {
  DateTime d = DateTime.now();
  void shift(int k) => setState(() => d = d.add(Duration(days: k)));
  String get mid => Me.mid;

  Future<void> setMeal(String u, String k, int v) async {
    if (v < 0 || v > 20) return;
    await safe(context, () => db.ref('messes/$mid/meals/${ymOf(d)}/${ymd(d)}/$u/$k').set(v == 0 ? null : v));
  }

  /// ডিফল্ট মিল (সদস্যের সেটিং অনুযায়ী) সবার জন্য বসানো; ছুটিতে থাকলে বাদ
  Future<void> applyDefaults(Map ms, Map off, Map cur) async {
    if (!await confirm(context, 'সবার ডিফল্ট মিল বসাবেন? (আজকের এন্ট্রি বদলে যাবে)')) return;
    final up = <String, Object?>{};
    ms.forEach((u, v) {
      final x = m(v);
      if (x['active'] == false || x['role'] == 'owner') return;
      final isOff = off[u] == true;
      final df = m(x['def']);
      for (final k in ['b', 'l', 'd']) {
        final val = isOff ? 0 : n(df[k]);
        up['$u/$k'] = val == 0 ? null : val;
      }
    });
    if (!mounted) return;
    await safe(context, () async {
      await db.ref('messes/$mid/meals/${ymOf(d)}/${ymd(d)}').update(up);
      await audit('ডিফল্ট মিল বসিয়েছে: ${ymd(d)}');
    });
  }

  Future<void> copyYesterday() async {
    final y = d.subtract(const Duration(days: 1));
    final snap = await db.ref('messes/$mid/meals/${ymOf(y)}/${ymd(y)}').get();
    if (!snap.exists) { if (mounted) snack(context, 'গতদিনের কোনো মিল নেই'); return; }
    if (!mounted) return;
    if (!await confirm(context, 'গতকালের মিল কপি করবেন?')) return;
    if (!mounted) return;
    await safe(context, () => db.ref('messes/$mid/meals/${ymOf(d)}/${ymd(d)}').set(snap.value));
  }

  Future<void> offRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 60)), helpText: 'যে দিনগুলো মিল বন্ধ');
    if (r == null || !mounted) return;
    final days = r.end.difference(r.start).inDays + 1;
    if (days > 31) { snack(context, 'একবারে সর্বোচ্চ ৩১ দিন'); return; }
    final up = <String, Object?>{};
    for (var i = 0; i < days; i++) {
      final x = r.start.add(Duration(days: i));
      up['${ymOf(x)}/${ymd(x)}/${Me.uid}'] = true;
    }
    await safe(context, () => db.ref('messes/$mid/off').update(up));
    if (mounted) snack(context, '$days দিন মিল বন্ধ দেওয়া হয়েছে');
  }

  Widget stepper(String u, String k, String label, Map row, bool edit) {
    final v = n(row[k]);
    return Expanded(
        child: Column(children: [
      Text(label, style: const TextStyle(fontSize: 11)),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (edit) InkWell(onTap: () => setMeal(u, k, v - 1), child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.remove_circle_outline, size: 22))),
        SizedBox(width: 22, child: Text(bn(v), textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: v > 0 ? null : Colors.grey))),
        if (edit) InkWell(onTap: () => setMeal(u, k, v + 1), child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.add_circle, size: 22))),
      ]),
    ]));
  }

  @override
  Widget build(BuildContext c) {
    final ds = ymd(d), ym = ymOf(d), edit = Me.meal;
    final tom = DateTime.now().add(const Duration(days: 1));
    return StreamBuilder<DatabaseEvent>(
      stream: db.ref('messes/$mid/members').onValue,
      builder: (c, s1) => StreamBuilder<DatabaseEvent>(
        stream: db.ref('messes/$mid/meals/$ym/$ds').onValue,
        builder: (c, s2) => StreamBuilder<DatabaseEvent>(
          stream: db.ref('messes/$mid/off/$ym/$ds').onValue,
          builder: (c, s3) => StreamBuilder<DatabaseEvent>(
            stream: db.ref('messes/$mid/off/${ymOf(tom)}/${ymd(tom)}/${Me.uid}').onValue,
            builder: (c, s4) {
              final ms = m(s1.data?.snapshot.value), ml = m(s2.data?.snapshot.value), off = m(s3.data?.snapshot.value);
              final myOff = s4.data?.snapshot.value == true;
              final list = [for (final e in ms.entries) if (m(e.value)['active'] != false && m(e.value)['role'] != 'owner') e];
              if (!edit) list.retainWhere((e) => e.key == Me.uid);
              int tb = 0, tl = 0, td = 0, tg = 0;
              ml.forEach((u, v) { tb += n(m(v)['b']); tl += n(m(v)['l']); td += n(m(v)['d']); tg += n(m(v)['g']); });
              final cs = Theme.of(c).colorScheme;
              return Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(onPressed: () => shift(-1), icon: const Icon(Icons.chevron_left)),
                  TextButton(
                    onPressed: () async {
                      final p = await showDatePicker(context: c, initialDate: d, firstDate: DateTime(2024), lastDate: DateTime(2100));
                      if (p != null) setState(() => d = p);
                    },
                    child: Text(bn(ds) + (ds == today() ? '  (আজ)' : ''), style: const TextStyle(fontSize: 18)),
                  ),
                  IconButton(onPressed: () => shift(1), icon: const Icon(Icons.chevron_right)),
                ]),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: cs.primaryContainer,
                  child: Padding(padding: const EdgeInsets.all(10), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    for (final e in [['সকাল', tb], ['দুপুর', tl], ['রাত', td], ['গেস্ট', tg], ['মোট', tb + tl + td + tg]])
                      Column(children: [Text(bn(e[1]), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), Text('${e[0]}', style: const TextStyle(fontSize: 12))]),
                  ])),
                ),
                if (edit)
                  SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
                    ActionChip(avatar: const Icon(Icons.auto_fix_high, size: 18), label: const Text('ডিফল্ট বসান'), onPressed: () => applyDefaults(ms, off, ml)),
                    const SizedBox(width: 6),
                    ActionChip(avatar: const Icon(Icons.copy, size: 18), label: const Text('গতকালের কপি'), onPressed: copyYesterday),
                    const SizedBox(width: 6),
                    ActionChip(avatar: const Icon(Icons.clear_all, size: 18), label: const Text('আজকের সব মুছুন'), onPressed: () async {
                      if (!await confirm(c, 'এই দিনের সব মিল মুছবেন?')) return;
                      if (c.mounted) await safe(c, () => db.ref('messes/$mid/meals/$ym/$ds').remove());
                    }),
                  ])),
                if (!edit || true)
                  Card(
                    margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    child: Column(children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.beach_access),
                        title: Text('আগামীকাল (${bn(ymd(tom))}) আমার মিল বন্ধ'),
                        value: myOff,
                        onChanged: (v) => safe(c, () => db.ref('messes/$mid/off/${ymOf(tom)}/${ymd(tom)}/${Me.uid}').set(v ? true : null)),
                      ),
                      ListTile(dense: true, leading: const Icon(Icons.date_range), title: const Text('কয়েকদিনের জন্য মিল বন্ধ দিন (ছুটি/বাড়ি)'), onTap: offRange),
                    ]),
                  ),
                Expanded(
                  child: list.isEmpty
                      ? const Empty(Icons.restaurant, 'কোনো সদস্য নেই')
                      : ListView(padding: const EdgeInsets.all(12), children: [
                          for (final e in list)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(children: [
                                  Row(children: [
                                    CircleAvatar(radius: 16, child: Text(('${m(e.value)['name']}' + '?').substring(0, 1))),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text('${m(e.value)['name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                                    if (off['${e.key}'] == true) const Chip(label: Text('মিল বন্ধ', style: TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
                                  ]),
                                  Row(children: [
                                    stepper('${e.key}', 'b', 'সকাল', m(ml[e.key]), edit),
                                    stepper('${e.key}', 'l', 'দুপুর', m(ml[e.key]), edit),
                                    stepper('${e.key}', 'd', 'রাত', m(ml[e.key]), edit),
                                    stepper('${e.key}', 'g', 'গেস্ট', m(ml[e.key]), edit),
                                  ]),
                                ]),
                              ),
                            ),
                        ]),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
