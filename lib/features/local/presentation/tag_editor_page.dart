import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../application/local_providers.dart';
import '../../player/domain/models/song.dart';
import '../../plugin/application/plugin_providers.dart';

class TagEditorPage extends ConsumerStatefulWidget {
  const TagEditorPage({super.key, this.songId});

  final String? songId;

  @override
  ConsumerState<TagEditorPage> createState() => _TagEditorPageState();
}

class _TagEditorPageState extends ConsumerState<TagEditorPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _albumController;
  late TextEditingController _yearController;
  late TextEditingController _genreController;
  late TextEditingController _lrcController;
  late TextEditingController _searchController;

  Song? _song;
  bool _saving = false;
  bool _searching = false;
  List<Song> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _titleController = TextEditingController();
    _artistController = TextEditingController();
    _albumController = TextEditingController();
    _yearController = TextEditingController();
    _genreController = TextEditingController();
    _lrcController = TextEditingController();
    _searchController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSong();
    });
  }

  void _loadSong() {
    final songId = widget.songId;
    if (songId == null || songId.isEmpty) return;

    final repo = ref.read(localMusicRepositoryProvider);
    final song = repo.getSongById(songId);
    if (song != null) {
      setState(() {
        _song = song;
        _titleController.text = song.title;
        _artistController.text = song.artist;
        _albumController.text = song.album;
        _yearController.text = song.year?.toString() ?? '';
        _genreController.text = '';
        _lrcController.text = song.lrc ?? '';
        _searchController.text = song.title;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _yearController.dispose();
    _genreController.dispose();
    _lrcController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeColorsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(colors),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                labelColor: colors.textOnPrimary,
                unselectedLabelColor: colors.textSecondary,
                labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: '编辑信息'),
                  Tab(text: '在线搜索'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildEditTab(colors),
                  _buildSearchTab(colors),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Icon(Icons.close, size: 24, color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '编辑标签',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ),
          if (_song != null)
            GestureDetector(
              onTap: _saving ? null : _handleSave,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: _saving ? colors.textHint : colors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_saving)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.textOnPrimary,
                        ),
                      )
                    else
                      Icon(Icons.check, size: 16, color: colors.textOnPrimary),
                    const SizedBox(width: 4),
                    Text(
                      '保存',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textOnPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEditTab(ThemeColors colors) {
    if (_song == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colors.textHint),
            const SizedBox(height: AppSpacing.md),
            Text('未找到歌曲信息', style: TextStyle(color: colors.textHint)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCoverSection(colors),
          const SizedBox(height: AppSpacing.xl),
          _buildField('歌曲名', _titleController, colors, Icons.music_note),
          _buildField('歌手', _artistController, colors, Icons.person),
          _buildField('专辑', _albumController, colors, Icons.album),
          Row(
            children: [
              Expanded(
                child: _buildField('年份', _yearController, colors, Icons.calendar_today),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildField('流派', _genreController, colors, Icons.category),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _buildLrcSection(colors),
          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }

  Widget _buildCoverSection(ThemeColors colors) {
    return Center(
      child: Column(
        children: [
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              image: _song?.coverUrl != null
                  ? DecorationImage(
                      image: NetworkImage(_song!.coverUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _song?.coverUrl == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.music_note, size: 48, color: colors.primary.withValues(alpha: 0.5)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _song?.hasCover == true ? '有封面' : '无封面',
                        style: TextStyle(fontSize: 11, color: colors.textHint),
                      ),
                    ],
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_song?.filePath != null)
            Text(
              _song!.filePath!.split(RegExp(r'[/\\]')).last,
              style: TextStyle(fontSize: 11, color: colors.textHint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (_song?.bitrate != null && _song!.bitrate! > 0) ...[
            const SizedBox(height: 2),
            Text(
              '${(_song!.bitrate! / 1000).round()} kbps'
              '${_song?.sampleRate != null ? ' · ${(_song!.sampleRate! / 1000).toStringAsFixed(1)} kHz' : ''}'
              '${_song?.channels != null ? ' · ${_song!.channels == 2 ? '立体声' : '单声道'}' : ''}',
              style: TextStyle(fontSize: 11, color: colors.textHint),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    ThemeColors colors,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.textHint,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: controller,
            style: TextStyle(fontSize: 15, color: colors.textPrimary),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 18, color: colors.textHint),
              filled: true,
              fillColor: colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLrcSection(ThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lyrics, size: 16, color: colors.textHint),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '歌词',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textHint,
              ),
            ),
            const Spacer(),
            if (_lrcController.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _lrcController.clear();
                  });
                },
                child: Text(
                  '清空',
                  style: TextStyle(fontSize: 12, color: colors.primary),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          constraints: const BoxConstraints(minHeight: 120, maxHeight: 250),
          child: TextField(
            controller: _lrcController,
            maxLines: null,
            style: TextStyle(
              fontSize: 13,
              color: colors.textPrimary,
              fontFamily: 'monospace',
              height: 1.5,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
              hintText: '输入LRC歌词内容',
              hintStyle: TextStyle(color: colors.textHint, fontSize: 13),
              contentPadding: const EdgeInsets.all(AppSpacing.md),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchTab(ThemeColors colors) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: _buildSearchBar(colors),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: _searching
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: colors.primary),
                      const SizedBox(height: AppSpacing.md),
                      Text('搜索中...', style: TextStyle(color: colors.textHint, fontSize: 14)),
                    ],
                  ),
                )
              : _searchResults.isNotEmpty
                  ? _buildSearchResults(colors)
                  : _buildSearchEmpty(colors),
        ),
      ],
    );
  }

  Widget _buildSearchBar(ThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: colors.textHint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: _searchController,
              onSubmitted: (_) => _handleSearch(),
              decoration: InputDecoration(
                hintText: '输入关键词搜索 (歌曲名 歌手)',
                border: InputBorder.none,
                hintStyle: TextStyle(color: colors.textHint, fontSize: 14),
              ),
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
              },
              child: Icon(Icons.close, size: 18, color: colors.textHint),
            ),
          const SizedBox(width: AppSpacing.xs),
          GestureDetector(
            onTap: _searching ? null : _handleSearch,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                '搜索',
                style: TextStyle(fontSize: 13, color: colors.textOnPrimary, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ThemeColors colors) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: colors.divider),
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        return _buildSearchResultItem(colors, item);
      },
    );
  }

  Widget _buildSearchResultItem(ThemeColors colors, Song item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              image: item.coverUrl != null
                  ? DecorationImage(
                      image: NetworkImage(item.coverUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: item.coverUrl == null
                ? Icon(Icons.music_note, size: 20, color: colors.textHint)
                : null,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        'WY',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.artist}${item.album.isNotEmpty ? ' · ${item.album}' : ''}',
                  style: TextStyle(fontSize: 12, color: colors.textHint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          GestureDetector(
            onTap: () => _applyResult(item),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                '使用',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchEmpty(ThemeColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search, size: 48, color: colors.textHint.withValues(alpha: 0.5)),
          const SizedBox(height: AppSpacing.md),
          Text(
            _searchController.text.isEmpty ? '输入关键词开始搜索' : '未找到相关结果',
            style: TextStyle(color: colors.textHint, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSearch() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    setState(() => _searching = true);

    try {
      final manager = ref.read(musicSourceManagerProvider);
      final results = await manager.search(keyword, sourceId: 'wy', limit: 30);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _searching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _searching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('搜索失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  Future<void> _applyResult(Song result) async {
    setState(() => _saving = true);

    try {
      _titleController.text = result.title.isNotEmpty ? result.title : _titleController.text;
      _artistController.text = result.artist.isNotEmpty ? result.artist : _artistController.text;
      _albumController.text = result.album.isNotEmpty ? result.album : _albumController.text;

      if (result.coverUrl != null && result.coverUrl!.isNotEmpty) {
        setState(() {
          _song = _song?.copyWith(
            coverUrl: result.coverUrl,
            hasCover: true,
          );
        });
      }

      final source = ref.read(musicSourceProvider);
      final lyric = await source.getLyric(result.id);
      if (lyric != null && lyric.isNotEmpty) {
        _lrcController.text = lyric;
      }

      _tabController.animateTo(0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已应用元数据，请检查后保存'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('应用失败: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleSave() async {
    if (_song == null) return;

    setState(() => _saving = true);

    try {
      final updated = _song!.copyWith(
        title: _titleController.text.trim().isEmpty ? null : _titleController.text.trim(),
        artist: _artistController.text.trim().isEmpty ? null : _artistController.text.trim(),
        album: _albumController.text.trim().isEmpty ? null : _albumController.text.trim(),
        year: int.tryParse(_yearController.text.trim()),
        lrc: _lrcController.text.trim().isEmpty ? null : _lrcController.text.trim(),
      );

      await ref.read(localMusicNotifierProvider.notifier).upsertSong(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('标签已保存'), duration: Duration(seconds: 2)),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), duration: Duration(seconds: 2)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
