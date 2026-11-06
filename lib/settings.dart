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
                              'fund': {'bill': k.fundLeft('bill', k.bin.values.fold(0.0, (a, b) => a + b), k.bill), 'fuel': k.fundLeft('fuel', k.fin.values.fold(0.0, (a, b) => a + b), k.fuel), 'dev': k.fundLeft('dev', k.din.values.fold(0.0, (a, b) => a + b), k.dev)},
                              'rate': double.parse(k.rate.toStringAsFixed(2)), 'meals': k.total,
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

  @override
  Widget build(BuildContext c) => ListView(padding: const EdgeInsets.all(8), children: [
        ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text('${Me.name} (${roles[Me.role]})'), subtitle: Text(auth.currentUser?.email?.split('@').first ?? '')),
        if (mon) ...[
          ListTile(leading: const Icon(Icons.group), title: const Text('সদস্য ও ম্যানেজার'), onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const MembersPage()))),
          ListTile(leading: const Icon(Icons.campaign), title: const Text('নোটিশ বোর্ড'), onTap: () => notice(c)),
          ListTile(leading: const Icon(Icons.lock_clock), title: const Text('মাস ক্লোজ ও ক্যারি ফরওয়ার্ড'), onTap: () => closeMonth(c)),
          ListTile(leading: const Icon(Icons.history), title: const Text('অডিট লগ'), onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const AuditPage()))),
          ListTile(leading: const Icon(Icons.backup), title: const Text('ব্যাকআপ কপি (JSON)'), onTap: () async {
            final v = await db.ref('messes/${Me.mid}').get();
            await Clipboard.setData(ClipboardData(text: jsonEncode(v.value)));
            if (c.mounted) snack(c, 'ব্যাকআপ কপি হয়েছে, কোথাও পেস্ট করে সেভ করুন');
          }),
          ListTile(leading: const Icon(Icons.vpn_key), title: const Text('Mess ID'), subtitle: SelectableText(Me.mid)),
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
