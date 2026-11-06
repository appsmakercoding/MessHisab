import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'common.dart';
import 'config.dart';
import 'report.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  bool get mon => Me.mon;

  Future<void> pass(BuildContext c) async {
    final o = TextEditingController(), nw = TextEditingController();
    await showDialog(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('পাসওয়ার্ড পরিবর্তন'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: o, obscureText: true, decoration: const InputDecoration(labelText: 'বর্তমান পাসওয়ার্ড')),
          TextField(controller: nw, obscureText: true, decoration: const InputDecoration(labelText: 'নতুন পাসওয়ার্ড (কমপক্ষে ৬)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('বাতিল')),
          FilledButton(
            onPressed: () async {
              try {
                final u = auth.currentUser!;
                await u.reauthenticateWithCredential(EmailAuthProvider.credential(email: u.email!, password: o.text));
                await u.updatePassword(nw.text);
                if (d.mounted) { Navigator.pop(d); snack(c, 'পাসওয়ার্ড বদলেছে'); }
              } on FirebaseAuthException catch (e) { if (d.mounted) snack(d, e.message ?? 'ত্রুটি'); }
            },
            child: const Text('সেভ'),
          ),
        ],
      ),
    );
  }

  Future<void> notice(BuildContext c) async {
    final t = TextEditingController();
    await showDialog(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('নোটিশ (ফাঁকা = মুছে যাবে)'),
        content: TextField(controller: t, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('বাতিল')),
          FilledButton(onPressed: () async {
            await safe(d, () => db.ref('messes/${Me.mid}/notice').set(t.text.trim().isEmpty ? null : t.text.trim()));
            if (d.mounted) Navigator.pop(d);
          }, child: const Text('সেভ')),
        ],
      ),
    );
  }

  /// মাস ক্লোজ: হিসাব সেভ করে (পরের মাসে ক্যারি ফরওয়ার্ড) মাস লক করে
  Future<void> closeMonth(BuildContext c) async {
    final now = DateTime.now();
    final list = [ymOf(DateTime(now.year, now.month - 1, 1)), ymOf(now)];
    await showDialog(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('মাস ক্লোজ / খোলা'),
        content: StreamBuilder<DatabaseEvent>(
          stream: db.ref('messes/${Me.mid}/locked').onValue,
          builder: (c2, s) {
            final lk = m(s.data?.snapshot.value);
            return Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('ক্লোজ করলে মাসের পাওনা/দেনা পরের মাসে জমে যাবে এবং ওই মাসে কেউ আর এন্ট্রি বদলাতে পারবে না।', style: TextStyle(fontSize: 12)),
              for (final ym in list)
                ListTile(
                  title: Text(monthLabelYm(ym)),
                  subtitle: Text(lk[ym] == true ? 'ক্লোজ করা' : 'চালু'),
                  trailing: lk[ym] == true
                      ? OutlinedButton(onPressed: () async { await safe(d, () => db.ref('messes/${Me.mid}/locked/$ym').remove()); await audit('মাস খুলেছে: $ym'); }, child: const Text('খুলুন'))
                      : FilledButton(onPressed: () async {
                          if (!await confirm(d, '${monthLabelYm(ym)} ক্লোজ করবেন?')) return;
                          await safe(d, () async {
                            final k = await Calc.load(ym);
                            await db.ref('messes/${Me.mid}/summary/$ym').set({
                              'bal': {for (final u in k.act) u: double.parse(k.bal(u).toStringAsFixed(2))},
                              'rbal': {for (final u in k.act) u: double.parse(k.riceBal(u).toStringAsFixed(3))},
                              'fund': {'bill': k.fundLeft('bill', k.bin.values.fold(0.0, (a, b) => a + b), k.bill), 'fuel': k.fundLeft('fuel', k.fin.values.fold(0.0, (a, b) => a + b), k.fuel), 'dev': k.fundLeft('dev', k.din.values.fold(0.0, (a, b) => a + b), k.dev)},
                              'rate': double.parse(k.rate.toStringAsFixed(2)), 'charge': double.parse(k.totalCharge.toStringAsFixed(0)), 'meals': k.total,
                            });
                            await db.ref('messes/${Me.mid}/locked/$ym').set(true);
                            await audit('মাস ক্লোজ: $ym');
                          });
                        }, child: const Text('ক্লোজ')),
                ),
            ]);
          },
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('ঠিক আছে'))],
      ),
    );
  }

  /// মিটিংয়ে ঠিক করা মিল চার্জ ও চালের নিয়ম
  Future<void> mealRules(BuildContext c) async {
    final cur = m((await db.ref('messes/${Me.mid}/cfg').get()).value);
    final keys = ['pb', 'pl', 'pd', 'rb', 'rl', 'rd'];
    const defs = {'rb': 100, 'rl': 250, 'rd': 150};
    final ctl = {for (final k in keys) k: TextEditingController(text: cur[k] != null ? '${dn(cur[k]) == dn(cur[k]).roundToDouble() ? dn(cur[k]).toInt() : dn(cur[k])}' : (defs[k] != null ? '${defs[k]}' : ''))};
    bool fixed = '${cur['mode']}' != 'rate';
    if (!c.mounted) return;
    await showDialog(
      context: c,
      builder: (_) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('মিল চার্জ ও চালের নিয়ম'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: true, label: Text('ফিক্সড চার্জ')), ButtonSegment(value: false, label: Text('বাজার ÷ মিল'))],
              selected: {fixed}, onSelectionChanged: (s) => set(() => fixed = s.first)),
            const SizedBox(height: 6),
            Text(fixed ? 'মিটিংয়ে ঠিক করা প্রতি মিলের চার্জ। মাস শেষে মশলা/অতিরিক্ত খরচ সবার মধ্যে সমান ভাগ হয়ে যোগ হবে।' : 'মাসের মোট আসল বাজার ÷ মোট মিল = মিল রেট।', style: const TextStyle(fontSize: 12)),
            if (fixed) ...[
              const Text('প্রতি মিলের চার্জ (টাকা)', style: TextStyle(fontWeight: FontWeight.w600)),
              Row(children: [
                for (final e in {'pb': 'সকাল', 'pl': 'দুপুর', 'pd': 'রাত'}.entries) Expanded(child: Padding(padding: const EdgeInsets.all(3), child: TextField(controller: ctl[e.key], keyboardType: TextInputType.number, decoration: InputDecoration(labelText: e.value)))),
              ]),
              const Text('অতিথির মিল দুপুরের চার্জে ধরা হয়।', style: TextStyle(fontSize: 11)),
            ],
            const SizedBox(height: 8),
            const Text('প্রতি মিলে চাল (গ্রাম)', style: TextStyle(fontWeight: FontWeight.w600)),
            Row(children: [
              for (final e in {'rb': 'সকাল', 'rl': 'দুপুর', 'rd': 'রাত'}.entries) Expanded(child: Padding(padding: const EdgeInsets.all(3), child: TextField(controller: ctl[e.key], keyboardType: TextInputType.number, decoration: InputDecoration(labelText: e.value)))),
            ]),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('বাতিল')),
            FilledButton(onPressed: () async {
              await safe(d, () async {
                await db.ref('messes/${Me.mid}/cfg').update({'mode': fixed ? 'fixed' : 'rate', for (final k in keys) k: double.tryParse(ctl[k]!.text.trim()) ?? 0});
                await audit('মিল চার্জ/চালের নিয়ম বদলেছে');
                if (d.mounted) Navigator.pop(d);
              });
            }, child: const Text('সেভ')),
          ],
        ),
      ),
    );
  }

  Future<void> funds(BuildContext c) async {
    final cur = m((await db.ref('messes/${Me.mid}/cfg').get()).value);
    final ctl = {for (final k in ['bill', 'fuel', 'dev']) k: TextEditingController(text: n(cur[k]) == 0 ? '' : '${n(cur[k])}')};
    if (!c.mounted) return;
    await showDialog(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('তহবিলের মাসিক চাঁদা (জনপ্রতি)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('সবাই এই টাকা দেবে, খরচ তহবিল থেকে হবে, বাকি টাকা পরের মাসে জমা থাকবে। না লিখলে বাকি হিসাব হবে না।', style: TextStyle(fontSize: 12)),
          TextField(controller: ctl['bill'], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'বিল (টাকা)')),
          TextField(controller: ctl['fuel'], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'জ্বালানি (টাকা)')),
          TextField(controller: ctl['dev'], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'উন্নয়ন (টাকা)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('বাতিল')),
          FilledButton(onPressed: () async {
            await safe(d, () async {
              await db.ref('messes/${Me.mid}/cfg').update({for (final e in ctl.entries) e.key: double.tryParse(e.value.text.trim()) ?? 0});
              await audit('তহবিলের চাঁদা ঠিক করেছে');
              if (d.mounted) Navigator.pop(d);
            });
          }, child: const Text('সেভ')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext c) => ListView(padding: const EdgeInsets.all(8), children: [
        ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text('${Me.name} (${roles[Me.role]})'), subtitle: Text(auth.currentUser?.email?.split('@').first ?? '')),
        if (mon) ...[
          ListTile(leading: const Icon(Icons.group), title: const Text('সদস্য ও ম্যানেজার'), onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const MembersPage()))),
          ListTile(leading: const Icon(Icons.tune), title: const Text('মিল চার্জ ও চালের নিয়ম'), onTap: () => mealRules(c)),
          ListTile(leading: const Icon(Icons.savings), title: const Text('তহবিলের মাসিক চাঁদা (বিল/জ্বালানি/উন্নয়ন)'), onTap: () => funds(c)),
          ListTile(leading: const Icon(Icons.campaign), title: const Text('নোটিশ বোর্ড'), onTap: () => notice(c)),
          ListTile(leading: const Icon(Icons.lock_clock), title: const Text('মাস ক্লোজ ও ক্যারি ফরওয়ার্ড'), onTap: () => closeMonth(c)),
          ExpansionTile(leading: const Icon(Icons.tune), title: const Text('আরও (কে কী করেছে, ব্যাকআপ)'), children: [
            ListTile(leading: const Icon(Icons.history), title: const Text('কে কী করেছে (লগ)'), onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const AuditPage()))),
            ListTile(leading: const Icon(Icons.backup), title: const Text('ব্যাকআপ কপি করুন'), onTap: () async {
              final v = await db.ref('messes/${Me.mid}').get();
              await Clipboard.setData(ClipboardData(text: jsonEncode(v.value)));
              if (c.mounted) snack(c, 'ব্যাকআপ কপি হয়েছে, কোথাও পেস্ট করে সেভ করুন');
            }),
            ListTile(leading: const Icon(Icons.vpn_key), title: const Text('Mess ID'), subtitle: SelectableText(Me.mid)),
          ]),
        ],
        const Divider(),
        ListTile(
          leading: const Icon(Icons.dark_mode),
          title: const Text('থিম'),
          trailing: ValueListenableBuilder<ThemeMode>(valueListenable: Prefs.theme, builder: (_, v, __) => SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: ThemeMode.system, label: Text('অটো')), ButtonSegment(value: ThemeMode.light, label: Text('দিন')), ButtonSegment(value: ThemeMode.dark, label: Text('রাত'))],
              selected: {v}, onSelectionChanged: (s) => Prefs.setTheme(s.first))),
        ),
        ValueListenableBuilder<bool>(valueListenable: Prefs.bnDigits, builder: (_, v, __) => SwitchListTile(secondary: const Icon(Icons.pin), title: const Text('বাংলা সংখ্যা (১২৩)'), value: v, onChanged: Prefs.setBn)),
        if (Me.role != 'owner') ListTile(leading: const Icon(Icons.forum), title: Text(Me.mon ? 'সদস্যদের অনুরোধ ও মতামত' : 'মনিটরকে অনুরোধ / মতামত'), onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const RequestsPage()))),
        ListTile(leading: const Icon(Icons.lock), title: const Text('পাসওয়ার্ড পরিবর্তন'), onTap: () => pass(c)),
        ListTile(leading: const Icon(Icons.send), title: const Text('যোগাযোগ / লাইসেন্স'), subtitle: const Text(telegramName), onTap: () => openUrl(telegram)),
        ListTile(leading: const Icon(Icons.logout), title: const Text('লগআউট'), onTap: auth.signOut),
        Center(child: footer()),
      ]);
}

class AuditPage extends StatelessWidget {
  const AuditPage({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('অডিট লগ')),
        body: StreamBuilder<DatabaseEvent>(
          stream: db.ref('messes/${Me.mid}/audit').orderByKey().limitToLast(100).onValue,
          builder: (c, s) {
            final l = m(s.data?.snapshot.value).entries.toList()..sort((a, b) => '${b.key}'.compareTo('${a.key}'));
            if (l.isEmpty) return const Empty(Icons.history, 'কিছু নেই');
            return ListView(children: [
              for (final e in l)
                ListTile(dense: true, title: Text('${m(e.value)['act']}'), subtitle: Text('${m(e.value)['by']} • ${bn(DateTime.fromMillisecondsSinceEpoch(n(m(e.value)['ts'])).toString().substring(0, 16))}')),
            ]);
          },
        ),
      );
}

class MembersPage extends StatelessWidget {
  const MembersPage({super.key});

  Widget defRow(Map<String, int> df, StateSetter set) => Row(children: [
        const Text('ডিফল্ট মিল:  '),
        for (final e in {'b': 'সকাল', 'l': 'দুপুর', 'd': 'রাত'}.entries)
          Expanded(child: CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, title: Text(e.value, style: const TextStyle(fontSize: 12)), value: df[e.key] == 1, onChanged: (v) => set(() => df[e.key] = v == true ? 1 : 0))),
      ]);

  Future<void> add(BuildContext c, int count) async {
    final max = n(Me.lic['maxBoarders']);
    if (count >= max) { snack(c, 'সদস্য সীমা ($max) শেষ। আরও লাগলে $telegramName এ যোগাযোগ করুন।'); return; }
    final nm = TextEditingController(), ph = TextEditingController(), ps = TextEditingController(), rent = TextEditingController(text: '0');
    String r = 'boarder';
    final df = {'b': 1, 'l': 1, 'd': 1};
    await showDialog(
      context: c,
      builder: (_) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('সদস্য যোগ'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nm, decoration: const InputDecoration(labelText: 'নাম')),
              TextField(controller: ph, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'মোবাইল (লগইন আইডি)')),
              TextField(controller: ps, decoration: const InputDecoration(labelText: 'পাসওয়ার্ড (কমপক্ষে ৬)')),
              TextField(controller: rent, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'মাসিক ভাড়া')),
              DropdownButtonFormField<String>(value: r, items: [for (final e in roles.entries) if (e.key != 'monitor') DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => set(() => r = v!)),
              defRow(df, set),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('বাতিল')),
            FilledButton(
              onPressed: () async {
                if (nm.text.trim().isEmpty || ph.text.trim().isEmpty || ps.text.length < 6) { snack(d, 'নাম, মোবাইল ও ৬+ অক্ষরের পাসওয়ার্ড দিন'); return; }
                try {
                  final app = await Firebase.initializeApp(name: 's${DateTime.now().millisecondsSinceEpoch}', options: Firebase.app().options);
                  final u = (await FirebaseAuth.instanceFor(app: app).createUserWithEmailAndPassword(email: em(ph.text), password: ps.text)).user!.uid;
                  await app.delete();
                  await db.ref('users/$u').set({'messId': Me.mid, 'role': r, 'name': nm.text.trim(), 'active': true});
                  await db.ref('messes/${Me.mid}/members/$u').set({'name': nm.text.trim(), 'role': r, 'phone': ph.text.trim(), 'active': true, 'rent': double.tryParse(rent.text) ?? 0, 'def': df});
                  await audit('সদস্য যোগ: ${nm.text.trim()} (${roles[r]})');
                  if (d.mounted) Navigator.pop(d);
                } on FirebaseAuthException catch (e) { if (d.mounted) snack(d, e.code == 'email-already-in-use' ? 'এই মোবাইল দিয়ে আগেই অ্যাকাউন্ট আছে' : e.message ?? 'ত্রুটি'); }
                catch (e) { if (d.mounted) snack(d, '$e'); }
              },
              child: const Text('যোগ করুন'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> edit(BuildContext c, String u, Map x) async {
    final rent = TextEditingController(text: dn(x['rent']).toStringAsFixed(0));
    String r = '${x['role']}';
    final df = {'b': n(m(x['def'])['b']), 'l': n(m(x['def'])['l']), 'd': n(m(x['def'])['d'])};
    await showDialog(
      context: c,
      builder: (_) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('${x['name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: rent, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'মাসিক ভাড়া')),
            if (r != 'monitor') DropdownButtonFormField<String>(value: r, items: [for (final e in roles.entries) if (e.key != 'monitor') DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => set(() => r = v!)),
            defRow(df, set),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('বাতিল')),
            FilledButton(onPressed: () async {
              await safe(d, () async {
                await db.ref('messes/${Me.mid}/members/$u').update({'rent': double.tryParse(rent.text) ?? 0, 'role': r, 'def': df});
                if (u != Me.uid) await db.ref('users/$u/role').set(r);
                await audit('সদস্য এডিট: ${x['name']} (${roles[r]})');
                if (d.mounted) Navigator.pop(d);
              });
            }, child: const Text('সেভ')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext c) => StreamBuilder<DatabaseEvent>(
        stream: db.ref('messes/${Me.mid}/members').onValue,
        builder: (c, s) {
          final ms = m(s.data?.snapshot.value);
          return Scaffold(
            appBar: AppBar(title: Text('সদস্য (${bn(ms.length)}/${bn(n(Me.lic['maxBoarders']))})')),
            floatingActionButton: FloatingActionButton(onPressed: () => add(c, ms.length), child: const Icon(Icons.person_add)),
            body: ListView(children: [
              for (final e in ms.entries)
                ListTile(
                  leading: CircleAvatar(child: Text(('${m(e.value)['name']}' + '?').substring(0, 1))),
                  title: Text('${m(e.value)['name']}'),
                  subtitle: Text('${roles[m(e.value)['role']]} • ${m(e.value)['phone'] ?? ''} • ভাড়া ${f0(dn(m(e.value)['rent']))}'),
                  onTap: () => edit(c, '${e.key}', m(e.value)),
                  trailing: e.key == Me.uid ? null : Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(value: m(e.value)['active'] != false, onChanged: (v) async {
                      await safe(c, () async {
                        await db.ref('users/${e.key}/active').set(v);
                        await db.ref('messes/${Me.mid}/members/${e.key}/active').set(v);
                        await audit('${v ? 'চালু' : 'বাতিল'}: ${m(e.value)['name']}');
                      });
                    }),
                    IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async {
                      if (!await confirm(c, 'ডিলিট করবেন? (পুরনো হিসাব থাকবে)')) return;
                      if (!c.mounted) return;
                      await safe(c, () async {
                        await db.ref('users/${e.key}').remove();
                        await db.ref('messes/${Me.mid}/members/${e.key}').remove();
                        await audit('সদস্য ডিলিট: ${m(e.value)['name']}');
                      });
                    }),
                  ]),
                ),
            ]),
          );
        },
      );
}

/// শেয়ার্ড বাজারের তালিকা (সবাই দেখে; মনিটর/মিল ম্যানেজার/বাজারি যোগ-টিক করে)
class BazarListPage extends StatelessWidget {
  const BazarListPage({super.key});
  bool get can => Me.meal || Me.role == 'bazari';
  @override
  Widget build(BuildContext c) {
    final ref = db.ref('messes/${Me.mid}/list');
    return Scaffold(
      appBar: AppBar(title: const Text('বাজারের তালিকা'), actions: [
        if (can) IconButton(tooltip: 'টিক করা মুছুন', icon: const Icon(Icons.cleaning_services), onPressed: () async {
          final s = await ref.get();
          final up = <String, Object?>{for (final e in m(s.value).entries) if (m(e.value)['done'] == true) '${e.key}': null};
          if (up.isNotEmpty && c.mounted) await safe(c, () => ref.update(up));
        }),
      ]),
      floatingActionButton: can ? FloatingActionButton(child: const Icon(Icons.add), onPressed: () async {
        final t = TextEditingController();
        await showDialog(context: c, builder: (d) => AlertDialog(
          title: const Text('কী কিনতে হবে?'),
          content: TextField(controller: t, autofocus: true),
          actions: [FilledButton(onPressed: () async {
            if (t.text.trim().isNotEmpty) await safe(d, () => ref.push().set({'t': t.text.trim(), 'done': false, 'by': Me.name}));
            if (d.mounted) Navigator.pop(d);
          }, child: const Text('যোগ'))],
        ));
      }) : null,
      body: StreamBuilder<DatabaseEvent>(
        stream: ref.onValue,
        builder: (c, s) {
          final l = m(s.data?.snapshot.value).entries.toList();
          if (l.isEmpty) return const Empty(Icons.shopping_cart, 'তালিকা ফাঁকা');
          return ListView(children: [
            for (final e in l)
              CheckboxListTile(
                value: m(e.value)['done'] == true,
                title: Text('${m(e.value)['t']}', style: TextStyle(decoration: m(e.value)['done'] == true ? TextDecoration.lineThrough : null)),
                subtitle: Text('${m(e.value)['by'] ?? ''}'),
                onChanged: can ? (v) => safe(c, () => ref.child('${e.key}/done').set(v == true)) : null,
              ),
          ]);
        },
      ),
    );
  }
}

/// অনুরোধ ও মতামত: সদস্য লেখে, মনিটর দেখে ও নিষ্পত্তি করে
class RequestsPage extends StatelessWidget {
  const RequestsPage({super.key});
  @override
  Widget build(BuildContext c) {
    final ref = db.ref('messes/${Me.mid}/req');
    return Scaffold(
      appBar: AppBar(title: Text(Me.mon ? 'সদস্যদের অনুরোধ ও মতামত' : 'অনুরোধ / মতামত')),
      floatingActionButton: Me.role == 'owner' ? null : FloatingActionButton.extended(
        icon: const Icon(Icons.edit),
        label: const Text('লিখুন'),
        onPressed: () async {
          final t = TextEditingController();
          await showDialog(context: c, builder: (d) => AlertDialog(
            title: const Text('মনিটরকে জানান'),
            content: TextField(controller: t, maxLines: 4, autofocus: true, decoration: const InputDecoration(hintText: 'অনুরোধ, মতামত বা অভিযোগ')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d), child: const Text('বাতিল')),
              FilledButton(onPressed: () async {
                if (t.text.trim().isEmpty) return;
                await safe(d, () => ref.push().set({'t': t.text.trim(), 'by': Me.name, 'byId': Me.uid, 'ts': ServerValue.timestamp, 'done': false}));
                if (d.mounted) Navigator.pop(d);
              }, child: const Text('পাঠান')),
            ],
          ));
        },
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: ref.orderByKey().limitToLast(60).onValue,
        builder: (c, s) {
          final l = m(s.data?.snapshot.value).entries.where((e) => Me.mon || m(e.value)['byId'] == Me.uid).toList()
            ..sort((a, b) => '${b.key}'.compareTo('${a.key}'));
          if (l.isEmpty) return const Empty(Icons.forum, 'কিছু নেই');
          return ListView(padding: const EdgeInsets.only(bottom: 80), children: [
            for (final e in l)
              Card(
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: ListTile(
                  leading: Icon(m(e.value)['done'] == true ? Icons.check_circle : Icons.pending, color: m(e.value)['done'] == true ? Colors.green : Colors.orange),
                  title: Text('${m(e.value)['t']}'),
                  subtitle: Text('${m(e.value)['by']} • ${bn(DateTime.fromMillisecondsSinceEpoch(n(m(e.value)['ts'])).toString().substring(0, 16))}'),
                  trailing: !Me.mon ? null : Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.done), onPressed: () => safe(c, () => ref.child('${e.key}/done').set(m(e.value)['done'] != true))),
                    IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => safe(c, () => ref.child('${e.key}').remove())),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

Future<void> editMenu(BuildContext c) async {
  var dt = DateTime.now();
  final b = TextEditingController(), l = TextEditingController(), d = TextEditingController();
  Future<void> load() async {
    final v = m((await db.ref('messes/${Me.mid}/menu/${ymd(dt)}').get()).value);
    b.text = '${v['b'] ?? ''}'; l.text = '${v['l'] ?? ''}'; d.text = '${v['d'] ?? ''}';
  }
  await load();
  if (!c.mounted) return;
  await showDialog(
    context: c,
    builder: (_) => StatefulBuilder(
      builder: (dc, set) => AlertDialog(
        title: const Text('দিনের মেনু'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(contentPadding: EdgeInsets.zero, title: Text(bn(ymd(dt))), trailing: const Icon(Icons.calendar_month), onTap: () async {
            final p = await showDatePicker(context: dc, initialDate: dt, firstDate: DateTime(2024), lastDate: DateTime(2100));
            if (p != null) { dt = p; await load(); set(() {}); }
          }),
          TextField(controller: b, decoration: const InputDecoration(labelText: 'সকাল')),
          TextField(controller: l, decoration: const InputDecoration(labelText: 'দুপুর')),
          TextField(controller: d, decoration: const InputDecoration(labelText: 'রাত')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc), child: const Text('বাতিল')),
          FilledButton(onPressed: () async {
            await safe(dc, () async {
              final v = {'b': b.text.trim(), 'l': l.text.trim(), 'd': d.text.trim()}..removeWhere((k, x) => x.isEmpty);
              await db.ref('messes/${Me.mid}/menu/${ymd(dt)}').set(v.isEmpty ? null : v);
              if (dc.mounted) Navigator.pop(dc);
            });
          }, child: const Text('সেভ')),
        ],
      ),
    ),
  );
}
