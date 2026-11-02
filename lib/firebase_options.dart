import 'package:firebase_core/firebase_core.dart';

// google-services.json এর মান এখানে বসান
const firebaseOptions = FirebaseOptions(
  apiKey: 'YOUR_API_KEY',
  appId: 'YOUR_APP_ID',
  messagingSenderId: 'YOUR_SENDER_ID',
  projectId: 'YOUR_PROJECT_ID',
  databaseURL: 'https://YOUR_PROJECT_ID-default-rtdb.firebaseio.com',
);
