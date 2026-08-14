import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/player/application/sleep_timer_provider.dart';

const _sheetAnimationStyle = AnimationStyle(
  duration: Duration(milliseconds: 220),
  reverseDuration: Duration(milliseconds: 180),
);

/// 功能菜单中的「定时关闭」选项行。
/// 定时开启时在右侧显示实时倒计时。
class SleepTimerMenuTile extends ConsumerWidget {
  const SleepTimerMenuTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sleep = ref.watch(sleepTimerProvider);
    return InkWell(
      onTap: () => showSleepTimerPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              sleep.active ? Icons.timer : Icons.timer_outlined,
              size: 22,
              color: sleep.active ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              '定时关闭',
              style: TextStyle(
                fontSize: 15,
                color: sleep.active ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            if (sleep.active) ...[
              Text(
                formatSleepTimerRemaining(sleep.remaining),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}

/// 打开定时关闭设置窗口。窗口内实时显示剩余倒计时。
Future<void> showSleepTimerPicker(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    sheetAnimationStyle: _sheetAnimationStyle,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => const _SleepTimerPickerSheet(),
  );
}

class _SleepTimerPickerSheet extends ConsumerStatefulWidget {
  const _SleepTimerPickerSheet();

  @override
  ConsumerState<_SleepTimerPickerSheet> createState() =>
      _SleepTimerPickerSheetState();
}

class _SleepTimerPickerSheetState extends ConsumerState<_SleepTimerPickerSheet> {
  final _hourCtrl = TextEditingController();
  final _minCtrl = TextEditingController();

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sleep = ref.watch(sleepTimerProvider);
    final notifier = ref.read(sleepTimerProvider.notifier);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '定时关闭',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            // 已设定时：实时显示剩余倒计时
            if (sleep.active) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.timer,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '剩余 ${formatSleepTimerRemaining(sleep.remaining)} 后自动暂停',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            _timerOption(ctx: context, label: '15分钟', duration: const Duration(minutes: 15)),
            _timerOption(ctx: context, label: '30分钟', duration: const Duration(minutes: 30)),
            _timerOption(ctx: context, label: '60分钟', duration: const Duration(minutes: 60)),
            _timerOption(ctx: context, label: '90分钟', duration: const Duration(minutes: 90)),
            _timerOption(ctx: context, label: '关闭', duration: Duration.zero),
            const Divider(height: 1, indent: 16, endIndent: 16),
            // 自定义输入
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.edit, size: 20, color: AppColors.textSecondary),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _hourCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '0',
                        labelText: '时',
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _minCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '30',
                        labelText: '分',
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () {
                      final h = int.tryParse(_hourCtrl.text) ?? 0;
                      final m = int.tryParse(_minCtrl.text) ?? 0;
                      final total = h * 60 + m;
                      if (total > 0) {
                        notifier.start(Duration(minutes: total));
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('确定'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _timerOption({
    required BuildContext ctx,
    required String label,
    required Duration duration,
  }) {
    return ListTile(
      leading: const Icon(Icons.timer_outlined, color: AppColors.textSecondary),
      title: Text(label, style: const TextStyle(color: AppColors.textPrimary)),
      onTap: () {
        Navigator.pop(ctx);
        if (duration > Duration.zero) {
          ref.read(sleepTimerProvider.notifier).start(duration);
        } else {
          ref.read(sleepTimerProvider.notifier).cancel();
        }
      },
    );
  }
}
