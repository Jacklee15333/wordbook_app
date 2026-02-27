import 'dart:async';
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
      builder: (ctx) => _ImportDialogV2(
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
// 新版导入对话框 V2（异步处理 + 进度轮询）
// ════════════════════════════════════════════════════════════════════

class _ImportDialogV2 extends ConsumerStatefulWidget {
  final String wordbookId;
  final String wordbookName;
  final VoidCallback onImported;

  const _ImportDialogV2({
    required this.wordbookId,
    required this.wordbookName,
    required this.onImported,
  });

  @override
  ConsumerState<_ImportDialogV2> createState() => _ImportDialogV2State();
}

class _ImportDialogV2State extends ConsumerState<_ImportDialogV2> {
  final _textController = TextEditingController();

  // 状态: input -> submitting -> processing -> completed -> error
  String _status = 'input';
  String? _taskId;
  String? _errorMessage;
  Timer? _pollTimer;

  // 进度数据
  int _totalWords = 0;
  int _matchedCount = 0;
  int _aiGeneratedCount = 0;
  int _aiFailedCount = 0;
  double _progress = 0;

  @override
  void dispose() {
    _textController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  /// 提交导入
  Future<void> _submitImport() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    // 解析单词列表（按行分割）
    final words = text
        .split(RegExp(r'[\n,;，；]+'))
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList();

    if (words.isEmpty) return;

    setState(() {
      _status = 'submitting';
      _totalWords = words.length;
      _errorMessage = null;
    });

    try {
      final api = ref.read(apiServiceProvider);
      final result = await api.importWordsV2(widget.wordbookId, words);
      debugPrint('[IMPORT] ✅ 导入任务创建: $result');

      setState(() {
        _taskId = result['task_id'];
        _totalWords = result['total_words'] ?? words.length;
        _status = 'processing';
      });

      _startPolling();
    } catch (e) {
      debugPrint('[IMPORT] ❌ 提交失败: $e');
      setState(() {
        _status = 'error';
        _errorMessage = '$e';
      });
    }
  }

  /// 轮询进度
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_taskId == null) return;

      try {
        final api = ref.read(apiServiceProvider);
        final progress = await api.getImportProgress(_taskId!);

        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _matchedCount = progress['matched_count'] ?? 0;
          _aiGeneratedCount = progress['ai_generated_count'] ?? 0;
          _aiFailedCount = progress['ai_failed_count'] ?? 0;
          _progress = (progress['progress'] as num?)?.toDouble() ?? 0;

          final taskStatus = progress['status'] as String? ?? '';
          if (taskStatus == 'completed' || taskStatus == 'failed') {
            _status = 'completed';
            timer.cancel();
            widget.onImported();
          }
        });
      } catch (e) {
        debugPrint('[IMPORT] 轮询错误: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _status == 'completed' ? Icons.check_circle :
            _status == 'error' ? Icons.error :
            _status == 'processing' ? Icons.hourglass_top :
            Icons.upload_file,
            color: _status == 'completed' ? AppColors.success :
                   _status == 'error' ? AppColors.error :
                   AppColors.primary,
            size: 24,
          ),
          const SizedBox(width: 10),
          Text(
            _status == 'input' ? '导入单词到「${widget.wordbookName}」' :
            _status == 'submitting' ? '提交中...' :
            _status == 'processing' ? '正在处理...' :
            _status == 'completed' ? '导入完成' :
            '导入失败',
            style: const TextStyle(fontSize: 17),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: _buildContent(),
      ),
      actions: _buildActions(),
    );
  }

  Widget _buildContent() {
    switch (_status) {
      case 'input':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '每行一个单词，支持逗号/分号分隔：',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: 'apple\nbanana\ncomfortable\nabundant\n...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
              style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '词库已有的单词自动导入，没有的会通过在线词典和AI自动生成（需管理员审核后入库）',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      case 'submitting':
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在提交导入任务...'),
            ],
          ),
        );

      case 'processing':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            // 进度条
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progress / 100,
                minHeight: 10,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: 10),
            Text('${_progress.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            // 统计
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatChip('总数', _totalWords, AppColors.textSecondary),
                _buildStatChip('匹配', _matchedCount, AppColors.success),
                _buildStatChip('生成', _aiGeneratedCount, AppColors.accent),
                _buildStatChip('失败', _aiFailedCount, AppColors.error),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '后台正在处理中，请稍候...',
              style: TextStyle(fontSize: 13, color: AppColors.textHint),
            ),
          ],
        );

      case 'completed':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 统计摘要
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatChip('总数', _totalWords, AppColors.textSecondary),
                  _buildStatChip('匹配', _matchedCount, AppColors.success),
                  _buildStatChip('生成', _aiGeneratedCount, AppColors.accent),
                  _buildStatChip('失败', _aiFailedCount, AppColors.error),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_matchedCount > 0)
              _buildResultRow(Icons.check_circle, AppColors.success,
                '$_matchedCount 个单词已从词库匹配并自动导入'),
            if (_aiGeneratedCount > 0) ...[
              const SizedBox(height: 8),
              _buildResultRow(Icons.smart_toy, AppColors.accent,
                '$_aiGeneratedCount 个单词由AI/词典生成，等待管理员在后台审核入库'),
            ],
            if (_aiFailedCount > 0) ...[
              const SizedBox(height: 8),
              _buildResultRow(Icons.warning_amber, AppColors.error,
                '$_aiFailedCount 个单词生成失败'),
            ],
          ],
        );

      case 'error':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text('导入失败: ${_errorMessage ?? "未知错误"}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.error)),
            ],
          ),
        );

      default:
        return const SizedBox();
    }
  }

  Widget _buildResultRow(IconData icon, Color color, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
            style: TextStyle(fontSize: 13, color: color, height: 1.4)),
        ),
      ],
    );
  }

  Widget _buildStatChip(String label, int value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label,
          style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
      ],
    );
  }

  List<Widget> _buildActions() {
    switch (_status) {
      case 'input':
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton.icon(
            onPressed: _submitImport,
            icon: const Icon(Icons.upload, size: 18),
            label: const Text('导入'),
          ),
        ];
      case 'submitting':
        return []; // 提交中不显示按钮
      case 'processing':
        return [
          TextButton(
            onPressed: () {
              _pollTimer?.cancel();
              Navigator.pop(context);
            },
            child: const Text('后台继续处理'),
          ),
        ];
      case 'completed':
      case 'error':
        return [
          if (_status == 'error')
            TextButton(
              onPressed: () => setState(() => _status = 'input'),
              child: const Text('重试'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ];
      default:
        return [];
    }
  }
}