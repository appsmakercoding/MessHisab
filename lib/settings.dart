import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'common.dart';
import 'config.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  bool get mon => Me.role == 'monitor';

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

  Future<void> lock(BuildContext c) async {
    final now = DateTime.now();
    final ms = [ymd(now).substring(0, 7), ymd(DateTime(now.year, now.month - 1, 1)).substring(0, 7)];
    await showDialog(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('মাস বন্ধ / চালু'),
        content: StreamBuilder<DatabaseEvent>(
          stream: db.ref('messes/${Me.mid}/locked').onValue,
          builder: (c, s) {
            final lk = m(s.data?.snapshot.value);
            return Column(mainAxisSize: MainAxisSize.min, children: [
              for (final ym in ms)
                SwitchListTile(
                  title: Text('$ym বন্ধ'),
                  value: lk[ym] == true,
                  onChanged: (v) async { await db.ref('messes/${Me.mid}/locked/$ym').set(v ? true : null); await audit('${v ? 'বন্ধ' : 'চালু'} করেছে: $ym'); },
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
        ListTile(leading: const Icon(Icons.badge), title: Text('${Me.name} (${roles[Me.role]})'), subtitle: Text(auth.currentUser?.email?.split('@').first ?? '')),
        if (mon) ...[
          ListTile(leading: const Icon(Icons.group), title: const Text('সদস্য ও ম্যানেজার'), onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const MembersPage()))),
          ListTile(leading: const Icon(Icons.campaign), title: const Text('নোটিশ বোর্ড'), onTap: () => notice(c)),
          ListTile(leading: const Icon(Icons.lock_clock), title: const Text('মাস বন্ধ করুন'), onTap: () => lock(c)),
          ListTile(leading: const Icon(Icons.history), title: const Text('অডিট লগ'), onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const AuditPage()))),
          ListTile(leading: const Icon(Icons.backup), title: const Text('ব্যাকআপ কপি (JSON)'), onTap: () async {
            final v = await db.ref('messes/${Me.mid}').get();
            await Clipboard.setData(ClipboardData(text: jsonEncode(v.value)));
            if (c.mounted) snack(c, 'ব্যাকআপ কপি হয়েছে, কোথাও পেস্ট করে সেভ করুন');
          }),
          ListTile(leading: const Icon(Icons.vpn_key), title: const Text('Mess ID'), subtitle: SelectableText(Me.mid)),
        ],
        ListTile(leading: const Icon(Icons.lock), title: const Text('পাসওয়ার্ড পরিবর্তন'), onTap: () => pass(c)),
        ListTile(leading: const Icon(Icons.send), title: const Text('যোগাযোগ / লাইসেন্স'), subtitle: const Text(telegramName), onTap: () => launchUrl(Uri.parse(telegram), mode: LaunchMode.externalApplication)),
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
          stream: db.ref('messes/${Me.mid}/audit').orderByKey().limitToLast(150).onValue,
          builder: (c, s) {
            final l = m(s.data?.snapshot.value).entries.toList()..sort((a, b) => '${b.key}'.compareTo('${a.key}'));
            return ListView(children: [
              for (final e in l)
                ListTile(
                  dense: true,
                  title: Text('${m(e.value)['act']}'),
                  subtitle: Text('${m(e.value)['by']} • ${DateTime.fromMillisecondsSinceEpoch(n(m(e.value)['ts'])).toString().substring(0, 16)}'),
                ),
            ]);
          },
        ),
      );
}

class MembersPage extends StatelessWidget {
  const MembersPage({super.key});

  Future<void> add(BuildContext c, int count) async {
    final max = n(Me.lic['maxBoarders']);
    if (count >= max) { snack(c, 'সদস্য সীমা ($max) শেষ। আরও লাগলে $telegramName এ যোগাযোগ করুন।'); return; }
    final nm = TextEditingController(), ph = TextEditingController(), ps = TextEditingController(), rent = TextEditingController(text: '0');
    String r = 'boarder';
    await showDialog(
      context: c,
      builder: (_) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('সদস্য যোগ'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nm, decoration: const InputDecoration(labelText: 'নাম')),
              TextField(controller: ph, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'মোবাইল')),
              TextField(controller: ps, decoration: const InputDecoration(labelText: 'পাসওয়ার্ড (কমপক্ষে ৬)')),
              TextField(controller: rent, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'মাসিক ভাড়া')),
              DropdownButtonFormField<String>(value: r, items: [for (final e in roles.entries) if (e.key != 'monitor') DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => set(() => r = v!)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('বাতিল')),
            FilledButton(
              onPressed: () async {
                try {
                  final app = await Firebase.initializeApp(name: 's${DateTime.now().millisecondsSinceEpoch}', options: Firebase.app().options);
                  final u = (await FirebaseAuth.instanceFor(app: app).createUserWithEmailAndPassword(email: em(ph.text), password: ps.text)).user!.uid;
                  await app.delete();
                  await db.ref('users/$u').set({'messId': Me.mid, 'role': r, 'name': nm.text.trim(), 'active': true});
                  await db.ref('messes/${Me.mid}/members/$u').set({'name': nm.text.trim(), 'role': r, 'phone': ph.text.trim(), 'active': true, 'rent': double.tryParse(rent.text) ?? 0});
                  await audit('সদস্য যোগ: ${nm.text.trim()} (${roles[r]})');
                  if (d.mounted) Navigator.pop(d);
                } catch (e) { if (d.mounted) snack(d, '$e'); }
              },
              child: const Text('যোগ করুন'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> edit(BuildContext c, String u, Map x) async {
    final rent = TextEditingController(text: '${dn(x['rent']).toStringAsFixed(0)}');
    String r = '${x['role']}';
    await showDialog(
      context: c,
      builder: (_) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('${x['name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: rent, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'মাসিক ভাড়া')),
            if (r != 'monitor') DropdownButtonFormField<String>(value: r, items: [for (final e in roles.entries) if (e.key != 'monitor') DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => set(() => r = v!)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('বাতিল')),
            FilledButton(onPressed: () async {
              await safe(d, () async {
                await db.ref('messes/${Me.mid}/members/$u').update({'rent': double.tryParse(rent.text) ?? 0, 'role': r});
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
            appBar: AppBar(title: Text('সদস্য (${ms.length}/${n(Me.lic['maxBoarders'])})')),
            floatingActionButton: FloatingActionButton(onPressed: () => add(c, ms.length), child: const Icon(Icons.person_add)),
            body: ListView(children: [
              for (final e in ms.entries)
                ListTile(
                  title: Text('${m(e.value)['name']}'),
                  subtitle: Text('${roles[m(e.value)['role']]} • ${m(e.value)['phone'] ?? ''} • ভাড়া ${dn(m(e.value)['rent']).toStringAsFixed(0)}'),
                  onTap: () => edit(c, '${e.key}', m(e.value)),
                  trailing: e.key == Me.uid ? null : Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(value: m(e.value)['active'] != false, onChanged: (v) async {
                      await db.ref('users/${e.key}/active').set(v);
                      await db.ref('messes/${Me.mid}/members/${e.key}/active').set(v);
                      await audit('${v ? 'চালু' : 'বাতিল'}: ${m(e.value)['name']}');
                    }),
                    IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async {
                      if (!await confirm(c, 'ডিলিট করবেন? (পুরনো হিসাব থাকবে)')) return;
                      await db.ref('users/${e.key}').remove();
                      await db.ref('messes/${Me.mid}/members/${e.key}').remove();
                      await audit('সদস্য ডিলিট: ${m(e.value)['name']}');
                    }),
                  ]),
                ),
            ]),
          );
        },
      );
}
