import 'package:flutter/material.dart';
import 'package:shoepick_staff_app/view/staff_app.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'vm/firebase_staff_auth.dart';

export 'package:shoepick_staff_app/view/staff_app.dart' show MyApp;

/// Firebase 초기화 후 실제 직원 인증을 기존 앱에 주입한다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(MyApp(authRepository: FirebaseStaffAuth()));
}
