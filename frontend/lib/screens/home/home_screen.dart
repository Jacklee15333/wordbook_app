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

// Progress provider
final progressProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, wordbookId) async {
  final api = ref.read(apiServiceProvider);
  return api.getProgress(wordbookId);
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
    // Wait for wordbooks to load, then auto-select first one
    final wordbooks = await ref.read(wordbooksProvider.future);
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
        title: const Text('WordBook'),
        actions: [
          IconButton(
            icon: const Icon(Icons.book_outlined),
            tooltip: 'Wordbooks',
            onPressed: () async {
              await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const WordbookListScreen()));
              // Reload after returning
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
              const PopupMenuItem(value: 'logout', child: Text('Logout')),
            ],
          ),
        ],
      ),
      body: selectedWb == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(wordbooksProvider);
                await ref.read(studyProvider.notifier).loadTodayTask(selectedWb['id']);
              },
              child: _buildBody(context, selectedWb, study),
            ),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> wb, StudyState study) {
    if (study.isLoading && study.totalCards == 0) {
      // Auto-load today's task
      Future.microtask(() {
        ref.read(studyProvider.notifier).loadTodayTask(wb['id']);
      });
      return const Center(child: CircularProgressIndicator());
    }

    final progress = ref.watch(progressProvider(wb['id']));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Selected wordbook card
        _buildWordbookCard(wb),
        const SizedBox(height: 20),

        // Today's task card
        _buildTodayCard(context, study, wb['id']),
        const SizedBox(height: 20),

        // Progress card
        progress.when(
          data: (p) => _buildProgressCard(p),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 20),

        // Streak
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
                  Text('${wb['word_count'] ?? 0} words',
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

  Widget _buildTodayCard(BuildContext context, StudyState study, String wordbookId) {
    final totalToday = study.totalNew + study.totalReview;
    final hasTask = totalToday > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text("Today's Tasks",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatItem('New', study.totalNew, AppColors.primary),
                Container(width: 1, height: 40, color: AppColors.divider),
                _buildStatItem('Review', study.totalReview, AppColors.accent),
                Container(width: 1, height: 40, color: AppColors.divider),
                _buildStatItem('Total', totalToday, AppColors.textPrimary),
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
                label: Text(hasTask ? 'Start Learning' : 'All done for today!'),
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
    final percent = total > 0 ? mastered / total : 0.0;

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
                  const Text('Learning Progress',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 12),
                  _buildProgressRow('Mastered', mastered, AppColors.success),
                  const SizedBox(height: 6),
                  _buildProgressRow('Learning', progress['stats']?['learning'] ?? 0, AppColors.accent),
                  const SizedBox(height: 6),
                  _buildProgressRow('New', progress['stats']?['new'] ?? 0, AppColors.textHint),
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
              Text('$days day streak!',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Text('Keep it up!',
                style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}
