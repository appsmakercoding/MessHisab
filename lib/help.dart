import 'package:flutter/material.dart';
import 'common.dart';
import 'config.dart';

/// পাসওয়ার্ড ভুলে গেলে কী করবেন
void forgotDialog(BuildContext c) => showDialog(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('পাসওয়ার্ড ভুলে গেছেন?'),
        content: const Text('সদস্য হলে মনিটরকে জানান। মনিটর হলে নিচের বাটনে সাপোর্টে যোগাযোগ করুন, আপনার নম্বর ও মেসের নাম জানাবেন। যাচাই করে অ্যাকাউন্ট নতুন করে চালু করে দেওয়া হবে।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('বন্ধ')),
          FilledButton(onPressed: () => openUrl(telegram), child: const Text('সাপোর্টে যোগাযোগ')),
        ],
      ),
    );

class _Sec extends StatelessWidget {
  final String t;
  final List<String> l;
  const _Sec(this.t, this.l);
  @override
  Widget build(BuildContext c) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 6),
            for (final x in l) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $x', style: const TextStyle(height: 1.4))),
          ]),
        ),
      );
}

/// ব্যবহার গাইড
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('ব্যবহার গাইড')),
        body: ListView(padding: const EdgeInsets.all(14), children: const [
          _Sec('শুরু করার ধাপ (মনিটর)', [
            'সেটিংস থেকে "মিল চার্জ নিয়ম" ঠিক করুন: নির্দিষ্ট মিল চার্জ নাকি বাজার ÷ মিল।',
            'সদস্য যোগ করুন (নাম, মোবাইল, পাসওয়ার্ড, রোল)।',
            'বিল ও খাত থেকে বিদ্যুৎ, ওয়াইফাই, উন্নয়ন ইত্যাদি বিল তৈরি করুন।',
            'প্রতিদিন মিল ও বাজার এন্ট্রি হবে, রিপোর্টে সব হিসাব দেখা যাবে।',
          ]),
          _Sec('রোল অনুযায়ী কাজ', [
            'মনিটর: সব কিছু দেখে ও নিয়ন্ত্রণ করে।',
            'মিল ম্যানেজার: মিল, টাকা জমা, বাজার অনুমোদন।',
            'বাজারি: শুধু বাজারের খরচ লেখে, অনুমোদন পেলে হিসাবে ধরা হয়।',
            'বিল / জ্বালানি / উন্নয়ন ম্যানেজার: নিজের বিলের টাকা তোলে ও খরচ লেখে।',
            'সাধারণ সদস্য: নিজের মিল, হিসাব ও রিপোর্ট দেখে।',
          ]),
          _Sec('মাস শেষে', [
            'সেটিংস থেকে "মিল ক্লোজ ও জের টানা" চাপুন, এতে মিলের পাওনা/দেনা পরের মাসে যায়।',
            'প্রতিটি বিলে আলাদা করে "ক্লোজ" বা "নতুন চক্র" চাপুন, হাতে থাকা টাকা জের হয়ে নতুন চক্রে যাবে।',
            'রিপোর্টের "ফুল এন্ড ফাইনাল" থেকে কে কত দেবে দেখে PDF বা হোয়াটসঅ্যাপে পাঠান।',
          ]),
          _Sec('ভুল হলে', [
            'এন্ট্রি ভুল হলে এন্ট্রি তালিকা থেকে সংশোধন বা মুছুন (মাস ক্লোজের আগে পর্যন্ত)।',
            'ইন্টারনেট না থাকলেও লেখা যায়, নেট এলে নিজে থেকে সিঙ্ক হয়।',
          ]),
        ]),
      );
}

/// গোপনীয়তা ও শর্ত
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('গোপনীয়তা ও শর্ত')),
        body: ListView(padding: const EdgeInsets.all(14), children: const [
          _Sec('আমরা কী রাখি', [
            'নাম, মোবাইল নম্বর (লগইনের জন্য) এবং মেসের মিল, জমা, খরচ ও বিলের হিসাব।',
            'ছবি, ফাইল, লোকেশন বা কন্টাক্ট আমরা নিই না।',
          ]),
          _Sec('কে দেখতে পারে', [
            'একটি মেসের তথ্য শুধু সেই মেসের সদস্যরা, রোল অনুযায়ী দেখতে পারে।',
            'অন্য মেসের কেউ আপনার হিসাব দেখতে পারে না।',
            'তথ্য কোনো তৃতীয় পক্ষের কাছে বিক্রি বা বিজ্ঞাপনে ব্যবহার করা হয় না।',
          ]),
          _Sec('ব্যবহারের শর্ত', [
            'হিসাবের সঠিকতার দায়িত্ব মেসের মনিটর ও ম্যানেজারদের। এন্ট্রি দেওয়ার আগে যাচাই করুন।',
            'লাইসেন্সের মেয়াদ শেষ বা বন্ধ হলে অ্যাপ লক হয়ে যেতে পারে, ডেটা মুছে যায় না।',
            'নিয়মিত PDF বা ব্যাকআপ রাখার পরামর্শ দেওয়া হয়।',
          ]),
          _Sec('তথ্য মোছা', [
            'অ্যাকাউন্ট বা মেসের তথ্য মুছতে চাইলে সাপোর্টে যোগাযোগ করুন: $telegramName',
          ]),
        ]),
      );
}
