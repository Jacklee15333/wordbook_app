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
      appBar: AppBar(title: const Text('Wordbooks')),
      body: wordbooks.when(
        data: (list) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final wb = Map<String, dynamic>.from(list[index]);
            final isSelected = selected?['id'] == wb['id'];
            return _buildWordbookTile(context, ref, wb, isSelected);
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
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
                // Icon
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
                // Info
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
                          Text('${wb['word_count'] ?? 0} words',
                            style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                ),
                // Selected check
                if (isSelected)
                  const Icon(Icons.check_circle, color: AppColors.primary),
              ],
            ),
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
      default: return AppColors.textSecondary;
    }
  }
}
