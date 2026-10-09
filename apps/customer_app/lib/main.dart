import 'package:flutter/material.dart';
import 'app/shupick_app.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'vm/firebase_account.dart';

/// 앱 실행 전에 Firebase를 준비하고 실제 인증 구현을 주입한다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(ShupickApp(accountRepository: FirebaseAccount()));
}
