abstract class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String discover = '/discover';
  static const String library = '/library';
  static const String local = '/local';
  static const String download = '/download';
  static const String settings = '/settings';
  static const String search = '/search';
  static const String playlistDetail = '/playlist/:id';
  static const String localPlaylistDetail = '/library/playlist/:id';
  static const String recentlyPlayed = '/recently-played';
  static const String recognize = '/recognize';
  static const String tagEditor = '/tag-editor';
  static const String pluginManagement = '/plugin-management';
  static const String fullPlayer = '/player/full';
  static const String lyric = '/player/lyric';
}
