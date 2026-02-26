import 'dart:math';
import 'package:dio/dio.dart';
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
// 队列项 - 每个单词的学习状态
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
// 选择题选项
// ═══════════════════════════════════════════════════════════════════════════

class ChoiceOption {
  final String text;
  final bool isCorrect;

  const ChoiceOption({required this.text, this.isCorrect = false});
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
  final String? spellingHint;
  final List<String> scrambledLetters;

  const TestQuestion({
    required this.wordId,
    required this.word,
    required this.meaning,
    this.phonetic,
    required this.step,
    this.options = const [],
    this.correctIndex = 0,
    this.spellingHint,
    this.scrambledLetters = const [],
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

  // 队列系统
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
    {'word': 'new', 'meaning': '新的'},
    {'word': 'old', 'meaning': '旧的'},
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
    {'word': 'like', 'meaning': '喜欢'},
    {'word': 'want', 'meaning': '想要'},
    {'word': 'need', 'meaning': '需要'},
    {'word': 'beautiful', 'meaning': '美丽的'},
    {'word': 'important', 'meaning': '重要的'},
    {'word': 'different', 'meaning': '不同的'},
    {'word': 'possible', 'meaning': '可能的'},
    {'word': 'understand', 'meaning': '理解'},
    {'word': 'remember', 'meaning': '记住'},
    {'word': 'believe', 'meaning': '相信'},
    {'word': 'change', 'meaning': '改变'},
    {'word': 'follow', 'meaning': '跟随'},
    {'word': 'start', 'meaning': '开始'},
    {'word': 'continue', 'meaning': '继续'},
  ];

  StudyNotifier(this._api) : super(const StudyState());

  // ═══════════════════════════════════════════════════════════════════════
  // 加载今日任务
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> loadTodayTask(String wordbookId) async {
    _wordbookId = wordbookId;
    state = const StudyState(isLoading: true);

    try {
      final data = await _api.getTodayTask(wordbookId);

      final newWords =
          List<Map<String, dynamic>>.from(data['new_words'] ?? []);
      final reviewWords =
          List<Map<String, dynamic>>.from(data['review_words'] ?? []);

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
      state = StudyState(
        isLoading: false,
        error: 'Failed to load tasks: ${_extractError(e)}',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 队列初始化
  // ═══════════════════════════════════════════════════════════════════════

  List<QueueItem> _initQueue(List<Map<String, dynamic>> cards) {
    final items = <QueueItem>[];
    // 初始解锁前3个单词（或全部，如果不足3个）
    // 这样可以让不同单词的不同步骤交叉进行
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
  // 选题逻辑
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

  // ─── 英选汉 ───

  TestQuestion _buildEnToCnQuestion(
      String wordId, String wordText, String meaning, String? phonetic) {
    final options = <ChoiceOption>[
      ChoiceOption(text: meaning, isCorrect: true),
    ];

    final distractors = _getChineseDistractors(wordId, meaning, 3);
    options.addAll(distractors.map((d) => ChoiceOption(text: d)));

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

  // ─── 汉选英 ───

  TestQuestion _buildCnToEnQuestion(
      String wordId, String wordText, String meaning, String? phonetic) {
    final options = <ChoiceOption>[
      ChoiceOption(text: wordText, isCorrect: true),
    ];

    final distractors = _getEnglishDistractors(wordId, wordText, 3);
    options.addAll(distractors.map((d) => ChoiceOption(text: d)));

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

  // ─── 拼写题 ───

  TestQuestion _buildSpellingQuestion(
      String wordId, String wordText, String meaning, String? phonetic) {
    final hint = _generateSpellingHint(wordText);

    final letters = wordText.toLowerCase().split('');
    final extraLetters = _generateExtraLetters(wordText, 2);
    letters.addAll(extraLetters);
    letters.shuffle(_random);

    return TestQuestion(
      wordId: wordId,
      word: wordText,
      meaning: meaning,
      phonetic: phonetic,
      step: TestStep.spelling,
      spellingHint: hint,
      scrambledLetters: letters,
    );
  }

  String _generateSpellingHint(String word) {
    if (word.length <= 2) return word;

    final chars = word.split('');
    final hideCount = (word.length * 0.4).ceil();
    final hidePositions = <int>{};

    while (hidePositions.length < hideCount) {
      final pos = _random.nextInt(word.length);
      if (pos > 0) {
        hidePositions.add(pos);
      }
    }

    for (final pos in hidePositions) {
      chars[pos] = '_';
    }

    return chars.join(' ');
  }

  List<String> _generateExtraLetters(String word, int count) {
    const vowels = 'aeiou';
    const consonants = 'bcdfghjklmnpqrstvwxyz';
    final extras = <String>[];

    for (int i = 0; i < count; i++) {
      final pool = _random.nextBool() ? vowels : consonants;
      extras.add(pool[_random.nextInt(pool.length)]);
    }

    return extras;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 干扰项生成
  // ═══════════════════════════════════════════════════════════════════════

  List<String> _getChineseDistractors(
      String currentWordId, String correctMeaning, int count) {
    final results = <String>[];
    final usedMeanings = <String>{correctMeaning};

    final allCards = state.allCards;
    final candidates = allCards.where((card) {
      final word = card['word'] as Map<String, dynamic>;
      return word['id'].toString() != currentWordId;
    }).toList();
    candidates.shuffle(_random);

    for (final card in candidates) {
      if (results.length >= count) break;
      final word = card['word'] as Map<String, dynamic>;
      final meaning = _extractMeaning(word);
      if (meaning.isNotEmpty &&
          meaning != '未知' &&
          !usedMeanings.contains(meaning)) {
        results.add(meaning);
        usedMeanings.add(meaning);
      }
    }

    if (results.length < count) {
      final fallbacks = List<Map<String, String>>.from(_fallbackWords);
      fallbacks.shuffle(_random);
      for (final fb in fallbacks) {
        if (results.length >= count) break;
        final m = fb['meaning']!;
        if (!usedMeanings.contains(m)) {
          results.add(m);
          usedMeanings.add(m);
        }
      }
    }

    return results;
  }

  List<String> _getEnglishDistractors(
      String currentWordId, String correctWord, int count) {
    final results = <String>[];
    final usedWords = <String>{correctWord.toLowerCase()};

    final allCards = state.allCards;
    final candidates = allCards.where((card) {
      final word = card['word'] as Map<String, dynamic>;
      return word['id'].toString() != currentWordId;
    }).toList();
    candidates.shuffle(_random);

    for (final card in candidates) {
      if (results.length >= count) break;
      final word = card['word'] as Map<String, dynamic>;
      final w = word['word'] as String? ?? '';
      if (w.isNotEmpty && !usedWords.contains(w.toLowerCase())) {
        results.add(w);
        usedWords.add(w.toLowerCase());
      }
    }

    if (results.length < count) {
      final fallbacks = List<Map<String, String>>.from(_fallbackWords);
      fallbacks.shuffle(_random);
      for (final fb in fallbacks) {
        if (results.length >= count) break;
        final w = fb['word']!;
        if (!usedWords.contains(w.toLowerCase())) {
          results.add(w);
          usedWords.add(w.toLowerCase());
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

    // 提交到后端
    if (isCorrect && question.step == TestStep.spelling) {
      _submitToBackend(question.wordId, 4);
    } else if (!isCorrect) {
      _submitToBackend(question.wordId, 1);
    }
  }

  Future<void> submitSpellingAnswer(String answer) async {
    final question = state.currentQuestion;
    if (question == null) return;

    final isCorrect =
        answer.toLowerCase().trim() == question.word.toLowerCase().trim();

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
    if (_wordbookId == null) return;
    try {
      await _api.submitReview(
        wordId: wordId,
        rating: rating,
        wordbookId: _wordbookId!,
        reviewedAt: DateTime.now(),
      );
    } catch (_) {}
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
