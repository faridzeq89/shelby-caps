import 'package:flutter/material.dart';

import 'app.dart';
import 'data/local/database.dart';
import 'services/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  final auth = AuthController(db);
  await auth.ensureSeedAdmin();
  runApp(BoutiquePosApp(auth: auth));
}
