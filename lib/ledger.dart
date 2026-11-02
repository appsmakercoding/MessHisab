import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'common.dart';

class LedgerPage extends StatelessWidget {
  const LedgerPage({super.key});
  List<String> get allowed => canEnter[Me.role] ?? [];

  Future<void> add(BuildContext c) async {
    final mid = Me.mid;
    final ms = m((await db.ref('messes/$mid/members').get()).value);
    String t = allowed.first;
    String? who;
    DateTime dt = DateTime.now();
    bool open = false;
    final amt = TextEditingController(), note = TextEditingController();
    if (!c.mounted) return;
    await showDialog(
      context: c,
      builder: (_) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('নতুন এন্ট্রি'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(value: t, items: [for (final k in allowed) DropdownMenuItem(value: k, child: Text(types[k]!))], onChanged: (v) => set(() => t = v!)),
              DropdownButtonFormField<String>(value: who, hint: Text(needWho.contains(t) ? 'কার নামে (বাধ্যতামূলক)' : 'কে (ঐচ্ছিক)'), items: [for (final e in ms.entries) DropdownMenuItem(value: e.key as String, child: Text('${m(e.value)['name']}'))], onChanged: (v) => set(() => who = v)),
              TextField(controller: amt, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'পরিমাণ')),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'বিবরণ')),
              ListTile(contentPadding: EdgeInsets.zero, title: Text('তারিখ: ${ymd(dt)}'), trailing: const Icon(Icons.calendar_month), onTap: () async {
                final p = await showDatePicker(context: d, initialDate: dt, firstDate: DateTime(2024), lastDate: DateTime(2100));
                if (p != null) set(() => dt = p);
              }),
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('পুরনো জমা / আগের বাকি'), value: open, onChanged: (v) => set(() => open = v!)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('বাতিল')),
            FilledButton(
              onPressed: () async {
                final a = double.tryParse(amt.text) ?? 0;
                if (a <= 0 || (needWho.contains(t) && who == null)) { snack(d, 'পরিমাণ ও নাম দিন'); return; }
                await safe(d, () async {
                  await db.ref('messes/$mid/entries').push().set({'type': t, 'uid': who ?? '', 'name': who == null ? '-' : m(ms[who])['name'], 'amount': a, 'note': note.text.trim(), 'date': ymd(dt), 'open': open, 'by': Me.name});
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

  Future<void> edit(BuildContext c, String key, Map e) async {
    if (!allowed.contains(e['type'])) return;
    final amt = TextEditingController(text: '${e['amount']}'), note = TextEditingController(text: '${e['note'] ?? ''}');
    await showDialog(
      context: c,
      builder: (d) => AlertDialog(
        title: Text('${types[e['type']]} - ${e['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amt, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'পরিমাণ')),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'বিবরণ')),
        ]),
        actions: [
          TextButton(
            onPressed: () async {
              if (!await confirm(d, 'মুছে ফেলবেন?')) return;
              await safe(d, () async {
                await db.ref('messes/${Me.mid}/entries/$key').remove();
                await audit('মুছেছে: ${types[e['type']]} ${e['amount']} (${e['name']})');
                if (d.mounted) Navigator.pop(d);
              });
            },
            child: const Text('ডিলিট', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () async {
              final a = double.tryParse(amt.text) ?? 0;
              if (a <= 0) return;
              await safe(d, () async {
                await db.ref('messes/${Me.mid}/entries/$key').update({'amount': a, 'note': note.text.trim()});
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
        appBar: AppBar(title: const Text('এন্ট্রি / হিসাব')),
        floatingActionButton: allowed.isEmpty ? null : FloatingActionButton(onPressed: () => add(c), child: const Icon(Icons.add)),
        body: StreamBuilder<DatabaseEvent>(
          stream: db.ref('messes/${Me.mid}/entries').orderByChild('date').limitToLast(200).onValue,
          builder: (c, s) {
            final es = m(s.data?.snapshot.value).entries.toList()..sort((a, b) => '${m(b.value)['date']}'.compareTo('${m(a.value)['date']}'));
            if (es.isEmpty) return const Center(child: Text('কোনো এন্ট্রি নেই'));
            return ListView(children: [
              for (final x in es)
                ListTile(
                  title: Text('${types[m(x.value)['type']] ?? m(x.value)['type']} - ${m(x.value)['name']}'),
                  subtitle: Text('${m(x.value)['date']}  ${m(x.value)['open'] == true ? '(পুরনো) ' : ''}${m(x.value)['note'] ?? ''}'),
                  trailing: Text('${m(x.value)['amount']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () => edit(c, '${x.key}', m(x.value)),
                ),
            ]);
          },
        ),
      );
}
