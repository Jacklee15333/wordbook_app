// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  wordbook_list_screen.dart  v3.4  2026-03-02                        ║
// ║  v3.4: 新增创建词书 + 导入单词功能                                   ║
// ╚═══════════════════════════════════════════════════════════════════════╝

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/wordbook/wordbook_detail_screen.dart';
import '../../services/api_service.dart';

class WordbookListScreen extends ConsumerStatefulWidget {
  const WordbookListScreen({super.key});

  @override
  ConsumerState<WordbookListScreen> createState() => _WordbookListScreenState();
}

class _WordbookListScreenState extends ConsumerState<WordbookListScreen> {
  @override
  Widget build(BuildContext context) {
    final wordbooks = ref.watch(wordbooksProvider);
    final selected = ref.watch(selectedWordbookProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('词书管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '创建词书',
            onPressed: () => _showCreateWordbookDialog(context),
          ),
        ],
      ),
      body: wordbooks.when(
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.menu_book_rounded, size: 64,
                      color: AppColors.textHint.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  const Text('还没有词书', style: TextStyle(
                      fontSize: 18, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  const Text('点击右上角 + 创建一个新词书',
                      style: TextStyle(color: AppColors.textHint)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final wb = Map<String, dynamic>.from(list[index]);
              final isSelected = selected?['id'] == wb['id'];
              return _buildWordbookTile(context, ref, wb, isSelected);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }

  Widget _buildWordbookTile(BuildContext context, WidgetRef ref,
      Map<String, dynamic> wb, bool isSelected) {
    final difficulty = wb['difficulty'] ?? '';
    final diffColor = _difficultyColor(difficulty);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isSelected ? AppColors.primary.withOpacity(0.06) : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WordbookDetailScreen(wordbook: wb),
              ),
            ).then((_) {
              // 刷新列表（名称可能已修改）
              ref.invalidate(wordbooksProvider);
            });
          },
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.cardBorder,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: diffColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.menu_book_rounded, color: diffColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(wb['name'] ?? '', style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (difficulty.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: diffColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(difficulty,
                                  style: TextStyle(fontSize: 11,
                                      fontWeight: FontWeight.w700, color: diffColor)),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text('${wb['word_count'] ?? 0} 个单词',
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                ),
                // ★ 导入按钮
                IconButton(
                  icon: const Icon(Icons.file_upload_outlined, size: 22),
                  tooltip: '导入单词',
                  color: AppColors.textSecondary,
                  onPressed: () => _showImportDialog(context, wb),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle, color: AppColors.primary)
                else
                  const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 创建词书
  // ═══════════════════════════════════════════════════════════════════════

  void _showCreateWordbookDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? selectedDiff;
    bool isCreating = false;
    final diffs = ['初中', '高中', '四级', '六级', '考研', '托福', '雅思', '其他'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Text('创建新词书'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '词书名称 *',
                    hintText: '例如：考研核心词汇',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: '描述（可选）',
                    hintText: '简短介绍这本词书',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                const Text('难度等级',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: diffs.map((d) {
                    final sel = d == selectedDiff;
                    return GestureDetector(
                      onTap: () => ss(() => selectedDiff = sel ? null : d),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primary : AppColors.divider.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(d, style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : AppColors.textPrimary,
                        )),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              onPressed: isCreating ? null : () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请输入词书名称')));
                  return;
                }
                ss(() => isCreating = true);
                try {
                  final api = ref.read(apiServiceProvider);
                  await api.createWordbook(
                    name: name,
                    description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                    difficulty: selectedDiff,
                  );
                  ref.invalidate(wordbooksProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('词书"$name"创建成功！'),
                      backgroundColor: AppColors.success,
                    ));
                  }
                } catch (e) {
                  ss(() => isCreating = false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('创建失败: $e'), backgroundColor: AppColors.error));
                  }
                }
              },
              child: isCreating
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 导入单词
  // ═══════════════════════════════════════════════════════════════════════

  void _showImportDialog(BuildContext context, Map<String, dynamic> wb) {
    final wordsCtrl = TextEditingController();
    bool isImporting = false;
    String? taskId;
    Map<String, dynamic>? progress;
    Timer? pollTimer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) {
          if (taskId != null) {
            return _buildProgressDialog(ctx, wb, progress,
              onClose: () {
                pollTimer?.cancel();
                Navigator.pop(ctx);
                ref.invalidate(wordbooksProvider);
              },
            );
          }

          return AlertDialog(
            title: Text('导入到「${wb['name']}」'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('每行输入一个单词或短语：',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: wordsCtrl,
                    decoration: const InputDecoration(
                      hintText: 'apple\nhappy\nrun\ntable\n...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(12),
                    ),
                    maxLines: 10,
                    minLines: 6,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 8),
                  Text('系统会自动匹配词库或AI生成释义',
                      style: TextStyle(fontSize: 12, color: AppColors.textHint)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () { pollTimer?.cancel(); Navigator.pop(ctx); },
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: isImporting ? null : () async {
                  final words = wordsCtrl.text.trim()
                      .split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
                  if (words.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请输入单词')));
                    return;
                  }
                  ss(() => isImporting = true);
                  try {
                    final api = ref.read(apiServiceProvider);
                    final result = await api.importWordsV2(wb['id'], words);
                    final tid = result['task_id'] as String;
                    ss(() { taskId = tid; isImporting = false; });
                    pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
                      try {
                        final p = await api.getImportProgress(tid);
                        if (ctx.mounted) ss(() => progress = p);
                        final s = p['status'] as String?;
                        if (s == 'completed' || s == 'failed') pollTimer?.cancel();
                      } catch (_) {}
                    });
                  } catch (e) {
                    ss(() => isImporting = false);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('导入失败: $e'), backgroundColor: AppColors.error));
                    }
                  }
                },
                child: isImporting
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('开始导入'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProgressDialog(BuildContext ctx, Map<String, dynamic> wb,
      Map<String, dynamic>? progress, {required VoidCallback onClose}) {
    final status = progress?['status'] as String? ?? 'processing';
    final total = progress?['total_words'] ?? 0;
    final matched = progress?['matched_count'] ?? 0;
    final aiGen = progress?['ai_generated_count'] ?? 0;
    final failed = progress?['ai_failed_count'] ?? 0;
    final pct = progress?['progress'];
    final done = status == 'completed';
    final err = status == 'failed';

    return AlertDialog(
      title: Text(done ? '导入完成！' : err ? '导入失败' : '正在导入...'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: done ? 1.0 : (pct is num ? pct.toDouble() : 0.0),
            backgroundColor: AppColors.divider,
            valueColor: AlwaysStoppedAnimation(done ? AppColors.success : AppColors.primary),
          ),
          const SizedBox(height: 20),
          _stat('总单词数', total, AppColors.textPrimary),
          const SizedBox(height: 8),
          _stat('词库匹配', matched, AppColors.success),
          const SizedBox(height: 8),
          _stat('AI生成', aiGen, AppColors.primary),
          if ((failed is int && failed > 0) || (failed is num && failed > 0)) ...[
            const SizedBox(height: 8),
            _stat('失败', failed, AppColors.error),
          ],
          if (!done && !err) ...[
            const SizedBox(height: 20),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('处理中...', style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ],
        ],
      ),
      actions: [
        if (done || err) ElevatedButton(
          onPressed: onClose,
          style: ElevatedButton.styleFrom(
              backgroundColor: done ? AppColors.success : AppColors.primary),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Widget _stat(String label, dynamic count, Color color) {
    return Row(
      children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 14)),
        const Spacer(),
        Text('$count', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }

  Color _difficultyColor(String difficulty) {
    switch (difficulty) {
      case '初中': return const Color(0xFF34A853);
      case '高中': return const Color(0xFF1A73E8);
      case '四级': return const Color(0xFFFF8F00);
      case '六级': return const Color(0xFFE8710A);
      case '考研': return const Color(0xFFEA4335);
      case '托福': return const Color(0xFF9C27B0);
      case '雅思': return const Color(0xFF00BCD4);
      default: return AppColors.textSecondary;
    }
  }
}
