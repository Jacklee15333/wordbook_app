// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  home_screen.dart  v4.0  2026-03-07                                 ║
// ║  v4: 今日任务逻辑透明化 / 从后端同步 daily_new_words /              ║
// ║       进度卡显示词书名 / 数据来源清晰标注                            ║
// ╚═══════════════════════════════════════════════════════════════════════╝

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/study_provider.dart';
import '../../services/api_service.dart';
import '../study/study_screen.dart';
import '../wordbook/wordbook_list_screen.dart';

const String _kHomeVersion = '📦 home_screen v4.0 (2026-03-07)';

void _log(String msg) {
  debugPrint('[HOME-v4] $msg');
}

final selectedWordbookProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

final wordbooksProvider = FutureProvider<List<dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getWordbooks();
});

final progressProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, wordbookId) async {
  final api = ref.read(apiServiceProvider);
  return api.getProgress(wordbookId);
});

// ★ v4.0: 初始值 -1 代表"尚未从后端加载"
final dailyNewWordsProvider = StateProvider<int>((ref) => -1);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isSavingPlan = false;

  @override
  void initState() {
    super.initState();
    _log('✅ $_kHomeVersion  已加载');
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final wordbooks = await ref.read(wordbooksProvider.future);
    _log('📚 加载了 ${wordbooks.length} 本词书');
    if (wordbooks.isNotEmpty && ref.read(selectedWordbookProvider) == null) {
      ref.read(selectedWordbookProvider.notifier).state =
          Map<String, dynamic>.from(wordbooks.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final selectedWb = ref.watch(selectedWordbookProvider);
    final study = ref.watch(studyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('单词本'),
        actions: [
          IconButton(
            icon: const Icon(Icons.book_outlined),
            tooltip: '词书管理',
            onPressed: () async {
              await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const WordbookListScreen()));
              if (selectedWb != null) {
                ref.read(studyProvider.notifier).loadTodayTask(selectedWb['id']);
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.person_outline),
            onSelected: (v) {
              if (v == 'logout') ref.read(authProvider.notifier).logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(auth.nickname ?? auth.email ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'logout', child: Text('退出登录')),
            ],
          ),
        ],
      ),
      body: selectedWb == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(wordbooksProvider);
                ref.invalidate(progressProvider(selectedWb['id']));
                await ref.read(studyProvider.notifier).loadTodayTask(selectedWb['id']);
              },
              child: _buildBody(context, selectedWb, study),
            ),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> wb, StudyState study) {
    if (study.isLoading && study.totalWords == 0) {
      Future.microtask(() {
        ref.read(studyProvider.notifier).loadTodayTask(wb['id']);
      });
      return const Center(child: CircularProgressIndicator());
    }

    final progress = ref.watch(progressProvider(wb['id']));

    // ★ v4.0: 从后端进度接口同步 daily_new_words，保证 UI 与后端一致
    progress.whenData((p) {
      final backendDailyWords = p['daily_new_words'] as int? ?? 20;
      final currentLocal = ref.read(dailyNewWordsProvider);
      if (currentLocal < 1) {
        _log('🔄 初始化 daily_new_words from backend: $backendDailyWords');
        Future.microtask(() {
          if (mounted) {
            ref.read(dailyNewWordsProvider.notifier).state = backendDailyWords;
          }
        });
      }
    });

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _kHomeVersion,
            style: const TextStyle(fontSize: 11, color: AppColors.success),
            textAlign: TextAlign.center,
          ),
        ),

        _buildWordbookCard(wb),
        const SizedBox(height: 20),

        progress.when(
          data: (p) => _buildStudyPlanCard(wb, p['total_words'] ?? 0, p['daily_new_words'] ?? 20),
          loading: () => _buildStudyPlanCard(wb, wb['word_count'] ?? 0, 20),
          error: (_, __) => _buildStudyPlanCard(wb, wb['word_count'] ?? 0, 20),
        ),
        const SizedBox(height: 20),

        progress.when(
          data: (p) => _buildTodayCard(context, study, wb['id'], p['daily_new_words'] as int? ?? 20),
          loading: () => _buildTodayCard(context, study, wb['id'], 20),
          error: (_, __) => _buildTodayCard(context, study, wb['id'], 20),
        ),
        const SizedBox(height: 20),

        progress.when(
          data: (p) => _buildProgressCard(p, wb['name'] as String? ?? ''),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 20),

        if (study.streakDays > 0)
          _buildStreakCard(study.streakDays),
      ],
    );
  }

  Widget _buildWordbookCard(Map<String, dynamic> wb) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const WordbookListScreen())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.book, color: Colors.white, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(wb['name'] ?? 'Unknown',
                    style: const TextStyle(color: Colors.white,
                      fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${wb['word_count'] ?? 0} 个单词',
                    style: TextStyle(color: Colors.white.withOpacity(0.8))),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.8)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ★ v4.0: 背词计划卡片
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildStudyPlanCard(Map<String, dynamic> wb, int totalWords, int backendDailyWords) {
    final localDailyWords = ref.watch(dailyNewWordsProvider);
    // 当本地还未从后端加载时（=-1），用后端值
    final displayDailyWords = localDailyWords < 1 ? backendDailyWords : localDailyWords;

    _log('📊 背词计划: totalWords=$totalWords, backend=$backendDailyWords, local=$localDailyWords');

    final remainingDays = (displayDailyWords > 0 && totalWords > 0)
        ? (totalWords / displayDailyWords).ceil()
        : 0;
    final completionDate = DateTime.now().add(Duration(days: remainingDays));
    final dateStr =
        '${completionDate.year}年${completionDate.month.toString().padLeft(2, '0')}月${completionDate.day.toString().padLeft(2, '0')}日';

    final wordOptions = [30, 50, 60, 70, 80, 90, 100, 110, 120, 130, 150, 200];
    final hasPendingChange = localDailyWords > 0 && localDailyWords != backendDailyWords;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.event_note_rounded,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Text('背词计划',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text('共 $totalWords 词',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text('每天背词数',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 10),
                      Text('$displayDailyWords',
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: AppColors.primary)),
                      const Text('个',
                        style: TextStyle(fontSize: 14, color: AppColors.primary, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Container(width: 1, height: 70, color: AppColors.divider),
                Expanded(
                  child: Column(
                    children: [
                      const Text('完成天数',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 10),
                      Text('$remainingDays',
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: AppColors.accent)),
                      const Text('天',
                        style: TextStyle(fontSize: 14, color: AppColors.accent, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: '预计 ',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    TextSpan(text: dateStr,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success)),
                    const TextSpan(text: ' 完成',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 22),

            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('选择每日新词数：',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
            ),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: wordOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final option = wordOptions[index];
                  final isSelected = option == displayDailyWords;
                  return GestureDetector(
                    onTap: () {
                      ref.read(dailyNewWordsProvider.notifier).state = option;
                      _log('📝 选择每日词数: $option');
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 58,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.cardBorder,
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: isSelected
                            ? [BoxShadow(color: AppColors.primary.withOpacity(0.3),
                                blurRadius: 8, offset: const Offset(0, 2))]
                            : null,
                      ),
                      child: Center(
                        child: Text('$option',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? Colors.white : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ★ v4.0: 有未保存更改时提示
            if (hasPendingChange) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.accent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '服务器已保存计划：每天 $backendDailyWords 词。点击「保存计划」使新选择生效，今日任务会随之更新。',
                        style: TextStyle(fontSize: 12, color: AppColors.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSavingPlan ? null : () => _savePlan(wb['id'], displayDailyWords),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasPendingChange ? AppColors.accent : AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSavingPlan
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(hasPendingChange ? '保存计划（有更改未保存）' : '保存计划',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _savePlan(String wordbookId, int dailyWords) async {
    _log('💾 保存计划: wordbookId=$wordbookId, dailyWords=$dailyWords');
    setState(() => _isSavingPlan = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.selectWordbook(wordbookId, dailyNewWords: dailyWords);
      _log('✅ 计划保存成功');

      // ★ v4.0: 保存后刷新进度（含 daily_new_words）和今日任务
      ref.invalidate(progressProvider(wordbookId));
      await ref.read(studyProvider.notifier).loadTodayTask(wordbookId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('计划已保存，每天背 $dailyWords 个新词，今日任务已更新'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      _log('❌ 保存失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('保存失败，请重试'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingPlan = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ★ v4.0: 今日任务卡片 — 逻辑透明化，清晰解释每个数字的来源
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildTodayCard(BuildContext context, StudyState study, String wordbookId, int savedDailyWords) {
    final totalToday = study.totalNew + study.totalReview;
    final hasTask = totalToday > 0;
    final newWordsMatchPlan = study.totalNew == savedDailyWords || study.totalNew == 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('今日任务',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              '新词按计划（每天 $savedDailyWords 词）分配，复习词由系统根据遗忘曲线自动推算',
              style: const TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: _buildTodayStatItem(
                    icon: Icons.fiber_new_rounded,
                    iconColor: AppColors.primary,
                    count: study.isLoading ? null : study.totalNew,
                    label: '今日新词',
                    sublabel: '按计划学习',
                    countColor: AppColors.primary,
                  ),
                ),
                Container(width: 1, height: 70, color: AppColors.divider),
                Expanded(
                  child: _buildTodayStatItem(
                    icon: Icons.replay_rounded,
                    iconColor: AppColors.accent,
                    count: study.isLoading ? null : study.totalReview,
                    label: '到期复习',
                    sublabel: '遗忘曲线推算',
                    countColor: AppColors.accent,
                  ),
                ),
                Container(width: 1, height: 70, color: AppColors.divider),
                Expanded(
                  child: _buildTodayStatItem(
                    icon: Icons.task_alt_rounded,
                    iconColor: AppColors.textPrimary,
                    count: study.isLoading ? null : totalToday,
                    label: '合计',
                    sublabel: '今天要完成',
                    countColor: AppColors.textPrimary,
                  ),
                ),
              ],
            ),

            // 新词数与计划不符提示
            if (!study.isLoading && !newWordsMatchPlan && study.totalNew > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline, size: 15, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '新词显示 ${study.totalNew} 个（计划 $savedDailyWords 个）。可能原因：词书剩余词数不足，或计划尚未保存到服务器。',
                        style: TextStyle(fontSize: 11, color: AppColors.primary.withOpacity(0.85)),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (!study.isLoading && totalToday == 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 15, color: AppColors.success),
                    const SizedBox(width: 8),
                    Text(
                      '今日任务全部完成！明天继续加油 💪',
                      style: TextStyle(fontSize: 12, color: AppColors.success),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: hasTask && !study.isLoading
                    ? () {
                        ref.read(studyProvider.notifier).loadTodayTask(wordbookId);
                        Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const StudyScreen()));
                      }
                    : null,
                icon: Icon(hasTask ? Icons.play_arrow_rounded : Icons.check_circle_outline),
                label: Text(
                  study.isLoading ? '加载中...' :
                  hasTask ? '开始学习（$totalToday 词）' : '今日已完成！',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayStatItem({
    required IconData icon,
    required Color iconColor,
    required int? count,
    required String label,
    required String sublabel,
    required Color countColor,
  }) {
    return Column(
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(height: 6),
        count == null
            ? const SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Text('$count',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: countColor)),
        const SizedBox(height: 2),
        Text(label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        Text(sublabel,
          style: const TextStyle(fontSize: 10, color: AppColors.textHint),
          textAlign: TextAlign.center),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ★ v4.0: 进度卡片 — 新增词书名称
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildProgressCard(Map<String, dynamic> progress, String wordbookName) {
    final total = progress['total_words'] ?? 0;
    final mastered = progress['mastered'] ?? 0;
    final percent = total > 0 ? mastered / total : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ★ v4.0: 标题行 — 左侧"学习进度"，右侧词书名标签
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('学习进度',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const Spacer(),
                if (wordbookName.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.book_outlined, size: 12, color: AppColors.primary),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(
                            wordbookName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                CircularPercentIndicator(
                  radius: 50,
                  lineWidth: 8,
                  percent: percent.clamp(0.0, 1.0),
                  center: Text('${(percent * 100).toInt()}%',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  progressColor: AppColors.success,
                  backgroundColor: AppColors.divider,
                  circularStrokeCap: CircularStrokeCap.round,
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildProgressRow('已掌握', mastered, AppColors.success, '已巩固，暂不需要复习'),
                      const SizedBox(height: 8),
                      _buildProgressRow('学习中', progress['stats']?['learning'] ?? 0, AppColors.accent, '已学习，正在巩固记忆'),
                      const SizedBox(height: 8),
                      _buildProgressRow('未学习', progress['stats']?['new'] ?? 0, AppColors.textHint, '尚未学习的词'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressRow(String label, int count, Color color, String tooltip) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(width: 4),
        Tooltip(
          message: tooltip,
          child: Icon(Icons.help_outline, size: 12, color: AppColors.textHint),
        ),
        const Spacer(),
        Text('$count', style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  Widget _buildStreakCard(int days) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Text('🔥', style: TextStyle(fontSize: 32)),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('连续打卡 $days 天！',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Text('继续加油！',
                style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}
