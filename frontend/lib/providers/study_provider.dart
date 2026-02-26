import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 测试步骤枚举
// ═══════════════════════════════════════════════════════════════════════════

enum TestStep {
  enToCn,   // Step 1: 英选汉（给英文 → 选中文）
  cnToEn,   // Step 2: 汉选英（给中文 → 选英文）
  spelling, // Step 3: 拼写（字母填空）
}

// ═══════════════════════════════════════════════════════════════════════════
// 内容类型枚举 — 决定干扰项的来源类型
// ═══════════════════════════════════════════════════════════════════════════

enum ContentType {
  word,    // 普通单词: abandon, comfortable
  affix,   // 词根词缀: -tion, un-, pre-
  phrase,  // 短语: give up, look forward to
}

// ═══════════════════════════════════════════════════════════════════════════
// 队列项
// ═══════════════════════════════════════════════════════════════════════════

class QueueItem {
  final String wordId;
  final int orderIndex;
  TestStep currentStep;
  int cooldown;
  bool unlocked;
  bool completed;
  int attempts;

  QueueItem({
    required this.wordId,
    required this.orderIndex,
    this.currentStep = TestStep.enToCn,
    this.cooldown = 0,
    this.unlocked = false,
    this.completed = false,
    this.attempts = 0,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// 选择题选项 — 包含配对文本，答案公布时展示
// ═══════════════════════════════════════════════════════════════════════════

class ChoiceOption {
  final String text;       // 选项主文本（英选汉=中文，汉选英=英文）
  final bool isCorrect;
  final String pairText;   // 配对文本（英选汉=对应英文，汉选英=对应中文）

  const ChoiceOption({
    required this.text,
    this.isCorrect = false,
    this.pairText = '',
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// 当前题目
// ═══════════════════════════════════════════════════════════════════════════

class TestQuestion {
  final String wordId;
  final String word;
  final String meaning;
  final String? phonetic;
  final TestStep step;
  final List<ChoiceOption> options;
  final int correctIndex;
  /// 拼写题：正确的拆分块顺序（如 ["re", "late"] → "relate"）
  final List<String> correctChunks;
  /// 拼写题：打乱顺序的拆分块
  final List<String> shuffledChunks;

  const TestQuestion({
    required this.wordId,
    required this.word,
    required this.meaning,
    this.phonetic,
    required this.step,
    this.options = const [],
    this.correctIndex = 0,
    this.correctChunks = const [],
    this.shuffledChunks = const [],
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// 答题结果
// ═══════════════════════════════════════════════════════════════════════════

class AnswerResult {
  final bool isCorrect;
  final int correctIndex;
  final String correctAnswer;
  final String word;
  final String meaning;

  const AnswerResult({
    required this.isCorrect,
    required this.correctIndex,
    required this.correctAnswer,
    required this.word,
    required this.meaning,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// StudyState
// ═══════════════════════════════════════════════════════════════════════════

class StudyState {
  final bool isLoading;
  final List<Map<String, dynamic>> newWords;
  final List<Map<String, dynamic>> reviewWords;
  final int streakDays;
  final int totalNew;
  final int totalReview;
  final String? error;

  final List<QueueItem> queueItems;
  final TestQuestion? currentQuestion;
  final AnswerResult? lastResult;
  final bool isShowingResult;
  final int completedWordCount;

  const StudyState({
    this.isLoading = true,
    this.newWords = const [],
    this.reviewWords = const [],
    this.streakDays = 0,
    this.totalNew = 0,
    this.totalReview = 0,
    this.error,
    this.queueItems = const [],
    this.currentQuestion,
    this.lastResult,
    this.isShowingResult = false,
    this.completedWordCount = 0,
  });

  List<Map<String, dynamic>> get allCards => [...reviewWords, ...newWords];
  int get totalWords => queueItems.length;
  bool get isComplete =>
      queueItems.isNotEmpty && queueItems.every((item) => item.completed);

  int get completedQuestions {
    int count = 0;
    for (final item in queueItems) {
      if (item.completed) {
        count += 3;
      } else if (item.currentStep == TestStep.cnToEn) {
        count += 1;
      } else if (item.currentStep == TestStep.spelling) {
        count += 2;
      }
    }
    return count;
  }

  int get totalQuestions => totalWords * 3;

  double get progressPercent =>
      totalQuestions > 0 ? completedQuestions / totalQuestions : 0;

  StudyState copyWith({
    bool? isLoading,
    List<Map<String, dynamic>>? newWords,
    List<Map<String, dynamic>>? reviewWords,
    int? streakDays,
    int? totalNew,
    int? totalReview,
    String? error,
    List<QueueItem>? queueItems,
    TestQuestion? currentQuestion,
    AnswerResult? lastResult,
    bool? isShowingResult,
    int? completedWordCount,
    bool clearCurrentQuestion = false,
    bool clearLastResult = false,
  }) {
    return StudyState(
      isLoading: isLoading ?? this.isLoading,
      newWords: newWords ?? this.newWords,
      reviewWords: reviewWords ?? this.reviewWords,
      streakDays: streakDays ?? this.streakDays,
      totalNew: totalNew ?? this.totalNew,
      totalReview: totalReview ?? this.totalReview,
      error: error,
      queueItems: queueItems ?? this.queueItems,
      currentQuestion:
          clearCurrentQuestion ? null : (currentQuestion ?? this.currentQuestion),
      lastResult:
          clearLastResult ? null : (lastResult ?? this.lastResult),
      isShowingResult: isShowingResult ?? this.isShowingResult,
      completedWordCount: completedWordCount ?? this.completedWordCount,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// StudyNotifier
// ═══════════════════════════════════════════════════════════════════════════

class StudyNotifier extends StateNotifier<StudyState> {
  final ApiService _api;
  String? _wordbookId;
  final Random _random = Random();

  static const int _minGap = 2;

  // ─── 备用干扰项词库（按内容类型分类）───

  static const List<Map<String, String>> _fallbackWords = [
    {'word': 'apple', 'meaning': '苹果'},
    {'word': 'book', 'meaning': '书本'},
    {'word': 'water', 'meaning': '水'},
    {'word': 'happy', 'meaning': '快乐的'},
    {'word': 'run', 'meaning': '跑'},
    {'word': 'big', 'meaning': '大的'},
    {'word': 'small', 'meaning': '小的'},
    {'word': 'good', 'meaning': '好的'},
    {'word': 'bad', 'meaning': '坏的'},
    {'word': 'hot', 'meaning': '热的'},
    {'word': 'cold', 'meaning': '冷的'},
    {'word': 'fast', 'meaning': '快的'},
    {'word': 'slow', 'meaning': '慢的'},
    {'word': 'eat', 'meaning': '吃'},
    {'word': 'drink', 'meaning': '喝'},
    {'word': 'sleep', 'meaning': '睡觉'},
    {'word': 'walk', 'meaning': '走路'},
    {'word': 'think', 'meaning': '思考'},
    {'word': 'learn', 'meaning': '学习'},
    {'word': 'write', 'meaning': '写'},
    {'word': 'read', 'meaning': '读'},
    {'word': 'work', 'meaning': '工作'},
    {'word': 'play', 'meaning': '玩'},
    {'word': 'love', 'meaning': '爱'},
    {'word': 'beautiful', 'meaning': '美丽的'},
    {'word': 'important', 'meaning': '重要的'},
    {'word': 'different', 'meaning': '不同的'},
    {'word': 'understand', 'meaning': '理解'},
    {'word': 'remember', 'meaning': '记住'},
    {'word': 'believe', 'meaning': '相信'},
    {'word': 'change', 'meaning': '改变'},
    {'word': 'follow', 'meaning': '跟随'},
    {'word': 'start', 'meaning': '开始'},
    {'word': 'continue', 'meaning': '继续'},
  ];

  static const List<Map<String, String>> _fallbackAffixes = [
    {'word': '-tion', 'meaning': '名词后缀，表动作/状态'},
    {'word': '-ment', 'meaning': '名词后缀，表行为/结果'},
    {'word': '-ness', 'meaning': '名词后缀，表性质/状态'},
    {'word': '-ful', 'meaning': '形容词后缀，充满…的'},
    {'word': '-less', 'meaning': '形容词后缀，没有…的'},
    {'word': '-able', 'meaning': '形容词后缀，可以…的'},
    {'word': '-ly', 'meaning': '副词后缀，…地'},
    {'word': '-er', 'meaning': '名词后缀，做…的人'},
    {'word': '-ist', 'meaning': '名词后缀，…主义者'},
    {'word': '-ous', 'meaning': '形容词后缀，具有…的'},
    {'word': 'un-', 'meaning': '前缀，表否定/相反'},
    {'word': 're-', 'meaning': '前缀，再次/重新'},
    {'word': 'pre-', 'meaning': '前缀，在…之前'},
    {'word': 'dis-', 'meaning': '前缀，表否定/相反'},
    {'word': 'mis-', 'meaning': '前缀，错误地'},
    {'word': 'over-', 'meaning': '前缀，过度/超过'},
    {'word': 'sub-', 'meaning': '前缀，在…之下'},
    {'word': 'inter-', 'meaning': '前缀，在…之间'},
    {'word': 'trans-', 'meaning': '前缀，跨越/转变'},
    {'word': '-ize', 'meaning': '动词后缀，使…化'},
    {'word': '-ify', 'meaning': '动词后缀，使成为'},
    {'word': '-al', 'meaning': '形容词后缀，…的'},
    {'word': '-ive', 'meaning': '形容词后缀，有…性质的'},
    {'word': '-ance', 'meaning': '名词后缀，表状态/性质'},
    {'word': 'anti-', 'meaning': '前缀，反对/抗'},
    {'word': 'auto-', 'meaning': '前缀，自动/自己'},
    {'word': 'co-', 'meaning': '前缀，共同'},
    {'word': 'de-', 'meaning': '前缀，去除/向下'},
    {'word': 'ex-', 'meaning': '前缀，向外/前任'},
    {'word': 'multi-', 'meaning': '前缀，多'},
  ];

  static const List<Map<String, String>> _fallbackPhrases = [
    {'word': 'look at', 'meaning': '看；注视'},
    {'word': 'get up', 'meaning': '起床；起立'},
    {'word': 'give up', 'meaning': '放弃'},
    {'word': 'turn on', 'meaning': '打开（电器）'},
    {'word': 'turn off', 'meaning': '关闭（电器）'},
    {'word': 'put on', 'meaning': '穿上；戴上'},
    {'word': 'take off', 'meaning': '脱下；起飞'},
    {'word': 'wake up', 'meaning': '醒来'},
    {'word': 'look for', 'meaning': '寻找'},
    {'word': 'wait for', 'meaning': '等待'},
    {'word': 'listen to', 'meaning': '听'},
    {'word': 'come back', 'meaning': '回来'},
    {'word': 'sit down', 'meaning': '坐下'},
    {'word': 'stand up', 'meaning': '站起来'},
    {'word': 'go on', 'meaning': '继续；发生'},
    {'word': 'pick up', 'meaning': '捡起；接（人）'},
    {'word': 'set up', 'meaning': '建立；设置'},
    {'word': 'find out', 'meaning': '发现；查明'},
    {'word': 'work out', 'meaning': '解决；锻炼'},
    {'word': 'point out', 'meaning': '指出'},
    {'word': 'carry out', 'meaning': '执行；实施'},
    {'word': 'break down', 'meaning': '分解；崩溃'},
    {'word': 'make up', 'meaning': '组成；编造'},
    {'word': 'take part in', 'meaning': '参加'},
    {'word': 'look forward to', 'meaning': '期望；盼望'},
    {'word': 'come up with', 'meaning': '想出；提出'},
    {'word': 'get along with', 'meaning': '与…相处'},
    {'word': 'pay attention to', 'meaning': '注意'},
    {'word': 'in fact', 'meaning': '事实上'},
    {'word': 'at least', 'meaning': '至少'},
  ];

  StudyNotifier(this._api) : super(const StudyState());

  // ═══════════════════════════════════════════════════════════════════════
  // 内容类型检测
  // ═══════════════════════════════════════════════════════════════════════

  /// 检测一个词条是单词、词缀还是短语
  ContentType _detectContentType(String text) {
    final trimmed = text.trim();

    // 词缀：以-开头或-结尾，如 -tion, un-, pre-, -ful
    // 也包括带有-的词根形式，如 rupt-, -spect
    if (trimmed.startsWith('-') || trimmed.endsWith('-')) {
      return ContentType.affix;
    }

    // 短语：包含空格，如 "give up", "look forward to"
    if (trimmed.contains(' ')) {
      return ContentType.phrase;
    }

    // 普通单词
    return ContentType.word;
  }

  /// 获取对应内容类型的备用词库
  List<Map<String, String>> _getFallbackList(ContentType type) {
    switch (type) {
      case ContentType.word:
        return _fallbackWords;
      case ContentType.affix:
        return _fallbackAffixes;
      case ContentType.phrase:
        return _fallbackPhrases;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 加载今日任务
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> loadTodayTask(String wordbookId) async {
    _wordbookId = wordbookId;
    state = const StudyState(isLoading: true);
    debugPrint('[STUDY] 📥 加载今日任务: wordbookId=$wordbookId');

    try {
      final data = await _api.getTodayTask(wordbookId);
      debugPrint('[STUDY] 📥 API返回: new_count=${data['new_count']}, review_count=${data['review_count']}');

      final newWords =
          List<Map<String, dynamic>>.from(data['new_words'] ?? []);
      final reviewWords =
          List<Map<String, dynamic>>.from(data['review_words'] ?? []);

      debugPrint('[STUDY] 📥 新词=${newWords.length}, 复习=${reviewWords.length}');

      final allCards = [...reviewWords, ...newWords];
      final queueItems = _initQueue(allCards);

      state = StudyState(
        isLoading: false,
        newWords: newWords,
        reviewWords: reviewWords,
        streakDays: data['streak_days'] ?? 0,
        totalNew: data['new_count'] ?? 0,
        totalReview: data['review_count'] ?? 0,
        queueItems: queueItems,
      );

      _generateNextQuestion();
    } catch (e) {
      debugPrint('[STUDY] ❌ 加载任务失败: $e');
      state = StudyState(
        isLoading: false,
        error: '加载任务失败: ${_extractError(e)}',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 队列初始化
  // ═══════════════════════════════════════════════════════════════════════

  List<QueueItem> _initQueue(List<Map<String, dynamic>> cards) {
    final items = <QueueItem>[];
    final initialUnlockCount = cards.length < 3 ? cards.length : 3;
    for (int i = 0; i < cards.length; i++) {
      final word = cards[i]['word'] as Map<String, dynamic>;
      items.add(QueueItem(
        wordId: word['id'].toString(),
        orderIndex: i,
        currentStep: TestStep.enToCn,
        cooldown: 0,
        unlocked: i < initialUnlockCount,
        completed: false,
      ));
    }
    return items;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 选题逻辑（按 orderIndex 排序，保持单词书顺序）
  // ═══════════════════════════════════════════════════════════════════════

  int? _getNextQuestionIndex() {
    final items = state.queueItems;

    final candidates = <int>[];
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.unlocked && !item.completed && item.cooldown == 0) {
        candidates.add(i);
      }
    }

    if (candidates.isEmpty) {
      if (items.every((item) => item.completed)) return null;

      // 保底：选冷却最短的
      final unlockedNotCompleted = <int>[];
      for (int i = 0; i < items.length; i++) {
        if (items[i].unlocked && !items[i].completed) {
          unlockedNotCompleted.add(i);
        }
      }
      if (unlockedNotCompleted.isNotEmpty) {
        unlockedNotCompleted
            .sort((a, b) => items[a].cooldown.compareTo(items[b].cooldown));
        return unlockedNotCompleted.first;
      }
      return null;
    }

    // 按 orderIndex 排序 → 保持与纸质书一致的顺序
    candidates
        .sort((a, b) => items[a].orderIndex.compareTo(items[b].orderIndex));
    return candidates.first;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 生成题目
  // ═══════════════════════════════════════════════════════════════════════

  void _generateNextQuestion() {
    final idx = _getNextQuestionIndex();
    if (idx == null) {
      state = state.copyWith(clearCurrentQuestion: true);
      return;
    }

    final item = state.queueItems[idx];
    final card = _findCardByWordId(item.wordId);
    if (card == null) {
      state = state.copyWith(clearCurrentQuestion: true);
      return;
    }

    final word = card['word'] as Map<String, dynamic>;
    final wordText = word['word'] as String? ?? '';
    final meaning = _extractMeaning(word);
    final phonetic = word['phonetic_us'] as String?;

    TestQuestion question;

    switch (item.currentStep) {
      case TestStep.enToCn:
        question =
            _buildEnToCnQuestion(item.wordId, wordText, meaning, phonetic);
        break;
      case TestStep.cnToEn:
        question =
            _buildCnToEnQuestion(item.wordId, wordText, meaning, phonetic);
        break;
      case TestStep.spelling:
        question =
            _buildSpellingQuestion(item.wordId, wordText, meaning, phonetic);
        break;
    }

    state = state.copyWith(
      currentQuestion: question,
      clearLastResult: true,
      isShowingResult: false,
    );
  }

  String _extractMeaning(Map<String, dynamic> word) {
    final definitions = word['definitions'] as List? ?? [];
    if (definitions.isEmpty) return '未知';

    final parts = <String>[];
    for (final def in definitions.take(2)) {
      final pos = def['pos'] as String? ?? '';
      final cn = def['cn'] as String? ?? '';
      if (cn.isNotEmpty) {
        parts.add(pos.isNotEmpty ? '$pos $cn' : cn);
      }
    }
    return parts.isNotEmpty ? parts.join('；') : '未知';
  }

  Map<String, dynamic>? _findCardByWordId(String wordId) {
    for (final card in state.allCards) {
      final word = card['word'] as Map<String, dynamic>;
      if (word['id'].toString() == wordId) return card;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 英选汉：题干=英文，选项=中文，pairText=对应英文
  // ═══════════════════════════════════════════════════════════════════════

  TestQuestion _buildEnToCnQuestion(
      String wordId, String wordText, String meaning, String? phonetic) {
    // 获取3个干扰项（同类型），每个包含 word + meaning
    final distractors = _getDistractors(wordId, wordText, 3);

    final options = <ChoiceOption>[
      ChoiceOption(text: meaning, isCorrect: true, pairText: wordText),
    ];

    for (final d in distractors) {
      options.add(ChoiceOption(
        text: d['meaning']!,
        isCorrect: false,
        pairText: d['word']!,  // 公布答案时显示对应的英文
      ));
    }

    options.shuffle(_random);
    final correctIdx = options.indexWhere((o) => o.isCorrect);

    return TestQuestion(
      wordId: wordId,
      word: wordText,
      meaning: meaning,
      phonetic: phonetic,
      step: TestStep.enToCn,
      options: options,
      correctIndex: correctIdx,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 汉选英：题干=中文，选项=英文，pairText=对应中文
  // ═══════════════════════════════════════════════════════════════════════

  TestQuestion _buildCnToEnQuestion(
      String wordId, String wordText, String meaning, String? phonetic) {
    final distractors = _getDistractors(wordId, wordText, 3);

    final options = <ChoiceOption>[
      ChoiceOption(text: wordText, isCorrect: true, pairText: meaning),
    ];

    for (final d in distractors) {
      options.add(ChoiceOption(
        text: d['word']!,
        isCorrect: false,
        pairText: d['meaning']!,  // 公布答案时显示对应的中文
      ));
    }

    options.shuffle(_random);
    final correctIdx = options.indexWhere((o) => o.isCorrect);

    return TestQuestion(
      wordId: wordId,
      word: wordText,
      meaning: meaning,
      phonetic: phonetic,
      step: TestStep.cnToEn,
      options: options,
      correctIndex: correctIdx,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 拼写题（拼块排序：把单词拆成几个块，打乱顺序让用户排列）
  // ═══════════════════════════════════════════════════════════════════════

  TestQuestion _buildSpellingQuestion(
      String wordId, String wordText, String meaning, String? phonetic) {
    // 将单词拆成2-4个块
    final chunks = _splitWordIntoChunks(wordText.toLowerCase());

    // 打乱顺序
    final shuffled = List<String>.from(chunks);
    // 确保打乱后和原顺序不同（如果块数>1）
    if (chunks.length > 1) {
      int maxAttempts = 10;
      do {
        shuffled.shuffle(_random);
        maxAttempts--;
      } while (_listsEqual(shuffled, chunks) && maxAttempts > 0);
    }

    return TestQuestion(
      wordId: wordId,
      word: wordText,
      meaning: meaning,
      phonetic: phonetic,
      step: TestStep.spelling,
      correctChunks: chunks,
      shuffledChunks: shuffled,
    );
  }

  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 将单词拆分为2-4个音节块
  ///
  /// 拆分策略：
  /// 1. 优先按常见音节模式拆分
  /// 2. 短单词（<=4字母）拆成2块
  /// 3. 中等单词（5-8字母）拆成2-3块
  /// 4. 长单词（>8字母）拆成3-4块
  List<String> _splitWordIntoChunks(String word) {
    if (word.length <= 2) return [word];
    if (word.length <= 4) return _splitEvenly(word, 2);

    // 尝试按常见前后缀拆分
    final prefixResult = _trySplitByAffix(word);
    if (prefixResult != null && prefixResult.length >= 2) {
      return prefixResult;
    }

    // 按音节规则拆分
    final syllables = _splitBySyllableRules(word);
    if (syllables.length >= 2 && syllables.length <= 4) {
      return syllables;
    }

    // 兜底：均匀拆分
    if (word.length <= 8) {
      return _splitEvenly(word, 2 + _random.nextInt(2)); // 2-3块
    } else {
      return _splitEvenly(word, 3 + _random.nextInt(2)); // 3-4块
    }
  }

  /// 尝试按常见前后缀拆分
  List<String>? _trySplitByAffix(String word) {
    // 常见前缀
    const prefixes = [
      'un', 're', 'in', 'im', 'ir', 'il', 'dis', 'en', 'em',
      'non', 'over', 'mis', 'sub', 'pre', 'inter', 'fore',
      'de', 'trans', 'super', 'semi', 'anti', 'mid', 'under',
      'out', 'ex', 'co', 'counter', 'auto', 'bi', 'multi',
    ];

    // 常见后缀
    const suffixes = [
      'tion', 'sion', 'ment', 'ness', 'able', 'ible', 'ful',
      'less', 'ous', 'ive', 'ing', 'tion', 'ence', 'ance',
      'ity', 'ize', 'ise', 'ate', 'ent', 'ant', 'dom',
      'ship', 'ward', 'wise', 'like', 'ally', 'ious',
      'eous', 'ical', 'ual', 'ure', 'ery', 'ory',
      'ist', 'ism', 'ard', 'age', 'al', 'ly', 'er', 'ed',
    ];

    String? prefix;
    String remaining = word;

    // 找前缀（从长到短匹配）
    final sortedPrefixes = List<String>.from(prefixes)
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final p in sortedPrefixes) {
      if (word.startsWith(p) && word.length > p.length + 1) {
        prefix = p;
        remaining = word.substring(p.length);
        break;
      }
    }

    String? suffix;
    String middle = remaining;

    // 找后缀（从长到短匹配）
    final sortedSuffixes = List<String>.from(suffixes)
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final s in sortedSuffixes) {
      if (remaining.endsWith(s) && remaining.length > s.length + 1) {
        suffix = s;
        middle = remaining.substring(0, remaining.length - s.length);
        break;
      }
    }

    // 构建结果
    final result = <String>[];
    if (prefix != null) result.add(prefix);

    if (middle.length > 6) {
      // 中间部分太长，再拆一次
      final midChunks = _splitEvenly(middle, 2);
      result.addAll(midChunks);
    } else if (middle.isNotEmpty) {
      result.add(middle);
    }

    if (suffix != null) result.add(suffix);

    return result.length >= 2 ? result : null;
  }

  /// 按音节规则拆分（简化版：在辅音-元音边界处拆）
  List<String> _splitBySyllableRules(String word) {
    const vowels = 'aeiouy';
    final breakPoints = <int>[];

    // 找可能的拆分点：辅元交界处
    for (int i = 1; i < word.length - 1; i++) {
      final prev = vowels.contains(word[i - 1]);
      final curr = vowels.contains(word[i]);

      // 元音后面跟辅音 → 可能是拆分点
      if (prev && !curr && i >= 2) {
        breakPoints.add(i);
      }
      // 辅音后面跟元音 → 也是拆分点
      else if (!prev && curr && i >= 2) {
        breakPoints.add(i);
      }
    }

    if (breakPoints.isEmpty) return [word];

    // 选择合适的拆分点（目标2-4块）
    final targetChunks = word.length <= 8 ? 2 : 3;
    final selectedBreaks = <int>[];

    if (breakPoints.length <= targetChunks - 1) {
      selectedBreaks.addAll(breakPoints);
    } else {
      // 均匀选取拆分点
      final step = breakPoints.length / (targetChunks - 1);
      for (int i = 0; i < targetChunks - 1; i++) {
        selectedBreaks.add(breakPoints[(i * step).round()]);
      }
    }

    // 去重并排序
    final uniqueBreaks = selectedBreaks.toSet().toList()..sort();

    // 按拆分点切割
    final chunks = <String>[];
    int start = 0;
    for (final bp in uniqueBreaks) {
      if (bp > start && bp < word.length) {
        chunks.add(word.substring(start, bp));
        start = bp;
      }
    }
    chunks.add(word.substring(start));

    // 过滤掉太短的块（合并到前一个）
    final merged = <String>[];
    for (final chunk in chunks) {
      if (merged.isNotEmpty && chunk.length == 1) {
        merged[merged.length - 1] = merged.last + chunk;
      } else {
        merged.add(chunk);
      }
    }

    return merged.length >= 2 ? merged : [word];
  }

  /// 均匀拆分
  List<String> _splitEvenly(String word, int numChunks) {
    if (numChunks <= 1 || word.length < numChunks) return [word];

    final chunkSize = word.length / numChunks;
    final chunks = <String>[];

    for (int i = 0; i < numChunks; i++) {
      final start = (i * chunkSize).round();
      final end = ((i + 1) * chunkSize).round().clamp(0, word.length);
      if (start < end) {
        chunks.add(word.substring(start, end));
      }
    }

    return chunks;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 统一干扰项生成（按内容类型过滤）
  // 返回 List<{word, meaning}>
  // ═══════════════════════════════════════════════════════════════════════

  List<Map<String, String>> _getDistractors(
      String currentWordId, String currentWord, int count) {
    final results = <Map<String, String>>[];
    final usedWords = <String>{currentWord.toLowerCase()};
    final usedMeanings = <String>{};

    // 检测当前词条的内容类型
    final contentType = _detectContentType(currentWord);

    // ── 第1步：从当前单词书中找同类型的候选 ──
    final allCards = state.allCards;
    final candidates = allCards.where((card) {
      final word = card['word'] as Map<String, dynamic>;
      if (word['id'].toString() == currentWordId) return false;
      final wordText = word['word'] as String? ?? '';
      // 关键：只选同类型的
      return _detectContentType(wordText) == contentType;
    }).toList();
    candidates.shuffle(_random);

    for (final card in candidates) {
      if (results.length >= count) break;
      final word = card['word'] as Map<String, dynamic>;
      final w = word['word'] as String? ?? '';
      final m = _extractMeaning(word);
      if (w.isNotEmpty &&
          m.isNotEmpty &&
          m != '未知' &&
          !usedWords.contains(w.toLowerCase()) &&
          !usedMeanings.contains(m)) {
        results.add({'word': w, 'meaning': m});
        usedWords.add(w.toLowerCase());
        usedMeanings.add(m);
      }
    }

    // ── 第2步：不够时用对应类型的备用词库补充 ──
    if (results.length < count) {
      final fallbacks = List<Map<String, String>>.from(
          _getFallbackList(contentType));
      fallbacks.shuffle(_random);
      for (final fb in fallbacks) {
        if (results.length >= count) break;
        final w = fb['word']!;
        final m = fb['meaning']!;
        if (!usedWords.contains(w.toLowerCase()) &&
            !usedMeanings.contains(m)) {
          results.add({'word': w, 'meaning': m});
          usedWords.add(w.toLowerCase());
          usedMeanings.add(m);
        }
      }
    }

    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 提交答案
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> submitChoiceAnswer(int selectedIndex) async {
    final question = state.currentQuestion;
    if (question == null) return;

    final isCorrect = selectedIndex == question.correctIndex;

    state = state.copyWith(
      lastResult: AnswerResult(
        isCorrect: isCorrect,
        correctIndex: question.correctIndex,
        correctAnswer: question.options[question.correctIndex].text,
        word: question.word,
        meaning: question.meaning,
      ),
      isShowingResult: true,
    );

    _processAnswer(question.wordId, isCorrect);

    if (isCorrect && question.step == TestStep.spelling) {
      _submitToBackend(question.wordId, 4);
    } else if (!isCorrect) {
      _submitToBackend(question.wordId, 1);
    }
  }

  Future<void> submitSpellingAnswer(List<String> orderedChunks) async {
    final question = state.currentQuestion;
    if (question == null) return;

    final answer = orderedChunks.join();
    final isCorrect = answer.toLowerCase() == question.word.toLowerCase();

    state = state.copyWith(
      lastResult: AnswerResult(
        isCorrect: isCorrect,
        correctIndex: 0,
        correctAnswer: question.word,
        word: question.word,
        meaning: question.meaning,
      ),
      isShowingResult: true,
    );

    _processAnswer(question.wordId, isCorrect);

    if (isCorrect) {
      _submitToBackend(question.wordId, 4);
    } else {
      _submitToBackend(question.wordId, 1);
    }
  }

  void nextQuestion() {
    _generateNextQuestion();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 队列处理
  // ═══════════════════════════════════════════════════════════════════════

  void _processAnswer(String wordId, bool isCorrect) {
    final items = state.queueItems;

    final idx = items.indexWhere((item) => item.wordId == wordId);
    if (idx < 0) return;

    final item = items[idx];
    item.attempts++;

    // 减少所有其他单词的冷却
    for (int i = 0; i < items.length; i++) {
      if (i != idx && items[i].cooldown > 0) {
        items[i].cooldown--;
      }
    }

    if (isCorrect) {
      switch (item.currentStep) {
        case TestStep.enToCn:
          item.currentStep = TestStep.cnToEn;
          item.cooldown = _minGap;
          _unlockNextWord(items);
          break;
        case TestStep.cnToEn:
          item.currentStep = TestStep.spelling;
          item.cooldown = _minGap;
          _unlockNextWord(items);
          break;
        case TestStep.spelling:
          item.completed = true;
          item.cooldown = 0;
          _unlockNextWord(items);
          state = state.copyWith(
            completedWordCount: state.completedWordCount + 1,
          );
          break;
      }
    } else {
      item.currentStep = TestStep.enToCn;
      item.cooldown = _minGap;
      _unlockNextWord(items);
    }

    state = state.copyWith(queueItems: items);
  }

  void _unlockNextWord(List<QueueItem> items) {
    for (final item in items) {
      if (!item.unlocked) {
        item.unlocked = true;
        return;
      }
    }
  }

  Future<void> _submitToBackend(String wordId, int rating) async {
    if (_wordbookId == null) {
      debugPrint('[STUDY] ⚠️ _submitToBackend: _wordbookId is null, skipping');
      return;
    }
    debugPrint('[STUDY] 📤 提交评分到后端: wordId=$wordId, rating=$rating, wordbookId=$_wordbookId');
    try {
      final result = await _api.submitReview(
        wordId: wordId,
        rating: rating,
        wordbookId: _wordbookId!,
        reviewedAt: DateTime.now(),
      );
      debugPrint('[STUDY] ✅ 评分提交成功: $result');
    } catch (e) {
      debugPrint('[STUDY] ❌ 评分提交失败: $e');
      if (e is DioException) {
        debugPrint('[STUDY] ❌ Response: ${e.response?.statusCode} ${e.response?.data}');
      }
    }
  }

  String _extractError(dynamic e) {
    if (e is DioException && e.response != null) {
      final data = e.response!.data;
      if (data is Map && data.containsKey('detail')) {
        return data['detail'].toString();
      }
    }
    return e.toString();
  }
}

final studyProvider = StateNotifierProvider<StudyNotifier, StudyState>((ref) {
  return StudyNotifier(ref.read(apiServiceProvider));
});