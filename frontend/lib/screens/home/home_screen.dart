import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/study_provider.dart';
import '../../services/api_service.dart';
import '../study/study_screen.dart';
import '../wordbook/wordbook_list_screen.dart';

// Selected wordbook state
final selectedWordbookProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

// Wordbooks list provider
final wordbooksProvider = FutureProvider<List<dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getWordbooks();
});

// Progress provider - autoDispose so it refreshes when re-watched
final progressProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, wordbookId) async {
  final api = ref.read(apiServiceProvider);
  debugPrint('[HOME] 📊 正在获取词书进度: $wordbookId');
  final result = await api.getProgress(wordbookId);
  debugPrint('[HOME] 📊 进度结果: $result');
  return result;
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final wordbooks = await ref.read(wordbooksProvider.future);
    debugPrint('[HOME] 📚 加载了 ${wordbooks.length} 本词书');
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
                ref.invalidate(progressProvider(selectedWb['id']));
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
        _buildWordbookCard(wb),
        const SizedBox(height: 20),
        _buildTodayCard(context, study, wb['id']),
        const SizedBox(height: 20),
        progress.when(
          data: (p) => _buildProgressCard(p),
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, _) {
            debugPrint('[HOME] ❌ 进度加载错误: $e');
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('加载进度失败: $e',
                  style: const TextStyle(color: AppColors.error)),
              ),
            );
          },
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
                  Text(wb['name'] ?? '未知',
                    style: const TextStyle(color: Colors.white,
                      fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${wb['word_count'] ?? 0} 个单词',
                    style: TextStyle(color: Colors.white.withOpacity(0.8))),
                ],
              ),
            ),
            // 导入按钮
            IconButton(
              icon: Icon(Icons.upload_file, color: Colors.white.withOpacity(0.9)),
              tooltip: '导入单词',
              onPressed: () => _showImportDialog(wb),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.8)),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // 导入词库对话框
  // ════════════════════════════════════════════════════════════

  void _showImportDialog(Map<String, dynamic> wb) {
    showDialog(
      context: context,
      builder: (ctx) => _ImportDialog(
        wordbookId: wb['id'],
        wordbookName: wb['name'] ?? '',
        onImported: () {
          ref.invalidate(wordbooksProvider);
          ref.invalidate(progressProvider(wb['id']));
          ref.read(studyProvider.notifier).loadTodayTask(wb['id']);
        },
      ),
    );
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
                    ? () async {
                        ref.read(studyProvider.notifier).loadTodayTask(wordbookId);
                        await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const StudyScreen()));
                        // ★ 学完回来刷新进度
                        debugPrint('[HOME] 📊 学习结束，刷新进度...');
                        ref.invalidate(progressProvider(wordbookId));
                        ref.read(studyProvider.notifier).loadTodayTask(wordbookId);
                      }
                    : null,
                icon: Icon(hasTask ? Icons.play_arrow_rounded : Icons.check_circle_outline),
                label: Text(hasTask ? '开始学习' : '今日任务已完成！'),
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
        Text(label,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildProgressCard(Map<String, dynamic> progress) {
    final total = progress['total_words'] ?? 0;
    final mastered = progress['mastered'] ?? 0;
    final learning = progress['stats']?['learning'] ?? 0;
    final newCount = progress['stats']?['new'] ?? 0;
    final percent = total > 0 ? mastered / total : 0.0;

    debugPrint('[HOME] 📊 构建进度卡: total=$total, mastered=$mastered, learning=$learning, new=$newCount');

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
                  _buildProgressRow('学习中', learning, AppColors.accent),
                  const SizedBox(height: 6),
                  _buildProgressRow('未学习', newCount, AppColors.textHint),
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

// ════════════════════════════════════════════════════════════════════
// 导入对话框
// ════════════════════════════════════════════════════════════════════

class _ImportDialog extends ConsumerStatefulWidget {
  final String wordbookId;
  final String wordbookName;
  final VoidCallback onImported;

  const _ImportDialog({
    required this.wordbookId,
    required this.wordbookName,
    required this.onImported,
  });

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  final _textController = TextEditingController();
  bool _isImporting = false;
  String? _result;
  String? _error;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isImporting = true;
      _result = null;
      _error = null;
    });

    try {
      final api = ref.read(apiServiceProvider);
      final result = await api.importWordsToWordbook(
        wordbookId: widget.wordbookId,
        textContent: text,
      );
      debugPrint('[IMPORT] ✅ 导入结果: $result');

      setState(() {
        _isImporting = false;
        _result = '导入完成！'
            '\n匹配: ${result['found']} 个'
            '\n新增: ${result['added']} 个'
            '${(result['not_found_count'] ?? 0) > 0 ? '\n未找到: ${result['not_found_count']} 个' : ''}';
      });
      widget.onImported();
    } catch (e) {
      debugPrint('[IMPORT] ❌ 导入错误: $e');
      setState(() {
        _isImporting = false;
        _error = '导入失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('导入单词到「${widget.wordbookName}」'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '每行一个单词，支持直接粘贴：',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: 'apple\nbanana\ncomfortable\n...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
              style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            const Text(
              '提示：单词需要已存在于词典中才能匹配成功',
              style: TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_result!,
                  style: const TextStyle(fontSize: 13, color: AppColors.success)),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                style: const TextStyle(fontSize: 13, color: AppColors.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        ElevatedButton(
          onPressed: _isImporting ? null : _import,
          child: _isImporting
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('导入'),
        ),
      ],
    );
  }
}
