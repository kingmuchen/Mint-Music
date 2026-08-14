import 'dart:collection';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class MusicCoverImage extends StatefulWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;
  final int? cacheWidth;
  final int? cacheHeight;
  final FilterQuality filterQuality;

  const MusicCoverImage({
    super.key,
    this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
    this.cacheWidth,
    this.cacheHeight,
    this.filterQuality = FilterQuality.medium,
  });

  @override
  State<MusicCoverImage> createState() => _MusicCoverImageState();
}

class _MusicCoverImageState extends State<MusicCoverImage> {
  // Keep the decoded image cache bounded by bytes. A count-only limit can
  // retain hundreds of large covers on low-memory devices.
  static final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  static final Map<String, List<void Function(Uint8List)>> _pending = {};
  static const int _maxCacheBytes = 24 * 1024 * 1024;
  static int _cacheBytes = 0;

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  static final Dio _refererDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Referer': 'https://music.163.com',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
      },
    ),
  );

  Uint8List? _bytes;
  bool _loading = true;
  String? _lastUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MusicCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _load();
    }
  }

  void _load() {
    final url = widget.url;
    if (url == null || url.isEmpty) {
      setState(() {
        _loading = false;
        _bytes = null;
      });
      return;
    }

    var imageUrl = url;
    final needsReferer = imageUrl.contains('music.126.net');
    if (needsReferer && imageUrl.startsWith('http://')) {
      imageUrl = 'https://${imageUrl.substring(7)}';
    }
    // Kuwo's official CDN is stable over HTTP, while some CDN nodes present
    // an HTTPS certificate whose hostname does not match on Android.
    if (imageUrl.contains('kwcdn.kuwo.cn') && imageUrl.startsWith('https://')) {
      imageUrl = 'http://${imageUrl.substring(8)}';
    }

    if (_lastUrl == imageUrl && _bytes != null) return;
    _lastUrl = imageUrl;

    final cached = _cache.remove(imageUrl);
    if (cached != null) {
      _cache[imageUrl] = cached;
      setState(() {
        _bytes = cached;
        _loading = false;
      });
      return;
    }

    if (_pending.containsKey(imageUrl)) {
      _pending[imageUrl]!.add((bytes) {
        if (mounted && _lastUrl == imageUrl) {
          setState(() {
            _bytes = bytes;
            _loading = false;
          });
        }
      });
      return;
    }

    _pending[imageUrl] = [];
    _loading = true;

    _fetchImage(imageUrl, needsReferer);
  }

  Future<void> _fetchImage(String imageUrl, bool needsReferer) async {
    try {
      final dio = needsReferer ? _refererDio : _dio;

      final response = await dio.get<List<int>>(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.data == null) {
        _onError(imageUrl);
        return;
      }

      final bytes = Uint8List.fromList(response.data!);

      if (bytes.length <= _maxCacheBytes) {
        while (_cacheBytes + bytes.length > _maxCacheBytes &&
            _cache.isNotEmpty) {
          final oldestKey = _cache.keys.first;
          final oldest = _cache.remove(oldestKey);
          if (oldest != null) _cacheBytes -= oldest.length;
        }
        _cache[imageUrl] = bytes;
        _cacheBytes += bytes.length;
      }

      if (mounted && _lastUrl == imageUrl) {
        setState(() {
          _bytes = bytes;
          _loading = false;
        });
      }

      final callbacks = _pending.remove(imageUrl);
      if (callbacks != null) {
        for (final cb in callbacks) {
          cb(bytes);
        }
      }
    } catch (e) {
      _onError(imageUrl);
    }
  }

  void _onError(String imageUrl) {
    _pending.remove(imageUrl);
    if (mounted && _lastUrl == imageUrl) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep drawing the previous decoded cover while a new song's cover is
    // downloading. Replacing it with a placeholder for one or two frames is
    // especially visible in the full-player background during next/previous.
    if (_loading && _bytes == null) {
      return widget.errorWidget ?? _buildPlaceholder();
    }

    if (_bytes == null) {
      return widget.errorWidget ?? _buildPlaceholder();
    }

    final image = Image.memory(
      _bytes!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      cacheWidth: widget.cacheWidth ?? _decodeDimension(widget.width),
      cacheHeight: widget.cacheHeight ?? _decodeDimension(widget.height),
      filterQuality: widget.filterQuality,
    );

    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: image);
    }

    return image;
  }

  static int _decodeDimension(double? dimension) {
    if (dimension == null || !dimension.isFinite || dimension <= 0) {
      // Most callers are cards and list rows. Full-player artwork supplies
      // an explicit cache size, so decoding every unspecified cover at 1024px
      // only wastes memory and makes scrolling stutter on low-end devices.
      return 512;
    }
    return (dimension * 2).round().clamp(64, 1024);
  }

  Widget _buildPlaceholder() {
    if (widget.placeholder != null) return widget.placeholder!;
    final container = Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey.withValues(alpha: 0.15),
      child: Icon(
        Icons.music_note,
        size: (widget.width ?? 48) * 0.5,
        color: Colors.grey.withValues(alpha: 0.4),
      ),
    );
    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: container);
    }
    return container;
  }
}
