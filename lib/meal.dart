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
  bool get edit => Me.role == 'monitor' || Me.role == 'meal';
  void shift(int k) => setState(() => d = d.add(Duration(days: k)));
  @override
  Widget build(BuildContext c) {
    final ds = ymd(d), mid = Me.mid, tom = ymd(DateTime.now().add(const Duration(days: 1)));
    const names = {'b': 'সকাল', 'l': 'দুপুর', 'd': 'রাত'};
    return StreamBuilder<DatabaseEvent>(
      stream: db.ref('messes/$mid/members').onValue,
      builder: (c, s1) => StreamBuilder<DatabaseEvent>(
        stream: db.ref('messes/$mid/meals/$ds').onValue,
        builder: (c, s2) => StreamBuilder<DatabaseEvent>(
          stream: db.ref('messes/$mid/off').onValue,
          builder: (c, s3) {
            final ms = m(s1.data?.snapshot.value), ml = m(s2.data?.snapshot.value), off = m(s3.data?.snapshot.value);
            final myOff = m(off[tom])[Me.uid] == true;
            return Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(onPressed: () => shift(-1), icon: const Icon(Icons.chevron_left)),
                TextButton(
                  onPressed: () async {
                    final p = await showDatePicker(context: c, initialDate: d, firstDate: DateTime(2024), lastDate: DateTime(2100));
                    if (p != null) setState(() => d = p);
                  },
                  child: Text(ds, style: const TextStyle(fontSize: 18)),
                ),
                IconButton(onPressed: () => shift(1), icon: const Icon(Icons.chevron_right)),
              ]),
              SwitchListTile(
                title: Text('আগামীকাল ($tom) আমার মিল বন্ধ'),
                value: myOff,
                onChanged: (v) => safe(c, () => db.ref('messes/$mid/off/$tom/${Me.uid}').set(v ? true : null)),
              ),
              if (edit) const Padding(padding: EdgeInsets.all(4), child: Text('ট্যাপ করলে মিল বাড়বে (০-৩)', style: TextStyle(fontSize: 12))),
              Expanded(
                child: ListView(children: [
                  for (final e in ms.entries)
                    if (m(e.value)['active'] != false)
                      Card(
                        child: ListTile(
                          title: Row(children: [Text('${m(e.value)['name']}'), if (m(off[ds])[e.key] == true) const Padding(padding: EdgeInsets.only(left: 8), child: Chip(label: Text('অফ চেয়েছে'), visualDensity: VisualDensity.compact))]),
                          subtitle: Wrap(spacing: 6, children: [
                            for (final k in names.keys)
                              ActionChip(
                                label: Text('${names[k]} ${n(m(ml[e.key])[k])}'),
                                onPressed: edit ? () => safe(c, () => db.ref('messes/$mid/meals/$ds/${e.key}/$k').set((n(m(ml[e.key])[k]) + 1) % 4)) : null,
                              ),
                          ]),
                        ),
                      ),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
