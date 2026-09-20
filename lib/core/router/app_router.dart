import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_page.dart';
import '../../features/import/presentation/import_page.dart';
import '../../features/study/presentation/study_page.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomePage()),
    GoRoute(path: '/import', builder: (context, state) => const ImportPage()),
    GoRoute(path: '/study', builder: (context, state) => const StudyPage()),
  ],
);
