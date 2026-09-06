import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../features/player/domain/models/song.dart';
import '../../features/library/domain/models/playlist.dart';
import '../services/share_poster_generator.dart';
import '../services/share_service.dart';

class SharePreviewDialog extends StatefulWidget {
  final Song? song;
  final Playlist? playlist;

  const SharePreviewDialog({super.key, this.song, this.playlist})
    : assert(song != null || playlist != null, 'song or playlist required');

  static Future<void> show(
    BuildContext context, {
    Song? song,
    Playlist? playlist,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SharePreviewDialog(song: song, playlist: playlist),
    );
  }

  @override
  State<SharePreviewDialog> createState() => _SharePreviewDialogState();
}

class _SharePreviewDialogState extends State<SharePreviewDialog> {
  PosterTemplate _selectedTemplate = PosterTemplate.classic;
  Uint8List? _coverBytes;
  Uint8List? _posterBytes;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  Future<void> _loadCover() async {
    try {
      Uint8List? bytes;
      if (widget.song != null) {
        final url = widget.song!.coverUrl;
        if (url != null && url.isNotEmpty) {
          bytes = await ShareService.downloadCover(url);
        }
      } else if (widget.playlist != null) {
        final url = widget.playlist!.coverImgUrl;
        if (url.isNotEmpty) {
          bytes = await ShareService.downloadCover(url);
        }
      }
      if (mounted) _coverBytes = bytes;
    } catch (_) {
      // cover optional, proceed without
    }
    _generate();
  }

  Future<void> _generate() async {
    setState(() => _isLoading = true);
    try {
      Uint8List? bytes;
      if (widget.song != null) {
        final qr = ShareService.shareQrContent(widget.song!);
        bytes = await SharePosterGenerator.generateSongPoster(
          song: widget.song!,
          coverBytes: _coverBytes,
          template: _selectedTemplate,
          qrContent: qr,
        );
      } else if (widget.playlist != null) {
        bytes = await SharePosterGenerator.generatePlaylistPoster(
          playlist: widget.playlist!,
          coverBytes: _coverBytes,
          template: _selectedTemplate,
        );
      }
      if (mounted) setState(() => _posterBytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _posterBytes = null);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _share() {
    Navigator.pop(context);
    if (widget.song != null) {
      ShareService.shareSong(
        widget.song!,
        coverBytes: _coverBytes,
        template: _selectedTemplate,
      );
    } else if (widget.playlist != null) {
      ShareService.sharePlaylist(widget.playlist!, template: _selectedTemplate);
    }
  }

  void _copyText() {
    final text = widget.song != null
        ? '【薄荷音乐】${widget.song!.title} - ${widget.song!.artist}${_playUrl(widget.song!)}'
        : '【薄荷音乐】${context.tr('分享歌单')}：${widget.playlist!.name}';
    Clipboard.setData(ClipboardData(text: text));
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('已复制到剪贴板')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _playUrl(Song song) {
    final url = ShareService.buildPlayUrl(song);
    return url != null ? '\n$url' : '';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHandle(),
              const SizedBox(height: 8),
              _buildTitle(),
              const SizedBox(height: 16),
              _buildPreview(),
              const SizedBox(height: 16),
              _buildTemplateSelector(),
              const SizedBox(height: 20),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.textHint,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildTitle() {
    return Text(
      context.tr('分享到'),
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildPreview() {
    if (_isLoading) {
      return Container(
        height: 260,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_posterBytes == null) {
      return Container(
        height: 260,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined, color: AppColors.textHint, size: 40),
              const SizedBox(height: 8),
              Text(
                context.tr('海报生成失败'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.memory(
        _posterBytes!,
        height: 260,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildTemplateSelector() {
    final templates = PosterTemplate.values;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: templates.map((t) {
        final selected = t == _selectedTemplate;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: GestureDetector(
            onTap: () {
              if (_selectedTemplate != t) {
                setState(() => _selectedTemplate = t);
                _generate();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                context.tr(_templateLabel(t)),
                style: TextStyle(
                  color: selected ? AppColors.textOnPrimary : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _copyText,
            icon: const Icon(Icons.copy, size: 18),
            label: Text(context.tr('复制文本')),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.divider),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: _share,
            icon: const Icon(Icons.share, size: 18),
            label: Text(context.tr('分享图片')),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _templateLabel(PosterTemplate t) {
    switch (t) {
      case PosterTemplate.classic:
        return '经典';
      case PosterTemplate.minimal:
        return '简约';
      case PosterTemplate.polaroid:
        return '拍立得';
    }
  }
}
