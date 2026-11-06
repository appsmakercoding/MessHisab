import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'common.dart';

class LedgerPage extends StatefulWidget {
  final List<String>? only; // মনিটরের নির্দিষ্ট পেজের জন্য
  final String? title;
  const LedgerPage({this.only, this.title, super.key});
  @override
  State<LedgerPage> createState() => _LedgerState();
}

class _LedgerState extends State<LedgerPage> {
  DateTime mo = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String filter = '', q = '';
  @override
  void initState() { super.initState(); if (Me.mon && widget.only == null) filter = '_none'; } // মনিটর বাছলে তবেই তালিকা
  List<String> get allowed => canEnter[Me.role] ?? [];
  /// কোন ধরনের এন্ট্রি এই রোলের সামনে আসবে
  List<String> get seeTypes {
    if (widget.only != null) return widget.only!;
    switch (Me.role) {
      case 'monitor': return types.keys.toList();
      case 'meal': return ['deposit', 'rice', 'market', 'extra', 'rice_extra', 'x_in', 'x_out'];
      case 'bazari': return ['market'];
      case 'bills': return ['bill_in', 'bill'];
      case 'fuel': return ['fuel_in', 'fuel'];
      case 'dev': return ['dev_in', 'dev'];
      case 'owner': return ['rent', 'advance', 'owner'];
      default: return types.keys.toList(); // বর্ডার: শুধু নিজের এন্ট্রি (নিচে ফিল্টার)
    }
  }
  String get ym => ymOf(mo);
  void go(int k) => setState(() => mo = DateTime(mo.year, mo.month + k, 1));

  Future<void> add() async {
    final mid = Me.mid;
    final ms = m((await db.ref('messes/$mid/members').get()).value);
    final opts = allowed.where(seeTypes.contains).toList();
    if (opts.isEmpty) return;
    String t = opts.first;
    String? who;
    DateTime dt = DateTime.now();
    final amt = TextEditingController(), note = TextEditingController(), given = TextEditingController();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('নতুন এন্ট্রি'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(value: t, items: [for (final k in opts) DropdownMenuItem(value: k, child: Text(types[k]!))], onChanged: (v) => set(() => t = v!)),
              DropdownButtonFormField<String>(
                  value: who,
                  hint: Text(needWho.contains(t) ? 'কার নামে (বাধ্যতামূলক)' : t == 'market' ? 'কে বাজার করল' : 'কে (ঐচ্ছিক)'),
                  items: [for (final e in ms.entries) if (m(e.value)['active'] != false) DropdownMenuItem(value: e.key as String, child: Text('${m(e.value)['name']}'))],
                  onChanged: (v) => set(() => who = v)),
              if (t == 'market' && Me.meal) TextField(controller: given, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'বাজারিকে দেওয়া টাকা (ঐচ্ছিক)')),
              TextField(controller: amt, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t == 'market' ? 'আসল খরচ (বাজার করে যত লাগল)' : 'পরিমাণ')),
              if (t == 'market' && Me.meal && (double.tryParse(given.text) ?? 0) > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('ফেরত/বাকি হিসাব এন্ট্রিতে দেখাবে', style: const TextStyle(fontSize: 11))),
              TextField(controller: note, decoration: InputDecoration(labelText: t == 'market' ? 'কী কী কেনা হলো (চাল ২কেজি, ডাল...)' : 'বিবরণ'), maxLines: t == 'market' ? 3 : 1),
              ListTile(contentPadding: EdgeInsets.zero, title: Text('তারিখ: ${bn(ymd(dt))}'), trailing: const Icon(Icons.calendar_month), onTap: () async {
                final p = await showDatePicker(context: d, initialDate: dt, firstDate: DateTime(2024), lastDate: DateTime(2100));
                if (p != null) set(() => dt = p);
              }),
              if (Me.role == 'bazari' && t == 'market') const Text('আপনার বাজার মনিটর/মিল ম্যানেজার অনুমোদন করলে হিসাবে ধরা হবে।', style: TextStyle(fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('বাতিল')),
            FilledButton(
              onPressed: () async {
                final a = double.tryParse(amt.text.trim()) ?? 0;
                if (a <= 0 || (needWho.contains(t) && who == null)) { snack(d, 'পরিমাণ ও নাম দিন'); return; }
                await safe(d, () async {
                  final pend = Me.role == 'bazari';
                  await db.ref('messes/$mid/entries/${ymOf(dt)}').push().set({
                    'type': t, 'uid': who ?? '', 'name': who == null ? '-' : m(ms[who])['name'], 'amount': a, 'note': note.text.trim(),
                    'date': ymd(dt), 'by': Me.name, 'byId': Me.uid, if (t == 'market') 'st': pend ? 'p' : 'a',
                    if (t == 'market' && !pend && (double.tryParse(given.text.trim()) ?? 0) > 0) 'given': double.parse(given.text.trim()),
                  });
                  await audit('এন্ট্রি: ${types[t]} $a');
                  if (d.mounted) Navigator.pop(d);
                });
              },
              child: const Text('সেভ'),
            ),
          ],
        ),
      ),
    );
  }

  bool canTouch(Map e) {
    if (!allowed.contains(e['type'])) return false;
    if (Me.role == 'bazari') return e['st'] == 'p' && e['byId'] == Me.uid;
    return true;
  }

  Future<void> approve(String key, Map e) async {
    await safe(context, () async {
      await db.ref('messes/${Me.mid}/entries/$ym/$key/st').set('a');
      await audit('বাজার অনুমোদন: ${e['amount']} (${e['by']})');
    });
  }

  Future<void> edit(String key, Map e) async {
    if (!canTouch(e)) return;
    final amt = TextEditingController(text: '${e['amount']}'), note = TextEditingController(text: '${e['note'] ?? ''}');
    await showDialog(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('${types[e['type']]} - ${e['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amt, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'পরিমাণ')),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'বিবরণ'), maxLines: 3),
        ]),
        actions: [
          TextButton(
            onPressed: () async {
              if (!await confirm(d, 'মুছে ফেলবেন?')) return;
              if (!d.mounted) return;
              await safe(d, () async {
                await db.ref('messes/${Me.mid}/entries/$ym/$key').remove();
                await audit('মুছেছে: ${types[e['type']]} ${e['amount']} (${e['name']})');
                if (d.mounted) Navigator.pop(d);
              });
            },
            child: const Text('ডিলিট', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () async {
              final a = double.tryParse(amt.text.trim()) ?? 0;
              if (a <= 0) return;
              await safe(d, () async {
                await db.ref('messes/${Me.mid}/entries/$ym/$key').update({'amount': a, 'note': note.text.trim()});
                await audit('এডিট: ${types[e['type']]} ${e['amount']} → $a (${e['name']})');
                if (d.mounted) Navigator.pop(d);
              });
            },
            child: const Text('সেভ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: widget.title == null ? null : AppBar(title: Text(widget.title!)),
        floatingActionButton: allowed.isEmpty ? null : FloatingActionButton.extended(onPressed: add, icon: const Icon(Icons.add), label: const Text('এন্ট্রি')),
        body: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 0), child: MonthBar(mo, go)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: TextField(onChanged: (v) => setState(() => q = v.trim()), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'নাম বা বিবরণ খুঁজুন', isDense: true, border: OutlineInputBorder()))),
          if ((seeTypes.length > 2 || seeTypes.contains('market')) && Me.role != 'boarder' && !(widget.only != null && !widget.only!.contains('market') && seeTypes.length <= 2)) SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(8), child: Row(children: [
            Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: const Text('সব'), selected: filter.isEmpty, onSelected: (_) => setState(() => filter = ''))),
            if (seeTypes.contains('market') && Me.role != 'boarder') Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: const Text('অনুমোদনের অপেক্ষায়'), selected: filter == '_p', onSelected: (_) => setState(() => filter = '_p'))),
            if (Me.role != 'boarder') for (final k in seeTypes) Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(types[k]!), selected: filter == k, onSelected: (_) => setState(() => filter = k))),
          ])),
          Expanded(
            child: filter == '_none'
                ? ListView(padding: const EdgeInsets.all(16), children: [
                    const Text('কোন এন্ট্রি দেখবেন?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      ActionChip(avatar: const Icon(Icons.list_alt, size: 18), label: const Text('সব এন্ট্রি'), onPressed: () => setState(() => filter = '')),
                      for (final k in seeTypes) ActionChip(avatar: Icon(typeIcons[k], size: 18), label: Text(types[k]!), onPressed: () => setState(() => filter = k)),
                    ]),
                  ])
                : StreamBuilder<DatabaseEvent>(
              stream: db.ref('messes/${Me.mid}/entries/$ym').onValue,
              builder: (c, s) {
                var es = m(s.data?.snapshot.value).entries.toList()..sort((a, b) => '${m(b.value)['date']}'.compareTo('${m(a.value)['date']}'));
                es = es.where((x) {
                  final e = m(x.value);
                  if (!seeTypes.contains(e['type'])) return false;
                  if (Me.role == 'boarder' && e['uid'] != Me.uid) return false;
                  if (filter == '_p' && e['st'] != 'p') return false;
                  if (filter.isNotEmpty && filter != '_p' && e['type'] != filter) return false;
                  if (q.isNotEmpty && !('${e['name']} ${e['note']}').contains(q)) return false;
                  return true;
                }).toList();
                if (es.isEmpty) return const Empty(Icons.receipt_long, 'এই মাসে কোনো এন্ট্রি নেই');
                return ListView(padding: const EdgeInsets.only(bottom: 80), children: [
                  for (final x in es)
                    Builder(builder: (_) {
                      final e = m(x.value);
                      final pend = e['st'] == 'p';
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: pend ? Colors.amber.shade200 : null, child: Icon(typeIcons[e['type']] ?? Icons.receipt, size: 20)),
                        title: Text('${types[e['type']] ?? e['type']}${e['name'] != '-' ? ' • ${e['name']}' : ''}'),
                        subtitle: Text('${bn(e['date'])}${pend ? '  ⏳ অনুমোদনের অপেক্ষায়' : ''}${dn(e['given']) > 0 ? '\nদেওয়া ${bn(dn(e['given']).toStringAsFixed(0))} • ${dn(e['given']) >= dn(e['amount']) ? 'ফেরত' : 'বাজারির পকেট থেকে'} ${bn((dn(e['given']) - dn(e['amount'])).abs().toStringAsFixed(0))}' : ''}\n${e['note'] ?? ''}${e['by'] != null ? '  — ${e['by']}' : ''}'.trim()),
                        isThreeLine: '${e['note'] ?? ''}'.isNotEmpty || dn(e['given']) > 0,
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(bn(e['amount']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          if (pend && Me.meal) InkWell(onTap: () => approve('${x.key}', e), child: const Text('অনুমোদন ✔', style: TextStyle(color: Colors.green, fontSize: 12))),
                        ]),
                        onTap: () => edit('${x.key}', e),
                      );
                    }),
                ]);
              },
            ),
          ),
        ]),
      );
}
