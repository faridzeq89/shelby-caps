import 'package:flutter/material.dart';

import 'app.dart';
import 'data/local/database.dart';
import 'data/seed.dart';
import 'services/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  final auth = AuthController(db);
  await auth.ensureSeedAdmin();
  await SeedService(db).run();
  runApp(BoutiquePosApp(auth: auth, db: db));
}
