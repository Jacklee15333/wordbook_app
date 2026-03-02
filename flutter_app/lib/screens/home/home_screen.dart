// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  home_screen.dart  v3.0  2026-03-02                                 ║
// ║  v3: 词数选项30~200 / 用进度total_words计算日期 / 答案公布            ║
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

const String _kHomeVersion = '📦 home_screen v3.0 (2026-03-02)';

void _log(String msg) {
  debugPrint('[HOME-v3] $msg');
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

final dailyNewWordsProvider = StateProvider<int>((ref) => 50);

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

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 版本标识（调试用）
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

        // 词书卡片
        _buildWordbookCard(wb),
        const SizedBox(height: 20),

        // ★ v3.0: 背词计划卡片 — 用进度里的 total_words 计算
        progress.when(
          data: (p) => _buildStudyPlanCard(wb, p['total_words'] ?? 0),
          loading: () => _buildStudyPlanCard(wb, wb['word_count'] ?? 0),
          error: (_, __) => _buildStudyPlanCard(wb, wb['word_count'] ?? 0),
        ),
        const SizedBox(height: 20),

        // 今日任务卡片
        _buildTodayCard(context, study, wb['id']),
        const SizedBox(height: 20),

        // 进度卡片
        progress.when(
          data: (p) => _buildProgressCard(p),
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
  // ★ v3.0: 背词计划卡片
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildStudyPlanCard(Map<String, dynamic> wb, int totalWords) {
    final dailyWords = ref.watch(dailyNewWordsProvider);

    // ★ v3.0: 用进度接口的 total_words，不再用 wb['word_count']
    _log('📊 背词计划: totalWords=$totalWords, dailyWords=$dailyWords');

    // 预计完成天数
    final remainingDays = (dailyWords > 0 && totalWords > 0)
        ? (totalWords / dailyWords).ceil()
        : 0;
    // 预计完成日期
    final completionDate = DateTime.now().add(Duration(days: remainingDays));
    final dateStr =
        '${completionDate.year}年${completionDate.month.toString().padLeft(2, '0')}月${completionDate.day.toString().padLeft(2, '0')}日';

    // ★ v3.0: 词数选项改为 30~200
    final wordOptions = [30, 50, 60, 70, 80, 90, 100, 110, 120, 130, 150, 200];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
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
                // 显示词库总词数
                Text('共 $totalWords 词',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 每天背词数 + 完成天数
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text('每天背词数',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 10),
                      Text('$dailyWords',
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

            // 预计完成日期
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

            // 每日词数选择（横向滚动）
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
                  final isSelected = option == dailyWords;
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
            const SizedBox(height: 20),

            // 保存计划按钮
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSavingPlan ? null : () => _savePlan(wb['id'], dailyWords),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSavingPlan
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('保存计划',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('计划已保存，每天背 $dailyWords 个新词'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        ref.read(studyProvider.notifier).loadTodayTask(wordbookId);
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

  Widget _buildTodayCard(BuildContext context, StudyState study, String wordbookId) {
    final totalToday = study.totalNew + study.totalReview;
    final hasTask = totalToday > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('今日任务',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatItem('新词', study.totalNew, AppColors.primary),
                Container(width: 1, height: 40, color: AppColors.divider),
                _buildStatItem('复习', study.totalReview, AppColors.accent),
                Container(width: 1, height: 40, color: AppColors.divider),
                _buildStatItem('总计', totalToday, AppColors.textPrimary),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: hasTask
                    ? () {
                        ref.read(studyProvider.notifier).loadTodayTask(wordbookId);
                        Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const StudyScreen()));
                      }
                    : null,
                icon: Icon(hasTask ? Icons.play_arrow_rounded : Icons.check_circle_outline),
                label: Text(hasTask ? '开始学习' : '今日已完成！'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text('$count',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildProgressCard(Map<String, dynamic> progress) {
    final total = progress['total_words'] ?? 0;
    final mastered = progress['mastered'] ?? 0;
    final percent = total > 0 ? mastered / total : 0.0;

    _log('📊 构建进度卡: total=$total, mastered=$mastered, learning=${progress['stats']?['learning']}, new=${progress['stats']?['new']}');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
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
                  const Text('学习进度',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 12),
                  _buildProgressRow('已掌握', mastered, AppColors.success),
                  const SizedBox(height: 6),
                  _buildProgressRow('学习中', progress['stats']?['learning'] ?? 0, AppColors.accent),
                  const SizedBox(height: 6),
                  _buildProgressRow('未学习', progress['stats']?['new'] ?? 0, AppColors.textHint),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressRow(String label, int count, Color color) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
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
