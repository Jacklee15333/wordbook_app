// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  study_provider.dart  v3.4  2026-03-02                              ║
// ║  v3.4: 干扰项类型匹配（单词配单词，短语配短语）                      ║
// ╚═══════════════════════════════════════════════════════════════════════╝

import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

const String _kVersion = '📦 study_provider v3.3 (2026-03-02)';

void _log(String msg) {
  debugPrint('[STUDY-v3.3] $msg');
}

// ═══════════════════════════════════════════════════════════════════════════
// 测试步骤枚举
// ═══════════════════════════════════════════════════════════════════════════

enum TestStep {
  enToCn,
  cnToEn,
  spelling,
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
// 选择题选项  ★ v3.0: 新增 subText 用于答题后公布答案
// ═══════════════════════════════════════════════════════════════════════════

class ChoiceOption {
  final String text;
  /// 答题后显示的附加信息
  /// enToCn: subText = 对应的英文单词
  /// cnToEn: subText = 对应的中文释义（含词性）
  final String? subText;
  final bool isCorrect;

  const ChoiceOption({
    required this.text,
    this.subText,
    this.isCorrect = false,
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
    {'word': 'apple', 'meaning': 'n. 苹果'},
    {'word': 'book', 'meaning': 'n. 书本'},
    {'word': 'water', 'meaning': 'n. 水'},
    {'word': 'happy', 'meaning': 'adj. 快乐的'},
    {'word': 'run', 'meaning': 'v. 跑'},
    {'word': 'big', 'meaning': 'adj. 大的'},
    {'word': 'small', 'meaning': 'adj. 小的'},
    {'word': 'good', 'meaning': 'adj. 好的'},
    {'word': 'bad', 'meaning': 'adj. 坏的'},
    {'word': 'hot', 'meaning': 'adj. 热的'},
    {'word': 'cold', 'meaning': 'adj. 冷的'},
    {'word': 'new', 'meaning': 'adj. 新的'},
    {'word': 'old', 'meaning': 'adj. 旧的'},
    {'word': 'fast', 'meaning': 'adj. 快的'},
    {'word': 'slow', 'meaning': 'adj. 慢的'},
    {'word': 'eat', 'meaning': 'v. 吃'},
    {'word': 'drink', 'meaning': 'v. 喝'},
    {'word': 'sleep', 'meaning': 'v. 睡觉'},
    {'word': 'walk', 'meaning': 'v. 走路'},
    {'word': 'think', 'meaning': 'v. 思考'},
    {'word': 'learn', 'meaning': 'v. 学习'},
    {'word': 'write', 'meaning': 'v. 写'},
    {'word': 'read', 'meaning': 'v. 读'},
    {'word': 'work', 'meaning': 'v. 工作'},
    {'word': 'play', 'meaning': 'v. 玩'},
    {'word': 'love', 'meaning': 'v. 爱'},
    {'word': 'like', 'meaning': 'v. 喜欢'},
    {'word': 'want', 'meaning': 'v. 想要'},
    {'word': 'need', 'meaning': 'v. 需要'},
    {'word': 'beautiful', 'meaning': 'adj. 美丽的'},
    {'word': 'important', 'meaning': 'adj. 重要的'},
    {'word': 'different', 'meaning': 'adj. 不同的'},
    {'word': 'possible', 'meaning': 'adj. 可能的'},
    {'word': 'understand', 'meaning': 'v. 理解'},
    {'word': 'remember', 'meaning': 'v. 记住'},
    {'word': 'believe', 'meaning': 'v. 相信'},
    {'word': 'change', 'meaning': 'v. 改变'},
    {'word': 'follow', 'meaning': 'v. 跟随'},
    {'word': 'start', 'meaning': 'v. 开始'},
    {'word': 'continue', 'meaning': 'v. 继续'},
    {'word': 'table', 'meaning': 'n. 桌子'},
    {'word': 'dog', 'meaning': 'n. 狗'},
    {'word': 'cat', 'meaning': 'n. 猫'},
    {'word': 'house', 'meaning': 'n. 房子'},
    {'word': 'car', 'meaning': 'n. 汽车'},
    {'word': 'tree', 'meaning': 'n. 树'},
    {'word': 'flower', 'meaning': 'n. 花'},
    {'word': 'music', 'meaning': 'n. 音乐'},
    {'word': 'teacher', 'meaning': 'n. 老师'},
    {'word': 'student', 'meaning': 'n. 学生'},
    {'word': 'tail', 'meaning': 'n. 尾巴'},
    {'word': 'head', 'meaning': 'n. 头'},
    {'word': 'hand', 'meaning': 'n. 手'},
    {'word': 'foot', 'meaning': 'n. 脚'},
    {'word': 'eye', 'meaning': 'n. 眼睛'},
    {'word': 'ear', 'meaning': 'n. 耳朵'},
    {'word': 'nose', 'meaning': 'n. 鼻子'},
    {'word': 'mouth', 'meaning': 'n. 嘴巴'},
    {'word': 'face', 'meaning': 'n. 脸'},
    {'word': 'body', 'meaning': 'n. 身体'},
    {'word': 'heart', 'meaning': 'n. 心'},
    {'word': 'door', 'meaning': 'n. 门'},
    {'word': 'window', 'meaning': 'n. 窗户'},
    {'word': 'chair', 'meaning': 'n. 椅子'},
    {'word': 'bed', 'meaning': 'n. 床'},
    {'word': 'room', 'meaning': 'n. 房间'},
    {'word': 'food', 'meaning': 'n. 食物'},
    {'word': 'fish', 'meaning': 'n. 鱼'},
    {'word': 'bird', 'meaning': 'n. 鸟'},
    {'word': 'sky', 'meaning': 'n. 天空'},
    {'word': 'sun', 'meaning': 'n. 太阳'},
    {'word': 'moon', 'meaning': 'n. 月亮'},
    {'word': 'star', 'meaning': 'n. 星星'},
    {'word': 'rain', 'meaning': 'n. 雨'},
    {'word': 'snow', 'meaning': 'n. 雪'},
    {'word': 'wind', 'meaning': 'n. 风'},
    {'word': 'river', 'meaning': 'n. 河流'},
    {'word': 'mountain', 'meaning': 'n. 山'},
    {'word': 'sea', 'meaning': 'n. 海'},
    {'word': 'city', 'meaning': 'n. 城市'},
    {'word': 'school', 'meaning': 'n. 学校'},
    {'word': 'friend', 'meaning': 'n. 朋友'},
    {'word': 'family', 'meaning': 'n. 家庭'},
    {'word': 'child', 'meaning': 'n. 孩子'},
    {'word': 'man', 'meaning': 'n. 男人'},
    {'word': 'woman', 'meaning': 'n. 女人'},
    {'word': 'time', 'meaning': 'n. 时间'},
    {'word': 'day', 'meaning': 'n. 白天'},
    {'word': 'night', 'meaning': 'n. 夜晚'},
    {'word': 'year', 'meaning': 'n. 年'},
    {'word': 'world', 'meaning': 'n. 世界'},
    {'word': 'life', 'meaning': 'n. 生活'},
    {'word': 'story', 'meaning': 'n. 故事'},
    {'word': 'name', 'meaning': 'n. 名字'},
    {'word': 'road', 'meaning': 'n. 路'},
    {'word': 'money', 'meaning': 'n. 钱'},
    {'word': 'color', 'meaning': 'n. 颜色'},
    {'word': 'white', 'meaning': 'adj. 白色的'},
    {'word': 'black', 'meaning': 'adj. 黑色的'},
    {'word': 'red', 'meaning': 'adj. 红色的'},
    {'word': 'blue', 'meaning': 'adj. 蓝色的'},
    {'word': 'green', 'meaning': 'adj. 绿色的'},
    {'word': 'long', 'meaning': 'adj. 长的'},
    {'word': 'short', 'meaning': 'adj. 短的'},
    {'word': 'tall', 'meaning': 'adj. 高的'},
    {'word': 'young', 'meaning': 'adj. 年轻的'},
    {'word': 'strong', 'meaning': 'adj. 强壮的'},
    {'word': 'easy', 'meaning': 'adj. 容易的'},
    {'word': 'hard', 'meaning': 'adj. 困难的'},
    {'word': 'clean', 'meaning': 'adj. 干净的'},
    {'word': 'dirty', 'meaning': 'adj. 脏的'},
    {'word': 'open', 'meaning': 'v. 打开'},
    {'word': 'close', 'meaning': 'v. 关闭'},
    {'word': 'give', 'meaning': 'v. 给'},
    {'word': 'take', 'meaning': 'v. 拿'},
    {'word': 'come', 'meaning': 'v. 来'},
    {'word': 'go', 'meaning': 'v. 去'},
    {'word': 'see', 'meaning': 'v. 看'},
    {'word': 'hear', 'meaning': 'v. 听'},
    {'word': 'speak', 'meaning': 'v. 说'},
    {'word': 'tell', 'meaning': 'v. 告诉'},
    {'word': 'ask', 'meaning': 'v. 问'},
    {'word': 'help', 'meaning': 'v. 帮助'},
    {'word': 'try', 'meaning': 'v. 尝试'},
    {'word': 'move', 'meaning': 'v. 移动'},
    {'word': 'stop', 'meaning': 'v. 停止'},
    {'word': 'turn', 'meaning': 'v. 转'},
    {'word': 'wait', 'meaning': 'v. 等待'},
    {'word': 'build', 'meaning': 'v. 建造'},
    {'word': 'keep', 'meaning': 'v. 保持'},
    {'word': 'let', 'meaning': 'v. 让'},
    {'word': 'make', 'meaning': 'v. 制作'},
    {'word': 'put', 'meaning': 'v. 放'},
    {'word': 'know', 'meaning': 'v. 知道'},
    {'word': 'feel', 'meaning': 'v. 感觉'},
    {'word': 'live', 'meaning': 'v. 生活'},
    {'word': 'die', 'meaning': 'v. 死'},
    {'word': 'grow', 'meaning': 'v. 成长'},
    {'word': 'sing', 'meaning': 'v. 唱歌'},
    {'word': 'dance', 'meaning': 'v. 跳舞'},
    {'word': 'fly', 'meaning': 'v. 飞'},
    {'word': 'swim', 'meaning': 'v. 游泳'},
    {'word': 'jump', 'meaning': 'v. 跳'},
    {'word': 'sit', 'meaning': 'v. 坐'},
    {'word': 'stand', 'meaning': 'v. 站'},
    {'word': 'fall', 'meaning': 'v. 落下'},
    {'word': 'hold', 'meaning': 'v. 持有'},
    {'word': 'carry', 'meaning': 'v. 携带'},
    {'word': 'bring', 'meaning': 'v. 带来'},
    {'word': 'buy', 'meaning': 'v. 买'},
    {'word': 'sell', 'meaning': 'v. 卖'},
    {'word': 'pay', 'meaning': 'v. 支付'},
    {'word': 'send', 'meaning': 'v. 发送'},
    {'word': 'receive', 'meaning': 'v. 收到'},
    {'word': 'win', 'meaning': 'v. 赢'},
    {'word': 'lose', 'meaning': 'v. 失去'},
    {'word': 'fight', 'meaning': 'v. 战斗'},
    {'word': 'break', 'meaning': 'v. 打破'},
    {'word': 'cut', 'meaning': 'v. 切'},
    {'word': 'pull', 'meaning': 'v. 拉'},
    {'word': 'push', 'meaning': 'v. 推'},
    {'word': 'throw', 'meaning': 'v. 扔'},
    {'word': 'catch', 'meaning': 'v. 抓住'},
    {'word': 'pick', 'meaning': 'v. 捡'},
    {'word': 'drop', 'meaning': 'v. 掉落'},
    {'word': 'spend', 'meaning': 'v. 花费'},
    {'word': 'save', 'meaning': 'v. 保存'},
    {'word': 'fill', 'meaning': 'v. 填满'},
    {'word': 'choose', 'meaning': 'v. 选择'},
    {'word': 'reach', 'meaning': 'v. 到达'},
    {'word': 'join', 'meaning': 'v. 加入'},
    {'word': 'leave', 'meaning': 'v. 离开'},
    {'word': 'watch', 'meaning': 'v. 观看'},
    {'word': 'show', 'meaning': 'v. 展示'},
    {'word': 'draw', 'meaning': 'v. 画'},
    {'word': 'paint', 'meaning': 'v. 涂色'},
    {'word': 'teach', 'meaning': 'v. 教'},
    {'word': 'study', 'meaning': 'v. 学习'},
    {'word': 'pass', 'meaning': 'v. 通过'},
    {'word': 'fail', 'meaning': 'v. 失败'},
    {'word': 'finish', 'meaning': 'v. 完成'},
    {'word': 'begin', 'meaning': 'v. 开始'},
    {'word': 'end', 'meaning': 'v. 结束'},
    {'word': 'happen', 'meaning': 'v. 发生'},
    {'word': 'seem', 'meaning': 'v. 似乎'},
    {'word': 'become', 'meaning': 'v. 变成'},
    {'word': 'return', 'meaning': 'v. 返回'},
    {'word': 'answer', 'meaning': 'v. 回答'},
    {'word': 'mean', 'meaning': 'v. 意味着'},
    {'word': 'include', 'meaning': 'v. 包括'},
    {'word': 'suggest', 'meaning': 'v. 建议'},
    {'word': 'agree', 'meaning': 'v. 同意'},
    {'word': 'consider', 'meaning': 'v. 考虑'},
    {'word': 'produce', 'meaning': 'v. 生产'},
    {'word': 'develop', 'meaning': 'v. 发展'},
    {'word': 'provide', 'meaning': 'v. 提供'},
    {'word': 'create', 'meaning': 'v. 创造'},
    {'word': 'require', 'meaning': 'v. 需要'},
    {'word': 'prepare', 'meaning': 'v. 准备'},
    {'word': 'improve', 'meaning': 'v. 改善'},
    {'word': 'increase', 'meaning': 'v. 增加'},
    {'word': 'describe', 'meaning': 'v. 描述'},
    {'word': 'explain', 'meaning': 'v. 解释'},
    {'word': 'decide', 'meaning': 'v. 决定'},
    {'word': 'discover', 'meaning': 'v. 发现'},
    {'word': 'accept', 'meaning': 'v. 接受'},
    {'word': 'expect', 'meaning': 'v. 期望'},
    {'word': 'suppose', 'meaning': 'v. 假设'},
    {'word': 'enjoy', 'meaning': 'v. 享受'},
  ];

  StudyNotifier(this._api) : super(const StudyState()) {
    _log('✅ $_kVersion  已加载');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 加载今日任务
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> loadTodayTask(String wordbookId) async {
    _wordbookId = wordbookId;
    state = const StudyState(isLoading: true);
    _log('📥 加载今日任务: wordbookId=$wordbookId');

    try {
      final data = await _api.getTodayTask(wordbookId);
      final newWords = List<Map<String, dynamic>>.from(data['new_words'] ?? []);
      final reviewWords = List<Map<String, dynamic>>.from(data['review_words'] ?? []);

      _log('📥 API返回: new=${newWords.length}, review=${reviewWords.length}');

      final allCards = [...reviewWords, ...newWords];

      // ★ v3.3: 预过滤 — 只保留有有效中文释义的单词
      final validCards = <Map<String, dynamic>>[];
      int skippedCount = 0;
      for (final card in allCards) {
        final word = card['word'] as Map<String, dynamic>;
        final wordText = word['word'] as String? ?? '';
        final meaning = _extractMeaning(word);
        final validMeaning = _ensureValidMeaning(wordText, meaning);
        if (_isValidMeaning(validMeaning)) {
          validCards.add(card);
        } else {
          skippedCount++;
          _log('⏭️ 预过滤跳过: "$wordText"（无有效中文释义）');
        }
      }
      _log('📋 有效单词: ${validCards.length}/${allCards.length}（跳过$skippedCount个无释义词）');

      final queueItems = _initQueue(validCards);

      // 统计有效词中新词/复习的数量
      final validNewCount = validCards.where((c) =>
          newWords.any((n) => (n['word'] as Map)['id'] == (c['word'] as Map)['id'])).length;
      final validReviewCount = validCards.length - validNewCount;

      state = StudyState(
        isLoading: false,
        newWords: newWords,
        reviewWords: reviewWords,
        streakDays: data['streak_days'] ?? 0,
        totalNew: validNewCount,
        totalReview: validReviewCount,
        queueItems: queueItems,
      );

      _generateNextQuestion();
    } catch (e) {
      _log('❌ 加载失败: $e');
      state = StudyState(
        isLoading: false,
        error: 'Failed to load tasks: ${_extractError(e)}',
      );
    }
  }

  List<QueueItem> _initQueue(List<Map<String, dynamic>> cards) {
    final items = <QueueItem>[];
    final initialUnlockCount = cards.length < 3 ? cards.length : 3;
    for (int i = 0; i < cards.length; i++) {
      final word = cards[i]['word'] as Map<String, dynamic>;
      items.add(QueueItem(
        wordId: word['id'].toString(),
        orderIndex: i,
        unlocked: i < initialUnlockCount,
      ));
    }
    return items;
  }

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

    candidates.sort((a, b) => items[a].orderIndex.compareTo(items[b].orderIndex));
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

    // 已在 loadTodayTask 中预过滤，这里直接用 _ensureValidMeaning 兜底
    final validMeaning = _ensureValidMeaning(wordText, meaning);

    TestQuestion question;
    switch (item.currentStep) {
      case TestStep.enToCn:
        question = _buildEnToCnQuestion(item.wordId, wordText, validMeaning, phonetic);
        break;
      case TestStep.cnToEn:
        question = _buildCnToEnQuestion(item.wordId, wordText, validMeaning, phonetic);
        break;
      case TestStep.spelling:
        question = _buildSpellingQuestion(item.wordId, wordText, validMeaning, phonetic);
        break;
    }

    _log('🎯 ${item.currentStep}: word=$wordText, options=${question.options.map((o) => o.text).toList()}');

    state = state.copyWith(
      currentQuestion: question,
      clearLastResult: true,
      isShowingResult: false,
    );
  }

  String _extractMeaning(Map<String, dynamic> word) {
    final definitions = word['definitions'] as List? ?? [];
    if (definitions.isEmpty) return '';
    final parts = <String>[];
    for (final def in definitions.take(2)) {
      final pos = def['pos'] as String? ?? '';
      final cn = def['cn'] as String? ?? '';
      if (cn.isNotEmpty) {
        parts.add(pos.isNotEmpty ? '$pos $cn' : cn);
      }
    }
    return parts.isNotEmpty ? parts.join('；') : '';
  }

  Map<String, dynamic>? _findCardByWordId(String wordId) {
    for (final card in state.allCards) {
      final word = card['word'] as Map<String, dynamic>;
      if (word['id'].toString() == wordId) return card;
    }
    return null;
  }

  /// 检查字符串是否包含中文字符
  bool _containsChinese(String text) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
  }

  /// 释义有效：非空、不含"未知"、必须包含中文
  bool _isValidMeaning(String meaning) {
    if (meaning.isEmpty) return false;
    if (meaning == '未知' || meaning.contains('未知')) return false;
    if (!_containsChinese(meaning)) return false;
    return true;
  }

  String _ensureValidMeaning(String wordText, String meaning) {
    if (_isValidMeaning(meaning)) return meaning;
    // 从 fallback 查找
    final fb = _fallbackWords.firstWhere(
      (f) => f['word']!.toLowerCase() == wordText.toLowerCase(),
      orElse: () => <String, String>{},
    );
    if (fb.isNotEmpty && _isValidMeaning(fb['meaning']!)) {
      return fb['meaning']!;
    }
    // 实在找不到就返回空字符串，后续会跳过
    _log('⚠️ "$wordText" 无有效中文释义，将跳过');
    return '';
  }

  // ─── 英选汉 ───  选项text=中文释义, subText=对应的英文单词

  TestQuestion _buildEnToCnQuestion(
      String wordId, String wordText, String meaning, String? phonetic) {
    meaning = _ensureValidMeaning(wordText, meaning);

    final options = <ChoiceOption>[
      ChoiceOption(text: meaning, subText: wordText, isCorrect: true),
    ];

    final distractors = _getChineseDistractorsWithWord(wordId, meaning, 3);
    options.addAll(distractors);

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

  // ─── 汉选英 ───  选项text=英文单词, subText=对应的中文释义

  TestQuestion _buildCnToEnQuestion(
      String wordId, String wordText, String meaning, String? phonetic) {
    meaning = _ensureValidMeaning(wordText, meaning);

    final options = <ChoiceOption>[
      ChoiceOption(text: wordText, subText: meaning, isCorrect: true),
    ];

    final distractors = _getEnglishDistractorsWithMeaning(wordId, wordText, 3);
    options.addAll(distractors);

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

  // ─── 拼写题（音节块拼接）───

  TestQuestion _buildSpellingQuestion(
      String wordId, String wordText, String meaning, String? phonetic) {
    meaning = _ensureValidMeaning(wordText, meaning);

    // ★ v3.2: 把单词拆成音节块，打乱顺序让用户排列
    final chunks = _splitWordIntoChunks(wordText.toLowerCase());
    final shuffled = List<String>.from(chunks);
    // 确保打乱后和原顺序不同
    int attempts = 0;
    do {
      shuffled.shuffle(_random);
      attempts++;
    } while (_listEquals(shuffled, chunks) && attempts < 10);

    _log('🧩 拼写题: "$wordText" → 块=${chunks} → 乱序=${shuffled}');

    return TestQuestion(
      wordId: wordId,
      word: wordText,
      meaning: meaning,
      phonetic: phonetic,
      step: TestStep.spelling,
      spellingHint: chunks.join('|'), // 用 | 分隔的正确顺序
      scrambledLetters: shuffled,     // 打乱后的块
    );
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 把单词拆分成 2~4 个音节块
  List<String> _splitWordIntoChunks(String word) {
    final len = word.length;
    if (len <= 2) return [word];
    if (len <= 4) {
      // 2块: 如 "table" → "ta" + "ble"  或 "tail" → "ta" + "il"
      final mid = (len / 2).ceil();
      return [word.substring(0, mid), word.substring(mid)];
    }

    // 尝试按常见音节模式拆分
    final chunks = _trySyllableSplit(word);
    if (chunks.length >= 2) return chunks;

    // 兜底：均匀切割
    if (len <= 6) {
      final mid = (len / 2).ceil();
      return [word.substring(0, mid), word.substring(mid)];
    } else if (len <= 9) {
      final third = (len / 3).round();
      return [
        word.substring(0, third),
        word.substring(third, third * 2),
        word.substring(third * 2),
      ];
    } else {
      final quarter = (len / 4).round();
      return [
        word.substring(0, quarter),
        word.substring(quarter, quarter * 2),
        word.substring(quarter * 2, quarter * 3),
        word.substring(quarter * 3),
      ];
    }
  }

  /// 尝试基于元音/辅音模式的音节拆分
  List<String> _trySyllableSplit(String word) {
    const vowels = 'aeiouy';
    final result = <String>[];
    var current = '';
    bool lastWasVowel = false;
    int syllableVowelCount = 0;

    for (int i = 0; i < word.length; i++) {
      final ch = word[i];
      final isVowel = vowels.contains(ch);

      current += ch;

      if (isVowel) {
        syllableVowelCount++;
        lastWasVowel = true;
      } else if (lastWasVowel && syllableVowelCount > 0) {
        // 在"元音→辅音"转换点考虑切分
        // 但确保当前块至少2个字符且剩余部分至少2个字符
        if (current.length >= 2 && (word.length - i) >= 2) {
          // 把当前辅音留给下一个音节
          result.add(current.substring(0, current.length - 1));
          current = ch;
          syllableVowelCount = 0;
          lastWasVowel = false;
          continue;
        }
        lastWasVowel = false;
      }
    }
    if (current.isNotEmpty) {
      result.add(current);
    }

    // 如果只切出1块或块太碎（>4块），返回空让兜底逻辑处理
    if (result.length < 2 || result.length > 4) return [];
    // 确保没有太短的块（单字符）
    if (result.any((c) => c.length < 2)) {
      // 合并太短的块
      final merged = <String>[];
      String buffer = '';
      for (final chunk in result) {
        buffer += chunk;
        if (buffer.length >= 2) {
          merged.add(buffer);
          buffer = '';
        }
      }
      if (buffer.isNotEmpty) {
        if (merged.isNotEmpty) {
          merged[merged.length - 1] += buffer;
        } else {
          merged.add(buffer);
        }
      }
      return merged.length >= 2 ? merged : [];
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ★ v3.4: 干扰项生成 — 类型匹配（单词配单词，短语配短语）
  // ═══════════════════════════════════════════════════════════════════════

  /// 判断是否是短语（含空格）
  bool _isPhrase(String text) {
    return text.trim().contains(' ');
  }

  /// 英选汉的干扰项：返回 ChoiceOption(text=中文释义, subText=英文单词)
  List<ChoiceOption> _getChineseDistractorsWithWord(
      String currentWordId, String correctMeaning, int count) {
    final results = <ChoiceOption>[];
    final usedMeanings = <String>{correctMeaning};

    final candidates = state.allCards.where((card) {
      final word = card['word'] as Map<String, dynamic>;
      return word['id'].toString() != currentWordId;
    }).toList();
    candidates.shuffle(_random);

    for (final card in candidates) {
      if (results.length >= count) break;
      final word = card['word'] as Map<String, dynamic>;
      final m = _extractMeaning(word);
      final w = word['word'] as String? ?? '';
      if (_isValidMeaning(m) && !usedMeanings.contains(m)) {
        results.add(ChoiceOption(text: m, subText: w));
        usedMeanings.add(m);
      }
    }

    // 从 fallback 补充
    if (results.length < count) {
      final fallbacks = List<Map<String, String>>.from(_fallbackWords);
      fallbacks.shuffle(_random);
      for (final fb in fallbacks) {
        if (results.length >= count) break;
        final m = fb['meaning']!;
        final w = fb['word']!;
        if (_isValidMeaning(m) && !usedMeanings.contains(m)) {
          results.add(ChoiceOption(text: m, subText: w));
          usedMeanings.add(m);
        }
      }
    }

    return results;
  }

  /// 汉选英的干扰项：返回 ChoiceOption(text=英文单词, subText=中文释义)
  /// ★ v3.4: 类型匹配 — 单词只配单词干扰项，短语只配短语干扰项
  List<ChoiceOption> _getEnglishDistractorsWithMeaning(
      String currentWordId, String correctWord, int count) {
    final results = <ChoiceOption>[];
    final usedWords = <String>{correctWord.toLowerCase()};
    final correctIsPhrase = _isPhrase(correctWord);

    _log('🎲 汉选英干扰项: "$correctWord" isPhrase=$correctIsPhrase');

    // 第一轮：从同批次取相同类型
    final candidates = state.allCards.where((card) {
      final word = card['word'] as Map<String, dynamic>;
      return word['id'].toString() != currentWordId;
    }).toList();
    candidates.shuffle(_random);

    for (final card in candidates) {
      if (results.length >= count) break;
      final word = card['word'] as Map<String, dynamic>;
      final w = word['word'] as String? ?? '';
      if (w.isEmpty || usedWords.contains(w.toLowerCase())) continue;
      // ★ 类型匹配：只取相同类型
      if (_isPhrase(w) != correctIsPhrase) continue;
      final m = _extractMeaning(word);
      final validM = _isValidMeaning(m) ? m : null;
      results.add(ChoiceOption(text: w, subText: validM));
      usedWords.add(w.toLowerCase());
    }

    // 第二轮：从 fallback 补充（fallback 全是单词，只在正确答案也是单词时使用）
    if (results.length < count && !correctIsPhrase) {
      final fallbacks = List<Map<String, String>>.from(_fallbackWords);
      fallbacks.shuffle(_random);
      for (final fb in fallbacks) {
        if (results.length >= count) break;
        final w = fb['word']!;
        final m = fb['meaning']!;
        if (!usedWords.contains(w.toLowerCase())) {
          results.add(ChoiceOption(text: w, subText: m));
          usedWords.add(w.toLowerCase());
        }
      }
    }

    // 第三轮：如果仍不足（短语场景同批次不够），放宽限制从同批次取任意类型
    if (results.length < count) {
      for (final card in candidates) {
        if (results.length >= count) break;
        final word = card['word'] as Map<String, dynamic>;
        final w = word['word'] as String? ?? '';
        if (w.isEmpty || usedWords.contains(w.toLowerCase())) continue;
        final m = _extractMeaning(word);
        final validM = _isValidMeaning(m) ? m : null;
        results.add(ChoiceOption(text: w, subText: validM));
        usedWords.add(w.toLowerCase());
      }
    }

    _log('🎲 干扰项结果: ${results.map((r) => r.text).toList()}');
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

  void _processAnswer(String wordId, bool isCorrect) {
    final items = state.queueItems;
    final idx = items.indexWhere((item) => item.wordId == wordId);
    if (idx < 0) return;

    final item = items[idx];
    item.attempts++;

    for (int i = 0; i < items.length; i++) {
      if (i != idx && items[i].cooldown > 0) items[i].cooldown--;
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
          state = state.copyWith(completedWordCount: state.completedWordCount + 1);
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
