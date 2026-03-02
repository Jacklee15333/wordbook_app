import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../screens/home/home_screen.dart';
import '../../services/api_service.dart';

class WordbookListScreen extends ConsumerWidget {
  const WordbookListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wordbooks = ref.watch(wordbooksProvider);
    final selected = ref.watch(selectedWordbookProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('词书管理')),
      body: wordbooks.when(
        data: (list) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ===== 新建词书按钮 =====
            _buildCreateButton(context, ref),
            const SizedBox(height: 16),
            const Text('我的词书',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            // ===== 词书列表 =====
            ...list.map((item) {
              final wb = Map<String, dynamic>.from(item);
              final isSelected = selected?['id'] == wb['id'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildWordbookTile(context, ref, wb, isSelected),
              );
            }),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildCreateButton(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.primary.withOpacity(0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showCreateWordbookDialog(context, ref),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add_rounded,
                    color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              const Text('新建词书',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateWordbookDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    String? selectedDifficulty;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.library_add_rounded,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              const Text('新建词书', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('词书名称 *',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '例如：托福核心词汇',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('难度级别',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: ['初中', '高中', '四级', '六级', '考研', '托福', '雅思']
                      .map((diff) {
                    final isSelected = selectedDifficulty == diff;
                    return ChoiceChip(
                      label: Text(diff,
                          style: TextStyle(fontSize: 12,
                            color: isSelected ? Colors.white : AppColors.textPrimary)),
                      selected: isSelected,
                      selectedColor: _difficultyColor(diff),
                      backgroundColor: AppColors.surface,
                      onSelected: (val) {
                        setDialogState(() {
                          selectedDifficulty = val ? diff : null;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text('描述（可选）',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: descController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: '添加词书描述...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请输入词书名称')));
                  return;
                }
                try {
                  final api = ref.read(apiServiceProvider);
                  await api.createWordbook(
                    name: name,
                    description: descController.text.trim().isEmpty
                        ? null : descController.text.trim(),
                    difficulty: selectedDifficulty,
                  );
                  ref.invalidate(wordbooksProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('词书「$name」创建成功！')));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('创建失败: $e')));
                  }
                }
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWordbookTile(BuildContext context, WidgetRef ref,
      Map<String, dynamic> wb, bool isSelected) {
    final difficulty = wb['difficulty'] ?? '';
    final diffColor = _difficultyColor(difficulty);

    return Material(
      color: isSelected ? AppColors.primary.withOpacity(0.06) : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final api = ref.read(apiServiceProvider);
          try {
            await api.selectWordbook(wb['id']);
          } catch (_) {}
          ref.read(selectedWordbookProvider.notifier).state = wb;
          if (context.mounted) Navigator.pop(context);
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
                    Text(wb['name'] ?? '',
                      style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (difficulty.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: diffColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(difficulty,
                              style: TextStyle(fontSize: 11,
                                fontWeight: FontWeight.w700, color: diffColor)),
                          ),
                        if (difficulty.isNotEmpty) const SizedBox(width: 8),
                        Text('${wb['word_count'] ?? 0} 个单词',
                          style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                      ],
                    ),
                    if (wb['description'] != null &&
                        wb['description'].toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(wb['description'],
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textHint),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle, color: AppColors.primary),
            ],
          ),
        ),
      ),
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
