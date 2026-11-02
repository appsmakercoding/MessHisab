# মেস হিসাব (Powered by Hasan)

## চালু করার ধাপ
1. ফোল্ডারে: `flutter create . --platforms=android --org com.hasan.messhisab`
2. Firebase Console: Realtime Database + Authentication (Email/Password) চালু করুন।
3. `lib/firebase_options.dart` এ google-services.json এর মান বসান।
4. Database > Rules এ `database.rules.json` এর লেখা পেস্ট করে Publish করুন।
5. `flutter pub get` তারপর `flutter run` / `flutter build apk --release`

## লাইসেন্স অন করা
ক্রেতা রেজিস্টার করলে Console এ `licenses/{messId}/active = false` তৈরি হয়। সেটি `true` করুন।
ঐচ্ছিক: `expiry` = "2027-01-31", `maxBoarders` বাড়ানো।

## নোট
- সদস্য ডিলিট করলে লগইন আইডি (ফোন নম্বর) আবার ব্যবহার করা যায় না। ছুটি/বাতিলের জন্য সুইচ ব্যবহার করুন।
- PDF-এ বাংলা ফন্ট প্রথমবার ইন্টারনেট থেকে নামে।
