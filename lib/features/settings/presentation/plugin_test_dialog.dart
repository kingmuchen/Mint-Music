import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../../plugin/application/plugin_providers.dart';
import '../../plugin/application/plugin_test_service.dart';
import '../domain/models/plugin_info.dart';

/// 音源插件测试弹窗。
///
/// 输入测试曲目（格式：歌名-歌手，默认"江南-林俊杰"）后，逐音源逐音质
/// 验证该插件能否解析出可正常播放的链接，并在弹窗内展示 √/× 结果。
class PluginTestDialog extends ConsumerStatefulWidget {
  final PluginInfo plugin;

  const PluginTestDialog({super.key, required this.plugin});

  @override
  ConsumerState<PluginTestDialog> createState() => _PluginTestDialogState();
}

class _PluginTestDialogState extends ConsumerState<PluginTestDialog> {
  static const _defaultTrack = '江南-林俊杰';

  late final TextEditingController _trackController;
  PluginTestReport? _report;
  bool _starting = false;
  bool _stopRequested = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _trackController = TextEditingController(text: _defaultTrack);
  }

  @override
  void dispose() {
    _trackController.dispose();
    _stopRequested = true;
    final report = _report;
    // 运行中的测试由 runTest 的 finally 释放运行时，这里只处理未运行的。
    if (report != null && !report.running) {
      ref.read(pluginTestServiceProvider).discard(report);
    }
    super.dispose();
  }

  Future<void> _startTest() async {
    final keyword = _trackController.text.trim();
    if (keyword.isEmpty) {
      setState(() => _error = '请输入测试曲目');
      return;
    }

    setState(() {
      _starting = true;
      _stopRequested = false;
      _error = null;
      _report = null;
    });

    final service = ref.read(pluginTestServiceProvider);
    final PluginTestReport report;
    try {
      report = await service.prepareReport(widget.plugin);
    } catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
      return;
    }

    if (!mounted) {
      service.discard(report);
      return;
    }
    setState(() => _report = report);

    await service.runTest(
      report: report,
      keyword: keyword,
      onChanged: () {
        if (mounted) setState(() {});
      },
      isCancelled: () => _stopRequested || !mounted,
    );
    if (mounted) setState(() => _starting = false);
  }

  void _stopTest() {
    setState(() => _stopRequested = true);
  }

  void _restartTest() {
    setState(() {
      _stopRequested = false;
      _report = null;
      _error = null;
    });
    _startTest();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeColorsProvider);
    final report = _report;
    final running = _starting || (report?.running ?? false);

    return Dialog(
      backgroundColor: colors.surface,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(colors),
            Divider(height: 1, color: colors.divider),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTrackInput(colors, running),
                    const SizedBox(height: AppSpacing.md),
                    if (_error != null) _buildError(colors),
                    if (report == null && _starting) _buildLoading(colors),
                    if (report != null) ...[
                      _buildSummary(colors, report),
                      const SizedBox(height: AppSpacing.md),
                      ...report.sources.map(
                        (source) => _buildSourceCard(colors, source),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: colors.divider),
            _buildActions(colors, running),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.bug_report_outlined, size: 20, color: colors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '插件测试',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  widget.plugin.name,
                  style: TextStyle(fontSize: 12, color: colors.textHint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 20, color: colors.textHint),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackInput(ThemeColors colors, bool running) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _trackController,
          enabled: !running,
          style: TextStyle(fontSize: 14, color: colors.textPrimary),
          decoration: InputDecoration(
            labelText: '测试曲目',
            hintText: '格式：歌名-歌手',
            hintStyle: TextStyle(fontSize: 13, color: colors.textHint),
            labelStyle: TextStyle(fontSize: 13, color: colors.textSecondary),
            prefixIcon: Icon(
              Icons.music_note_outlined,
              color: colors.textHint,
              size: 20,
            ),
            filled: true,
            fillColor: colors.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: colors.primary),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '将逐音源逐音质验证该插件能否解析并播放测试曲目',
          style: TextStyle(fontSize: 11, color: colors.textHint),
        ),
      ],
    );
  }

  Widget _buildError(ThemeColors colors) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: colors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _error ?? '',
              style: TextStyle(fontSize: 12, color: colors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(ThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: Column(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '正在加载插件…',
              style: TextStyle(fontSize: 12, color: colors.textHint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(ThemeColors colors, PluginTestReport report) {
    if (report.running) {
      final doneSources =
          report.sources
              .where(
                (s) =>
                    s.status == PluginTestSourceStatus.done ||
                    s.status == PluginTestSourceStatus.failed,
              )
              .length;
      return Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '测试中 $doneSources/${report.sources.length} 个音源…',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
          Text(
            '${report.passedQualityCount}/${report.totalQualityCount} 音质通过',
            style: TextStyle(fontSize: 12, color: colors.primary),
          ),
        ],
      );
    }

    final stopMark = report.cancelled ? '（已停止）' : '';
    final allPass =
        report.availableSourceCount == report.sources.length &&
        report.sources.isNotEmpty;
    return Row(
      children: [
        Icon(
          allPass ? Icons.check_circle : Icons.info_outline,
          size: 16,
          color: allPass ? colors.success : colors.warning,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            '测试完成$stopMark：${report.availableSourceCount}/${report.sources.length} 音源可用 · '
            '${report.passedQualityCount}/${report.totalQualityCount} 音质通过',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceCard(ThemeColors colors, PluginTestSourceResult source) {
    final knownSourceIds = const ['wy', 'kg', 'kw', 'tx', 'mg'];
    final showIdBadge =
        knownSourceIds.contains(source.sourceId) &&
        source.sourceName != source.sourceId;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        source.sourceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (showIdBadge) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${source.sourceId}源',
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _buildSourceBadge(colors, source),
            ],
          ),
          if (source.matchText != null) ...[
            const SizedBox(height: 4),
            Text(
              source.status == PluginTestSourceStatus.failed
                  ? source.matchText!
                  : '匹配：${source.matchText}',
              style: TextStyle(
                fontSize: 11,
                color:
                    source.status == PluginTestSourceStatus.failed
                        ? colors.warning
                        : colors.textHint,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: source.qualities
                .map((quality) => _buildQualityChip(colors, quality))
                .toList(),
          ),
          _buildFailureNotes(colors, source),
        ],
      ),
    );
  }

  Widget _buildSourceBadge(ThemeColors colors, PluginTestSourceResult source) {
    switch (source.status) {
      case PluginTestSourceStatus.pending:
        return Text(
          '待测试',
          style: TextStyle(fontSize: 11, color: colors.textHint),
        );
      case PluginTestSourceStatus.searching:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 4),
            Text('搜索中', style: TextStyle(fontSize: 11, color: colors.primary)),
          ],
        );
      case PluginTestSourceStatus.testing:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 4),
            Text('测试中', style: TextStyle(fontSize: 11, color: colors.primary)),
          ],
        );
      case PluginTestSourceStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.close, size: 14, color: colors.error),
            Text('0/${source.qualities.length}', style: TextStyle(fontSize: 11, color: colors.error)),
          ],
        );
      case PluginTestSourceStatus.done:
        final allPass = source.passedCount == source.qualities.length;
        final color = source.passedCount == 0
            ? colors.error
            : (allPass ? colors.success : colors.warning);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              source.passedCount == 0 ? Icons.close : Icons.check,
              size: 14,
              color: color,
            ),
            Text(
              '${source.passedCount}/${source.qualities.length}',
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        );
    }
  }

  Widget _buildQualityChip(
    ThemeColors colors,
    PluginTestQualityResult quality,
  ) {
    final Widget icon;
    final Color color;
    switch (quality.status) {
      case PluginTestItemStatus.pending:
        icon = Icon(
          Icons.radio_button_unchecked,
          size: 12,
          color: colors.textHint,
        );
        color = colors.textHint;
      case PluginTestItemStatus.running:
        icon = SizedBox(
          width: 11,
          height: 11,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: colors.primary,
          ),
        );
        color = colors.primary;
      case PluginTestItemStatus.passed:
        icon = Icon(Icons.check, size: 13, color: colors.success);
        color = colors.success;
      case PluginTestItemStatus.failed:
        icon = Icon(Icons.close, size: 13, color: colors.error);
        color = colors.error;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 3),
          Text(
            quality.quality,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildFailureNotes(
    ThemeColors colors,
    PluginTestSourceResult source,
  ) {
    final notes =
        source.qualities
            .where(
              (q) => q.status == PluginTestItemStatus.failed && q.note != null,
            )
            .map((q) => '${q.quality}: ${q.note}')
            .toList();
    if (notes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        notes.join('；'),
        style: TextStyle(fontSize: 10.5, color: colors.textHint, height: 1.3),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildActions(ThemeColors colors, bool running) {
    final report = _report;
    final finished = report != null && report.finished && !_starting;

    Widget child;
    if (running) {
      child = SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _stopRequested ? null : _stopTest,
          icon: _stopRequested
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                )
              : const Icon(Icons.stop_circle_outlined, size: 18),
          label: Text(_stopRequested ? '停止中…' : '停止测试'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.error,
            side: BorderSide(color: colors.error.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
        ),
      );
    } else if (finished) {
      child = Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _restartTest,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重新测试'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.textOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: colors.textSecondary,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              child: const Text('关闭'),
            ),
          ),
        ],
      );
    } else {
      child = SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _startTest,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('开始测试'),
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: colors.textOnPrimary,
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: child,
    );
  }
}
