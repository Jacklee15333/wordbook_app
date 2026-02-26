import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../providers/study_provider.dart';

class StudyScreen extends ConsumerWidget {
  const StudyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final study = ref.watch(studyProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('${study.completedCount} / ${study.totalCards}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: study.progressPercent,
            backgroundColor: AppColors.divider,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
      ),
      body: study.isComplete
          ? _buildCompleteView(context, study)
          : _buildStudyView(context, ref, study),
    );
  }

  Widget _buildStudyView(BuildContext context, WidgetRef ref, StudyState study) {
    final card = study.currentCard;
    if (card == null) return const SizedBox.shrink();

    final word = card['word'] as Map<String, dynamic>;
    final isNew = card['is_new'] == true;

    return Column(
      children: [
        // Card type badge
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isNew ? AppColors.primary.withOpacity(0.1) : AppColors.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isNew ? 'NEW WORD' : 'REVIEW',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isNew ? AppColors.primary : AppColors.accent,
                letterSpacing: 1,
              ),
            ),
          ),
        ),

        // Main card area
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (!study.isShowingAnswer) {
                ref.read(studyProvider.notifier).showAnswer();
              }
            },
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: study.isShowingAnswer
                        ? _buildAnswerSide(word)
                        : _buildQuestionSide(word),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Bottom area: tap hint or rating buttons
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: study.isShowingAnswer
                ? _buildRatingButtons(ref)
                : _buildTapHint(),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionSide(Map<String, dynamic> word) {
    return Card(
      key: const ValueKey('question'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              word['word'] ?? '',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            if (word['phonetic_us'] != null)
              Text(
                word['phonetic_us'],
                style: const TextStyle(
                  fontSize: 18,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerSide(Map<String, dynamic> word) {
    final definitions = word['definitions'] as List? ?? [];
    final morphology = word['morphology'] as Map<String, dynamic>? ?? {};
    final examples = word['examples'] as List? ?? [];
    final phrases = word['phrases'] as List? ?? [];

    return Card(
      key: const ValueKey('answer'),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 450),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Word + phonetic
              Center(
                child: Column(
                  children: [
                    Text(word['word'] ?? '',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                    if (word['phonetic_us'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(word['phonetic_us'],
                          style: const TextStyle(fontSize: 16, color: AppColors.textSecondary)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),

              // Definitions
              for (final def in definitions) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        def['pos'] ?? '',
                        style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        def['cn'] ?? '',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Morphology
              if (morphology['explanation'] != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_fix_high, size: 16, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          morphology['explanation'],
                          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Phrases
              if (phrases.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Phrases', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppColors.textHint, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                for (final p in phrases.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${p['phrase']}  ${p['cn'] ?? ''}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
              ],

              // Examples
              if (examples.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Examples', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppColors.textHint, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                for (final ex in examples.take(2)) ...[
                  Text(ex['en'] ?? '',
                    style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
                  Text(ex['cn'] ?? '',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTapHint() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: const Text(
        'Tap card to reveal answer',
        style: TextStyle(
          fontSize: 16,
          color: AppColors.textHint,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildRatingButtons(WidgetRef ref) {
    return Row(
      children: [
        _buildRatingBtn(ref, 1, 'Again', AppColors.ratingAgain, Icons.close_rounded),
        const SizedBox(width: 8),
        _buildRatingBtn(ref, 2, 'Hard', AppColors.ratingHard, Icons.trending_down_rounded),
        const SizedBox(width: 8),
        _buildRatingBtn(ref, 3, 'Good', AppColors.ratingGood, Icons.check_rounded),
        const SizedBox(width: 8),
        _buildRatingBtn(ref, 4, 'Easy', AppColors.ratingEasy, Icons.bolt_rounded),
      ],
    );
  }

  Widget _buildRatingBtn(WidgetRef ref, int rating, String label, Color color, IconData icon) {
    return Expanded(
      child: Material(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => ref.read(studyProvider.notifier).rateWord(rating),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 4),
                Text(label,
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompleteView(BuildContext context, StudyState study) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.celebration_rounded,
                size: 50, color: AppColors.success),
            ),
            const SizedBox(height: 24),
            const Text('Session Complete!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('You reviewed ${study.completedCount} words',
              style: const TextStyle(fontSize: 16, color: AppColors.textSecondary)),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}
