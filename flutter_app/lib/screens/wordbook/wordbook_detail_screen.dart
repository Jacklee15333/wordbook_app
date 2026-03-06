// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  wordbook_detail_screen.dart  v1.0  2026-03-06                      ║
// ║  词书详情：单词列表 + 学习进度 + 错误分析 + 重命名                   ║
// ╚═══════════════════════════════════════════════════════════════════════╝

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../screens/home/home_screen.dart';
import '../../services/api_service.dart';

class WordbookDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> wordbook;

  const WordbookDetailScreen({super.key, required this.wordbook});

  @override
  ConsumerState<WordbookDetailScreen> createState() => _WordbookDetailScreenState();
}

class _WordbookDetailScreenState extends ConsumerState<WordbookDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Map<String, dynamic> _wb;

  Map<String, dynamic>? _progress;
  List<Map<String, dynamic>> _words = [];
  bool _loadingProgress = false;
  bool _loadingWords = false;
  bool _hasMore = true;
  int _page = 1;

  final ScrollController _wordScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _wb = Map<String, dynamic>.from(widget.wordbook);
    _wordScrollCtrl.addListener(_onScroll);
    _loadProgress();
    _loadWords();
  }

  void _onScroll() {
    if (_wordScrollCtrl.position.pixels >=
        _wordScrollCtrl.position.maxScrollExtent - 300) {
      _loadWords();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _wordScrollCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 数据加载
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _loadProgress() async {
    if (_loadingProgress) return;
    setState(() => _loadingProgress = true);
    try {
      final api = ref.read(apiServiceProvider);
      final p = await api.getProgress(_wb['id'].toString());
      if (mounted) setState(() { _progress = p; _loadingProgress = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingProgress = false);
    }
  }

  Future<void> _loadWords() async {
    if (_loadingWords || !_hasMore) return;
    setState(() => _loadingWords = true);
    final api = ref.read(apiServiceProvider);
    try {
      // 优先使用带学习状态的详情接口
      final result = await api.getWordbookWordsDetail(
          _wb['id'].toString(), page: _page);
      if (mounted) {
        setState(() {
          _words.addAll(result.map((w) => Map<String, dynamic>.from(w)));
          _page++;
          _hasMore = result.length >= 50;
          _loadingWords = false;
        });
      }
    } catch (_) {
      // 降级：使用原有词语列表接口（无学习状态数据）
      try {
        final result = await api.getWordbookWords(
            _wb['id'].toString(), page: _page, pageSize: 50);
        if (mounted) {
          setState(() {
            _words.addAll(result.map((w) {
              final m = Map<String, dynamic>.from(w as Map);
              // 统一字段名：原接口返回的是完整 WordResponse
              return {
                'word_id': m['id']?.toString() ?? '',
                'word': m['word'] ?? '',
                'phonetic_us': m['phonetic_us'],
                'definitions': m['definitions'] ?? [],
                'fsrs_state': 0,
                'review_count': 0,
                'fsrs_lapses': 0,
                'last_reviewed_at': null,
              };
            }));
            _page++;
            _hasMore = result.length >= 50;
            _loadingWords = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _loadingWords = false);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isBuiltin = _wb['is_builtin'] == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(_wb['name'] ?? ''),
        actions: [
          if (!isBuiltin)
            IconButton(
              icon: const Icon(Icons.drive_file_rename_outline),
              tooltip: '重命名',
              onPressed: _showRenameDialog,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildProgressCard(),
          _buildSelectButton(),
          Container(
            color: AppColors.surface,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: '单词列表'),
                Tab(text: '错误分析'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildWordListTab(),
                _buildErrorTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 进度卡片
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildProgressCard() {
    if (_loadingProgress && _progress == null) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final total = (_progress?['total_words'] ?? _wb['word_count'] ?? 0) as num;
    final mastered = (_progress?['mastered'] ?? 0) as num;
    final stats = (_progress?['stats'] as Map?) ?? {};
    final learning = (stats['learning'] ?? 0) as num;
    final pct = (_progress?['progress_percent'] ?? 0.0) as num;
    final notLearned = (total - mastered - learning).clamp(0, total);

    // 找到"当前学到"的位置（第一个未掌握的单词）
    int currentIdx = -1;
    for (int i = 0; i < _words.length; i++) {
      if ((_words[i]['fsrs_state'] ?? 0) != 2) { currentIdx = i; break; }
    }
    final currentWord = currentIdx >= 0 ? _words[currentIdx]['word'] : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text('学习进度',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const Spacer(),
              Text('${pct.toStringAsFixed(1)}%',
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.toDouble() / 100,
              minHeight: 6,
              backgroundColor: AppColors.divider,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _statChip('已掌握', mastered.toInt(), AppColors.success),
              const SizedBox(width: 6),
              _statChip('学习中', learning.toInt(), AppColors.primary),
              const SizedBox(width: 6),
              _statChip('未学习', notLearned.toInt(), AppColors.textHint),
              const Spacer(),
              Text('共 ${total.toInt()} 词',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
          if (currentWord != null) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.bookmark, size: 13, color: AppColors.accent),
                const SizedBox(width: 5),
                const Text('当前学到：',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                Text(currentWord,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                Text('  (第 ${currentIdx + 1} 个)',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textHint)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('$label $count',
              style: TextStyle(fontSize: 11, color: color,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 选择词书按钮
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSelectButton() {
    final selected = ref.watch(selectedWordbookProvider);
    final isSelected = selected?['id'] == _wb['id'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: Icon(isSelected ? Icons.check_circle : Icons.play_circle_outline,
              size: 18),
          label: Text(isSelected ? '当前学习中' : '开始学习此词书'),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isSelected ? AppColors.success : AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: isSelected
              ? null
              : () async {
                  final api = ref.read(apiServiceProvider);
                  try {
                    await api.selectWordbook(_wb['id'].toString());
                    ref.read(selectedWordbookProvider.notifier).state = _wb;
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('已选择「${_wb['name']}」'),
                        backgroundColor: AppColors.success,
                      ));
                    }
                  } catch (_) {}
                },
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 单词列表 Tab
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildWordListTab() {
    if (_words.isEmpty && _loadingWords) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_words.isEmpty) {
      return const Center(
        child: Text('暂无单词', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    // 第一个非"已掌握"单词为当前位置
    int currentIdx = -1;
    for (int i = 0; i < _words.length; i++) {
      if ((_words[i]['fsrs_state'] ?? 0) != 2) { currentIdx = i; break; }
    }

    return ListView.builder(
      controller: _wordScrollCtrl,
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: _words.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _words.length) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return _buildWordTile(_words[index], index + 1, index == currentIdx);
      },
    );
  }

  Widget _buildWordTile(Map<String, dynamic> word, int index, bool isCurrent) {
    final state = (word['fsrs_state'] ?? 0) as int;
    final reviewCount = (word['review_count'] ?? 0) as int;
    final lapses = (word['fsrs_lapses'] ?? 0) as int;

    Color stateColor;
    String stateLabel;
    IconData stateIcon;
    switch (state) {
      case 2:
        stateColor = AppColors.success;
        stateLabel = '已掌握';
        stateIcon = Icons.check_circle;
        break;
      case 1:
        stateColor = AppColors.primary;
        stateLabel = '学习中';
        stateIcon = Icons.school;
        break;
      case 3:
        stateColor = AppColors.accent;
        stateLabel = '重学中';
        stateIcon = Icons.refresh;
        break;
      default:
        stateColor = AppColors.textHint;
        stateLabel = '未学习';
        stateIcon = Icons.radio_button_unchecked;
    }

    final defs = word['definitions'] as List?;
    String shortDef = '';
    if (defs != null && defs.isNotEmpty) {
      final d = defs.first;
      shortDef = (d['meaning'] ?? d['chinese'] ?? '').toString();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.primary.withOpacity(0.05)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrent
              ? AppColors.primary.withOpacity(0.35)
              : AppColors.cardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text('$index',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textHint)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(word['word'] ?? '',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      if (isCurrent) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('当前',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                      if (word['phonetic_us'] != null) ...[
                        const SizedBox(width: 6),
                        Text('/${word['phonetic_us']}/',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textHint)),
                      ],
                    ],
                  ),
                  if (shortDef.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(shortDef,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(stateIcon, size: 11, color: stateColor),
                    const SizedBox(width: 3),
                    Text(stateLabel,
                        style: TextStyle(
                            fontSize: 10,
                            color: stateColor,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                if (reviewCount > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '复习${reviewCount}次'
                    '${lapses > 0 ? " · 错${lapses}次" : ""}',
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.textHint),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 错误分析 Tab
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildErrorTab() {
    if (_words.isEmpty && _loadingWords) {
      return const Center(child: CircularProgressIndicator());
    }

    // 筛选有错误记录的单词，按错误率降序
    final errorWords = _words
        .where((w) => (w['fsrs_lapses'] ?? 0) > 0)
        .toList()
      ..sort((a, b) {
        final rateA =
            (a['fsrs_lapses'] as num) / ((a['review_count'] as num? ?? 1).clamp(1, 9999));
        final rateB =
            (b['fsrs_lapses'] as num) / ((b['review_count'] as num? ?? 1).clamp(1, 9999));
        return rateB.compareTo(rateA);
      });

    if (errorWords.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events,
                size: 52, color: AppColors.success.withOpacity(0.45)),
            const SizedBox(height: 14),
            const Text('暂无错误记录',
                style: TextStyle(
                    fontSize: 16, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            const Text('继续保持，你很棒！',
                style: TextStyle(color: AppColors.textHint)),
            if (_hasMore) ...[
              const SizedBox(height: 16),
              const Text('（仍在加载单词中，请切换到「单词列表」下滑加载更多）',
                  style: TextStyle(fontSize: 11, color: AppColors.textHint),
                  textAlign: TextAlign.center),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasMore)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 13, color: AppColors.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '已分析 ${_words.length} 个单词，切换到「单词列表」下滑可加载更多',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.accent),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '错误率最高的 ${errorWords.length} 个单词',
            style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            itemCount: errorWords.length,
            itemBuilder: (context, index) {
              final w = errorWords[index];
              final lapses = (w['fsrs_lapses'] ?? 0) as int;
              final total = ((w['review_count'] ?? 1) as int).clamp(1, 9999);
              final rate = (lapses / total * 100).round();
              return _buildErrorTile(w, index + 1, lapses, total, rate);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildErrorTile(
      Map<String, dynamic> word, int rank, int lapses, int total, int rate) {
    final defs = word['definitions'] as List?;
    String shortDef = '';
    if (defs != null && defs.isNotEmpty) {
      shortDef = (defs.first['meaning'] ?? defs.first['chinese'] ?? '').toString();
    }

    final Color rankColor = rank <= 3
        ? AppColors.error
        : rank <= 10
            ? AppColors.accent
            : AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: rank <= 3
              ? AppColors.error.withOpacity(0.2)
              : AppColors.cardBorder,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text('$rank',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: rankColor)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(word['word'] ?? '',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                if (shortDef.isNotEmpty)
                  Text(shortDef,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$rate%',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: rankColor)),
              const Text('错误率',
                  style: TextStyle(
                      fontSize: 9, color: AppColors.textHint)),
              Text('答错 $lapses / 共 $total 次',
                  style: const TextStyle(
                      fontSize: 9, color: AppColors.textHint)),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 重命名
  // ═══════════════════════════════════════════════════════════════════════

  void _showRenameDialog() {
    final ctrl = TextEditingController(text: _wb['name']);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Text('重命名词书'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '词书名称',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = ctrl.text.trim();
                      if (name.isEmpty) return;
                      ss(() => isSaving = true);
                      try {
                        final api = ref.read(apiServiceProvider);
                        await api.renameWordbook(_wb['id'].toString(), name);
                        if (mounted) {
                          setState(() => _wb['name'] = name);
                          ref.invalidate(wordbooksProvider);
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('已重命名为「$name」'),
                            backgroundColor: AppColors.success,
                          ));
                        }
                      } catch (e) {
                        ss(() => isSaving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('重命名失败: $e'),
                            backgroundColor: AppColors.error,
                          ));
                        }
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
