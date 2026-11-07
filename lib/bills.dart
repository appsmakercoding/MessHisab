import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'common.dart';
import 'heads.dart';

/// মনিটর নতুন বিল/খাত বানায়
Future<void> newHead(BuildContext c) async {
  final nm = TextEditingController(), amt = TextEditingController();
  String mode = 'fix', cat = 'bill';
  DateTime? due;
  await showDialog(
    context: c,
    builder: (_) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: const Text('নতুন বিল / খাত'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 6, children: [
              for (final s in headSuggest)
                ActionChip(label: Text(s, style: const TextStyle(fontSize: 12)), onPressed: () {
                  nm.text = s;
                  if (s == 'বাড়িভাড়া') { mode = 'rent'; cat = 'monitor'; }
                  set(() {});
                }),
            ]),
            TextField(controller: nm, decoration: const InputDecoration(labelText: 'নাম (যেমন: অক্টোবরের বিদ্যুৎ বিল)')),
            DropdownButtonFormField<String>(value: mode, items: [for (final e in headModes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => set(() => mode = v!)),
            if (mode != 'rent') TextField(controller: amt, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: mode == 'fix' ? 'জনপ্রতি টাকা' : 'মোট বিলের টাকা (পরে বসালেও চলবে)')),
            DropdownButtonFormField<String>(value: cat, items: [for (final e in headCats.entries) DropdownMenuItem(value: e.key, child: Text('দায়িত্বে: ${e.value}'))], onChanged: (v) => set(() => cat = v!)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(due == null ? 'শেষ তারিখ (ঐচ্ছিক)' : 'শেষ তারিখ: ${bn(ymd(due!))}'),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final p = await showDatePicker(context: d, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2100));
                if (p != null) set(() => due = p);
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('বাতিল')),
          FilledButton(
            onPressed: () async {
              if (nm.text.trim().isEmpty) { snack(d, 'নাম দিন'); return; }
              final a = double.tryParse(amt.text.trim()) ?? 0;
              await safe(d, () async {
                await db.ref('messes/${Me.mid}/heads').push().set({
                  'name': nm.text.trim(), 'mode': mode, if (mode == 'fix') 'amt': a, if (mode == 'split') 'total': a,
                  'cat': cat, 'date': today(), if (due != null) 'due': ymd(due!), 'closed': false, 'carry': 0,
                });
                await audit('নতুন বিল/খাত: ${nm.text.trim()}');
                if (d.mounted) Navigator.pop(d);
              });
            },
            child: const Text('তৈরি করুন'),
          ),
        ],
      ),
    ),
  );
}

/// বিল ও খাতের তালিকা (মনিটর সব দেখে; ম্যানেজার শুধু নিজেরটা)
class HeadsPage extends StatelessWidget {
  final String? title;
  const HeadsPage({this.title, super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: title == null ? null : AppBar(title: Text(title!)),
        floatingActionButton: Me.mon ? FloatingActionButton.extended(onPressed: () => newHead(c), icon: const Icon(Icons.add), label: const Text('নতুন বিল / খাত')) : null,
        body: StreamBuilder<DatabaseEvent>(
          stream: db.ref('messes/${Me.mid}/members').onValue,
          builder: (c, s1) => StreamBuilder<DatabaseEvent>(
            stream: db.ref('messes/${Me.mid}/heads').onValue,
            builder: (c, s2) {
              final ms = m(s1.data?.snapshot.value);
              final hs = [for (final e in m(s2.data?.snapshot.value).entries) HV('${e.key}', m(e.value), ms)].where((v) => canHead(v.h)).toList()
                ..sort((a, b) {
                  if (a.closed != b.closed) return a.closed ? 1 : -1;
                  return '${b.h['date']}'.compareTo('${a.h['date']}');
                });
              if (hs.isEmpty) return Empty(Icons.receipt_long, Me.mon ? 'কোনো বিল বা খাত নেই।\nনিচের "নতুন বিল / খাত" চেপে তৈরি করুন।' : 'আপনার জন্য কোনো বিল নেই');
              return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), children: [
                for (final v in hs)
                  Builder(builder: (_) {
                    final cnt = v.part.length;
                    final done = v.part.where((u) => v.dueOf(u) > 0 && v.dueLeft(u) <= 0.5).length;
                    final due = v.dueTotal, paid = v.paidTotal;
                    final rem = due - paid > 0 ? due - paid : 0.0;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: v.closed ? Colors.grey.shade400 : null, child: Icon(headIcon(v.name, v.mode))),
                        title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(v.closed ? '✔ ক্লোজ করা' : '${bn(done)}/${bn(cnt)} জন দিয়েছে${v.h['due'] != null ? ' • শেষ ${bn(v.h['due'])}' : ''}', style: const TextStyle(fontSize: 12)),
                          if (due > 0) Padding(padding: const EdgeInsets.only(top: 4), child: LinearProgressIndicator(value: (paid / due).clamp(0.0, 1.0).toDouble(), minHeight: 5)),
                        ]),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(taka(rem), style: TextStyle(fontWeight: FontWeight.bold, color: rem > 0 ? Colors.red.shade400 : Colors.green)),
                          const Text('বাকি', style: TextStyle(fontSize: 10)),
                        ]),
                        onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => HeadDetail(v.id))),
                      ),
                    );
                  }),
              ]);
            },
          ),
        ),
      );
}

class HeadDetail extends StatelessWidget {
  final String id;
  const HeadDetail(this.id, {super.key});
  DatabaseReference get ref => db.ref('messes/${Me.mid}/heads/$id');

  Future<void> addPay(BuildContext c, HV v, String u) async {
    final left = v.dueLeft(u);
    final amt = TextEditingController(text: left > 0 ? left.toStringAsFixed(0) : '');
    DateTime dt = DateTime.now();
    await showDialog(
      context: c,
      builder: (_) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('${m(v.members[u])['name']} — জমা'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: amt, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'কত টাকা দিল')),
            ListTile(contentPadding: EdgeInsets.zero, title: Text('তারিখ: ${bn(ymd(dt))}'), trailing: const Icon(Icons.calendar_month), onTap: () async {
              final p = await showDatePicker(context: d, initialDate: dt, firstDate: DateTime(2024), lastDate: DateTime(2100));
              if (p != null) set(() => dt = p);
            }),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('বাতিল')),
            FilledButton(onPressed: () async {
              final a = double.tryParse(amt.text.trim()) ?? 0;
              if (a <= 0) return;
              await safe(d, () async {
                await ref.child('pay').push().set({'uid': u, 'amt': a, 'date': ymd(dt), 'by': Me.name});
                await audit('${v.name} জমা: ${m(v.members[u])['name']} ${a.toStringAsFixed(0)}');
                if (d.mounted) Navigator.pop(d);
              });
            }, child: const Text('সেভ')),
          ],
        ),
      ),
    );
  }

  Future<void> addExp(BuildContext c, HV v) async {
    final amt = TextEditingController(), note = TextEditingController();
    await showDialog(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('খরচ যোগ'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amt, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'কত টাকা খরচ')),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'কীসের খরচ')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('বাতিল')),
          FilledButton(onPressed: () async {
            final a = double.tryParse(amt.text.trim()) ?? 0;
            if (a <= 0) return;
            await safe(d, () async {
              await ref.child('exp').push().set({'amt': a, 'note': note.text.trim(), 'date': today(), 'by': Me.name});
              await audit('${v.name} খরচ: ${a.toStringAsFixed(0)} ${note.text.trim()}');
              if (d.mounted) Navigator.pop(d);
            });
          }, child: const Text('সেভ')),
        ],
      ),
    );
  }

  Future<void> toggleClose(BuildContext c, HV v) async {
    if (v.closed) {
      if (!await confirm(c, 'আবার খুলবেন?')) return;
      if (!c.mounted) return;
      await safe(c, () async { await ref.update({'closed': false, 'part': null}); await audit('আবার খুলেছে: ${v.name}'); });
    } else {
      if (!await confirm(c, '"${v.name}" ক্লোজ করবেন? এরপর জমা/খরচ বদলানো যাবে না।')) return;
      if (!c.mounted) return;
      await safe(c, () async {
        await ref.update({'closed': true, 'part': {for (final u in v.part) u: true}, 'closedAt': ServerValue.timestamp});
        await audit('ক্লোজ করেছে: ${v.name}');
      });
    }
  }

  /// এই চক্র ক্লোজ করে নতুন চক্র (যেমন পরের মাসের বিল) শুরু; হাতে থাকা টাকা জের হিসেবে যায়
  Future<void> newCycle(BuildContext c, HV v) async {
    final nm = TextEditingController(text: v.name);
    final amt = TextEditingController(text: v.mode == 'fix' ? dn(v.h['amt']).toStringAsFixed(0) : '');
    await showDialog(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('নতুন চক্র শুরু'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('"${v.name}" ক্লোজ হবে।${v.mode == 'fix' ? ' হাতে থাকা ${taka(v.left)} নতুন চক্রে জের যাবে।' : ''}', style: const TextStyle(fontSize: 12)),
          TextField(controller: nm, decoration: const InputDecoration(labelText: 'নতুন নাম')),
          if (v.mode != 'rent') TextField(controller: amt, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: v.mode == 'fix' ? 'জনপ্রতি টাকা' : 'মোট বিলের টাকা (পরে বসালেও চলবে)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('বাতিল')),
          FilledButton(onPressed: () async {
            if (nm.text.trim().isEmpty) return;
            final a = double.tryParse(amt.text.trim()) ?? 0;
            await safe(d, () async {
              final hr = db.ref('messes/${Me.mid}/heads');
              final key = hr.push().key!;
              final up = <String, Object?>{
                key: {
                  'name': nm.text.trim(), 'mode': v.mode, if (v.mode == 'fix') 'amt': a, if (v.mode == 'split') 'total': a,
                  'cat': v.h['cat'] ?? 'bill', 'date': today(), 'closed': false, 'carry': v.mode == 'fix' ? v.left : 0,
                },
                if (!v.closed) '${v.id}/closed': true,
                if (!v.closed) '${v.id}/part': {for (final u in v.part) u: true},
              };
              await hr.update(up);
              await audit('নতুন চক্র: ${nm.text.trim()}');
              if (d.mounted) { Navigator.pop(d); Navigator.pop(c); }
            });
          }, child: const Text('শুরু করুন')),
        ],
      ),
    );
  }

  Future<void> edit(BuildContext c, HV v) async {
    final nm = TextEditingController(text: v.name);
    final amt = TextEditingController(text: (v.mode == 'split' ? dn(v.h['total']) : dn(v.h['amt'])) == 0 ? '' : (v.mode == 'split' ? dn(v.h['total']) : dn(v.h['amt'])).toStringAsFixed(0));
    await showDialog(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('বিল সম্পাদনা'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nm, decoration: const InputDecoration(labelText: 'নাম')),
          if (v.mode != 'rent') TextField(controller: amt, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: v.mode == 'fix' ? 'জনপ্রতি টাকা' : 'মোট বিলের টাকা')),
        ]),
        actions: [
          TextButton(
            onPressed: () async {
              if (!await confirm(d, 'এই বিল পুরো মুছে ফেলবেন? (জমার তথ্যসহ)')) return;
              if (!d.mounted) return;
              await safe(d, () async {
                await ref.remove();
                await audit('মুছেছে: ${v.name}');
                if (d.mounted) { Navigator.pop(d); Navigator.pop(c); }
              });
            },
            child: const Text('মুছুন', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(onPressed: () async {
            final a = double.tryParse(amt.text.trim()) ?? 0;
            await safe(d, () async {
              await ref.update({'name': nm.text.trim(), if (v.mode == 'fix') 'amt': a, if (v.mode == 'split') 'total': a});
              if (d.mounted) Navigator.pop(d);
            });
          }, child: const Text('সেভ')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext c) => StreamBuilder<DatabaseEvent>(
        stream: db.ref('messes/${Me.mid}/members').onValue,
        builder: (c, s1) => StreamBuilder<DatabaseEvent>(
          stream: ref.onValue,
          builder: (c, s2) {
            if (!s2.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            final h = m(s2.data!.snapshot.value);
            if (h.isEmpty) return Scaffold(appBar: AppBar(), body: const Empty(Icons.receipt_long, 'বিলটি আর নেই'));
            final ms = m(s1.data?.snapshot.value);
            final v = HV(id, h, ms);
            final can = canHead(h) && !v.closed;
            final due = v.dueTotal, paid = v.paidTotal;
            final names = {for (final e in ms.entries) '${e.key}': '${m(e.value)['name']}'};
            final pays = m(h['pay']).entries.toList()..sort((a, b) => '${m(b.value)['date']}'.compareTo('${m(a.value)['date']}'));
            final exps = m(h['exp']).entries.toList()..sort((a, b) => '${m(b.value)['date']}'.compareTo('${m(a.value)['date']}'));
            final plist = [...v.part]..sort((a, b) => (names[a] ?? '').compareTo(names[b] ?? ''));
            return Scaffold(
              appBar: AppBar(title: Text(v.name), actions: [
                if (Me.mon) IconButton(tooltip: 'সম্পাদনা', icon: const Icon(Icons.edit), onPressed: () => edit(c, v)),
              ]),
              body: ListView(padding: const EdgeInsets.all(12), children: [
                Wrap(spacing: 8, children: [
                  Chip(label: Text(headModes[v.mode] ?? ''), visualDensity: VisualDensity.compact),
                  Chip(label: Text(headCats[h['cat']] ?? ''), visualDensity: VisualDensity.compact),
                  if (h['due'] != null) Chip(label: Text('শেষ ${bn(h['due'])}'), visualDensity: VisualDensity.compact),
                  if (v.closed) const Chip(label: Text('ক্লোজ করা'), visualDensity: VisualDensity.compact),
                ]),
                Row(children: [Stat('মোট ধার্য', taka(due), Icons.request_quote), Stat('জমা হয়েছে', taka(paid), Icons.savings, color: Colors.green), Stat('বাকি', taka(due - paid > 0 ? due - paid : 0), Icons.pending_actions, color: Colors.red)]),
                Row(children: [Stat('আগের জের', taka(v.carry), Icons.history), Stat('খরচ', taka(v.spent), Icons.outbox), Stat('হাতে আছে', taka(v.left), Icons.account_balance_wallet)]),
                if (v.mode == 'split' && dn(h['total']) == 0) const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('মোট বিলের টাকা এখনো বসানো হয়নি'), subtitle: Text('উপরের পেন্সিল চেপে বসান — তখন জনপ্রতি ভাগ হয়ে যাবে'))),
                if (v.mode == 'split' && dn(h['total']) > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text('জনপ্রতি: ${taka(v.part.isEmpty ? 0 : dn(h['total']) / v.part.length)}', style: const TextStyle(fontWeight: FontWeight.w600))),
                const SizedBox(height: 8),
                Text('সদস্য (${bn(plist.length)})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                for (final u in plist)
                  Builder(builder: (_) {
                    final left = v.dueLeft(u);
                    return ListTile(
                      dense: true,
                      title: Text(names[u] ?? '-'),
                      subtitle: Text('ধার্য ${f0(v.dueOf(u))} • জমা ${f0(v.paid[u] ?? 0)}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        left > 0.5 ? Text('বাকি ${f0(left)}', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.bold)) : const Icon(Icons.check_circle, color: Colors.green),
                        if (can) IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle), onPressed: () => addPay(c, v, u)),
                        if (can && left > 0.5) IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.send, color: Colors.green, size: 20), onPressed: () {
                          var ph = '${m(ms[u])['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
                          if (ph.startsWith('0')) ph = '88$ph';
                          openUrl('https://wa.me/$ph?text=${Uri.encodeComponent('আসসালামু আলাইকুম ${names[u]}, "${v.name}" এর ৳${f0(left)} বাকি আছে। অনুগ্রহ করে দিয়ে দিন। — মেস হিসাব')}');
                        }),
                      ]),
                    );
                  }),
                ExpansionTile(
                  title: Text('জমার তালিকা (${bn(pays.length)})'),
                  children: [
                    for (final e in pays)
                      ListTile(dense: true, title: Text('${names[m(e.value)['uid']] ?? '-'} — ৳${f0(dn(m(e.value)['amt']))}'), subtitle: Text('${bn(m(e.value)['date'])} • ${m(e.value)['by'] ?? ''}'),
                          trailing: can ? IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () async { if (await confirm(c, 'এই জমা মুছবেন?')) { if (c.mounted) await safe(c, () => ref.child('pay/${e.key}').remove()); } }) : null),
                  ],
                ),
                ExpansionTile(
                  initiallyExpanded: exps.isNotEmpty,
                  title: Text('খরচের তালিকা (${bn(exps.length)})'),
                  children: [
                    for (final e in exps)
                      ListTile(dense: true, title: Text('৳${f0(dn(m(e.value)['amt']))} — ${m(e.value)['note'] ?? ''}'), subtitle: Text('${bn(m(e.value)['date'])} • ${m(e.value)['by'] ?? ''}'),
                          trailing: can ? IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () async { if (await confirm(c, 'এই খরচ মুছবেন?')) { if (c.mounted) await safe(c, () => ref.child('exp/${e.key}').remove()); } }) : null),
                    if (can) TextButton.icon(onPressed: () => addExp(c, v), icon: const Icon(Icons.add), label: const Text('খরচ যোগ করুন')),
                  ],
                ),
                const SizedBox(height: 12),
                if (Me.mon) Row(children: [
                  Expanded(child: FilledButton.icon(onPressed: () => toggleClose(c, v), icon: Icon(v.closed ? Icons.lock_open : Icons.lock), label: Text(v.closed ? 'আবার খুলুন' : 'এই বিল ক্লোজ করুন'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(onPressed: () => newCycle(c, v), icon: const Icon(Icons.autorenew), label: const Text('নতুন চক্র'))),
                ]),
                const SizedBox(height: 40),
              ]),
            );
          },
        ),
      );
}
