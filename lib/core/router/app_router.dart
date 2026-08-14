import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/app_shell.dart';
import '../../features/discover/presentation/discover_page.dart';
import '../../features/discover/presentation/search_page.dart';
import '../../features/discover/presentation/playlist_detail_page.dart';
import '../../features/library/presentation/library_page.dart';
import '../../features/library/presentation/local_playlist_detail_page.dart';
import '../../features/library/presentation/recently_played_page.dart';
import '../../features/discover/presentation/recognize_page.dart';
import '../../features/local/presentation/tag_editor_page.dart';
import '../../features/settings/presentation/plugin_management_page.dart';
import '../../features/local/presentation/local_page.dart';
import '../../features/download/presentation/download_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/player/presentation/full_player_page.dart';
import '../../features/player/presentation/lyric_page.dart';
import '../constants/app_routes.dart';

final appRouter = GoRouter(
  initialLocation: AppRoutes.discover,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppShell(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.discover,
              builder: (context, state) => const DiscoverPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.library,
              builder: (context, state) => const LibraryPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.local,
              builder: (context, state) => const LocalPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.download,
              builder: (context, state) => const DownloadPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.settings,
              builder: (context, state) => const SettingsPage(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.fullPlayer,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const FullPlayerPage(),
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        },
      ),
    ),
    GoRoute(
      path: AppRoutes.lyric,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const LyricPage(),
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        },
      ),
    ),
    GoRoute(
      path: AppRoutes.search,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const SearchPage(),
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        },
      ),
    ),
    GoRoute(
      path: AppRoutes.playlistDetail,
      pageBuilder: (context, state) {
        final playlistId = state.pathParameters['id'] ?? '';
        return CustomTransitionPage(
          key: state.pageKey,
          child: PlaylistDetailPage(playlistId: playlistId),
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
        );
      },
    ),
    GoRoute(
      path: AppRoutes.localPlaylistDetail,
      pageBuilder: (context, state) {
        final playlistId = state.pathParameters['id'] ?? '';
        return CustomTransitionPage(
          key: state.pageKey,
          child: LocalPlaylistDetailPage(playlistId: playlistId),
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
        );
      },
    ),
    GoRoute(
      path: AppRoutes.recentlyPlayed,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const RecentlyPlayedPage(),
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        },
      ),
    ),
    GoRoute(
      path: AppRoutes.recognize,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const RecognizePage(),
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        },
      ),
    ),
    GoRoute(
      path: AppRoutes.tagEditor,
      pageBuilder: (context, state) {
        final songId = state.uri.queryParameters['songId'];
        return CustomTransitionPage(
          key: state.pageKey,
          child: TagEditorPage(songId: songId),
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
        );
      },
    ),
    GoRoute(
      path: AppRoutes.pluginManagement,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const PluginManagementPage(),
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        },
      ),
    ),
  ],
);
