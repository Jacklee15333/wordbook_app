// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  study_provider.dart  v3.9  2026-03-07                              ║
// ║  v3.9: 步骤自然交错 + 间隔2题 + 单词书顺序                          ║
// ╚═══════════════════════════════════════════════════════════════════════╝

import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

const String _kVersion = '📦 study_provider v3.9 (2026-03-07) 步骤自然交错+间隔2题';

void _log(String msg) {
  debugPrint('[STUDY] $msg');
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
  /// ★ v3.7: 记录当前正在学习的单词ID，用于退出后恢复
  String? _lastStudyingWordId;
  /// ★ v3.8 fix: 恢复标志，仅在 session 恢复后生效一次
  bool _pendingRestore = false;

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
    _log('═══════════════════════════════════════════');
    _log('★★★ $_kVersion ★★★');
    _log('═══════════════════════════════════════════');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 进度持久化 — 按词书ID独立保存，当天有效
  // ═══════════════════════════════════════════════════════════════════════

  String _sessionKey(String wordbookId) => 'study_session_$wordbookId';
  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _saveSession() async {
    if (_wordbookId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueData = state.queueItems.map((item) => {
        'wordId': item.wordId,
        'orderIndex': item.orderIndex,
        'currentStep': item.currentStep.index,
        'cooldown': item.cooldown,
        'unlocked': item.unlocked,
        'completed': item.completed,
        'attempts': item.attempts,
      }).toList();

      final sessionData = jsonEncode({
        'date': _todayStr(),
        'sessionVersion': 4,  // ★ v3.9: 步骤交错调度
        'wordbookId': _wordbookId,
        'completedWordCount': state.completedWordCount,
        'queueItems': queueData,
        'newWords': state.newWords,
        'reviewWords': state.reviewWords,
        'lastStudyingWordId': _lastStudyingWordId,
      });

      await prefs.setString(_sessionKey(_wordbookId!), sessionData);
      _log('💾 进度已保存: ${state.completedWordCount}/${state.totalWords} 词完成');
    } catch (e) {
      _log('⚠️ 保存进度失败: $e');
    }
  }

  Future<bool> _restoreSession(String wordbookId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionKey(wordbookId));
      if (raw == null) return false;

      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['date'] != _todayStr()) {
        _log('🗑️ 旧进度已过期（${data['date']}），重新开始');
        await prefs.remove(_sessionKey(wordbookId));
        return false;
      }
      // ★ v3.8: 版本校验，旧版session自动失效以应用新调度逻辑
      final sessionVersion = data['sessionVersion'] as int? ?? 0;
      if (sessionVersion < 4) {
        _log('🗑️ 旧版session(v$sessionVersion)，清除并重新开始');
        await prefs.remove(_sessionKey(wordbookId));
        return false;
      }

      final queueData = (data['queueItems'] as List).cast<Map<String, dynamic>>();
      final restoredQueue = queueData.map((q) => QueueItem(
        wordId: q['wordId'] as String,
        orderIndex: q['orderIndex'] as int,
        currentStep: TestStep.values[q['currentStep'] as int],
        cooldown: q['cooldown'] as int,
        unlocked: q['unlocked'] as bool,
        completed: q['completed'] as bool,
        attempts: q['attempts'] as int,
      )).toList();

      final newWords = (data['newWords'] as List).cast<Map<String, dynamic>>();
      final reviewWords = (data['reviewWords'] as List).cast<Map<String, dynamic>>();
      final completedWordCount = data['completedWordCount'] as int;
      _lastStudyingWordId = data['lastStudyingWordId'] as String?;
      _pendingRestore = _lastStudyingWordId != null;

      final validNewCount = newWords.length;
      final validReviewCount = reviewWords.length;

      state = StudyState(
        isLoading: false,
        newWords: newWords,
        reviewWords: reviewWords,
        totalNew: validNewCount,
        totalReview: validReviewCount,
        queueItems: restoredQueue,
        completedWordCount: completedWordCount,
      );

      _log('✅ 进度已恢复: $completedWordCount/${restoredQueue.length} 词完成');
      return true;
    } catch (e) {
      _log('⚠️ 恢复进度失败: $e');
      return false;
    }
  }

  Future<void> clearSession(String wordbookId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionKey(wordbookId));
      _log('🗑️ 已清除进度: $wordbookId');
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 加载今日任务
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> loadTodayTask(String wordbookId) async {
    _wordbookId = wordbookId;
    state = const StudyState(isLoading: true);
    _log('📥 加载今日任务: wordbookId=$wordbookId (v3.9, _minGap=$_minGap)');

    // ★ 先尝试恢复当天进度
    final restored = await _restoreSession(wordbookId);
    if (restored) {
      _generateNextQuestion();
      return;
    }

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

    // ★ v3.8 调试: 打印所有队列项状态
    _log('┌─── 选题调度 (v3.9 _minGap=$_minGap) ───');
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final status = item.completed ? '✅完成' : (item.unlocked ? '🔓' : '🔒');
      _log('│ [$i] wordId=${item.wordId} step=${item.currentStep.name} cd=${item.cooldown} $status');
      if (item.unlocked && !item.completed && item.cooldown == 0) {
        candidates.add(i);
      }
    }

    if (candidates.isEmpty) {
      if (items.every((item) => item.completed)) {
        _log('└─── 全部完成 ───');
        return null;
      }
      final unlockedNotCompleted = <int>[];
      for (int i = 0; i < items.length; i++) {
        if (items[i].unlocked && !items[i].completed) {
          unlockedNotCompleted.add(i);
        }
      }
      if (unlockedNotCompleted.isNotEmpty) {
        unlockedNotCompleted
            .sort((a, b) => items[a].cooldown.compareTo(items[b].cooldown));
        _log('│ ⏳ 无cd=0候选, 选cooldown最小的: idx=${unlockedNotCompleted.first}');
        _log('└───────────────');
        return unlockedNotCompleted.first;
      }
      _log('└─── 无可用候选 ───');
      return null;
    }

    // ★ v3.9: 按单词书原始顺序（orderIndex）出题，
    //         cooldown=2 自然实现步骤交错（同一单词隔2题后才出下一步）
    candidates.sort((a, b) =>
        items[a].orderIndex.compareTo(items[b].orderIndex));

    // ★ v3.8 调试: 打印候选排序结果
    _log('│ 候选(排序后):');
    for (final c in candidates) {
      _log('│   idx=$c wordId=${items[c].wordId} step=${items[c].currentStep.name} order=${items[c].orderIndex}');
    }
    _log('│ ✅ 选中: idx=${candidates.first} step=${items[candidates.first].currentStep.name}');
    _log('└───────────────');

    return candidates.first;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 生成题目
  // ═══════════════════════════════════════════════════════════════════════

  void _generateNextQuestion() {
    // ★ v3.8 fix: 仅在 session 恢复后第一次出题时，回到上次的单词
    int? idx;
    if (_pendingRestore && _lastStudyingWordId != null) {
      _pendingRestore = false; // 只用一次，后续正常调度
      final savedId = _lastStudyingWordId!;
      final savedIdx = state.queueItems.indexWhere(
        (item) => item.wordId == savedId && !item.completed,
      );
      if (savedIdx >= 0) {
        idx = savedIdx;
        _log('🔄 恢复到上次学习的单词: wordId=$savedId');
      }
    }
    idx ??= _getNextQuestionIndex();

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

    // ★ v3.7: 记录当前正在学习的单词ID
    _lastStudyingWordId = item.wordId;

    state = state.copyWith(
      currentQuestion: question,
      clearLastResult: true,
      isShowingResult: false,
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ★ v3.5: 超强兼容的释义提取 — 支持三种数据库格式
  // 格式1 (vocabulary.db导入): {"pos": "",     "meaning": "n. 桌子"}
  // 格式2 (在线词典):          {"pos": "noun", "definition": "...", "definition_cn": ""}
  // 格式3 (AI生成/已修复):     {"pos": "n.",   "cn": "桌子"}
  // ═══════════════════════════════════════════════════════════════════

  /// 词性全称转缩写
  static const Map<String, String> _posFullToAbbr = {
    'noun': 'n.', 'verb': 'v.', 'adjective': 'adj.', 'adverb': 'adv.',
    'preposition': 'prep.', 'conjunction': 'conj.', 'pronoun': 'pron.',
    'interjection': 'interj.', 'determiner': 'det.', 'exclamation': 'interj.',
  };

  /// 词性缩写正则 (n. / v. / adj. / adv. / ...)
  static final RegExp _posAbbrRe = RegExp(
    r'^(n\.|v\.|vt\.|vi\.|adj\.|adv\.|prep\.|conj\.|pron\.|int\.|interj\.|aux\.|art\.|num\.|det\.|abbr\.|pl\.)\s*',
  );

  /// 标准化词性为缩写形式
  String _normalizePos(String raw) {
    if (raw.isEmpty) return '';
    final trimmed = raw.trim().toLowerCase();
    // 已是缩写 (如 "n." / "adj.")
    if (_posAbbrRe.hasMatch('$trimmed ')) return trimmed;
    // 全称 (如 "noun" / "adjective")
    return _posFullToAbbr[trimmed] ?? '';
  }

  String _extractMeaning(Map<String, dynamic> word) {
    final definitions = word['definitions'] as List? ?? [];
    if (definitions.isEmpty) return '';
    final parts = <String>[];
    // ★ 短语和词缀不显示词性前缀，只有单个单词才显示
    final wordText = word['word'] as String? ?? '';
    final showPos = _getWordType(wordText) == 'word';

    for (final def in definitions.take(2)) {
      String pos = (def['pos'] as String? ?? '').trim();
      String cn = '';

      // ★ 按优先级尝试获取中文释义
      // 优先级: cn > meaning > definition_cn
      final cnField = (def['cn'] as String? ?? '').trim();
      final meaningField = (def['meaning'] as String? ?? '').trim();
      final defCnField = (def['definition_cn'] as String? ?? '').trim();

      if (cnField.isNotEmpty && _containsChinese(cnField)) {
        cn = cnField;
      } else if (meaningField.isNotEmpty && _containsChinese(meaningField)) {
        cn = meaningField;
      } else if (defCnField.isNotEmpty && _containsChinese(defCnField)) {
        cn = defCnField;
      }

      if (cn.isEmpty) continue;

      // ★ 标准化词性
      String normalizedPos = showPos ? _normalizePos(pos) : '';

      // ★ 如果 pos 为空且是单词，尝试从 cn 文本中解析嵌入的词性前缀
      if (normalizedPos.isEmpty && showPos) {
        final posMatch = _posAbbrRe.firstMatch(cn);
        if (posMatch != null) {
          normalizedPos = posMatch.group(1)!;
          cn = cn.substring(posMatch.end).trim();
        }
      } else if (!showPos) {
        // 短语/词缀：如果 cn 里嵌有词性前缀，去掉它
        final posMatch = _posAbbrRe.firstMatch(cn);
        if (posMatch != null) {
          cn = cn.substring(posMatch.end).trim();
        }
      }

      // 拼接最终结果: "n. 桌子"（单词）或 "桌子"（短语/词缀）
      if (normalizedPos.isNotEmpty && cn.isNotEmpty) {
        parts.add('$normalizedPos $cn');
      } else if (cn.isNotEmpty) {
        parts.add(cn);
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
    final wordType = _getWordType(wordText);
    _log('🔤 英选汉出题: "$wordText" type=$wordType meaning="$meaning"');

    final options = <ChoiceOption>[
      ChoiceOption(text: meaning, subText: wordText, isCorrect: true),
    ];

    final distractors = _getChineseDistractorsWithWord(wordId, wordText, meaning, 3);
    options.addAll(distractors);
    _log('🔤 英选汉选项: ${options.map((o) => "${o.subText}=${o.text}").toList()}');

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
  // ★ v3.5: 干扰项生成 — 三类匹配（单词/短语/词缀）
  // ═══════════════════════════════════════════════════════════════════════

  /// 判断是否是短语（含空格，但排除词缀）
  bool _isPhrase(String text) {
    final t = text.trim();
    if (_isAffix(t)) return false;
    return t.contains(' ');
  }

  /// 判断是否是词根词缀（以 - 开头或结尾，如 dis- / -tion / -able）
  bool _isAffix(String text) {
    final t = text.trim();
    return t.startsWith('-') || t.endsWith('-');
  }

  /// 获取词汇类型: 'affix' / 'phrase' / 'word'
  String _getWordType(String text) {
    if (_isAffix(text)) return 'affix';
    if (_isPhrase(text)) return 'phrase';
    return 'word';
  }

  // ─── 备用短语池 ───
  static const List<Map<String, String>> _fallbackPhrases = [
    {'word': 'look at', 'meaning': '看；注视'},
    {'word': 'look for', 'meaning': '寻找'},
    {'word': 'look after', 'meaning': '照顾'},
    {'word': 'look forward to', 'meaning': '期待'},
    {'word': 'give up', 'meaning': '放弃'},
    {'word': 'give in', 'meaning': '屈服；让步'},
    {'word': 'pick up', 'meaning': '捡起；学会'},
    {'word': 'put on', 'meaning': '穿上'},
    {'word': 'put off', 'meaning': '推迟'},
    {'word': 'take off', 'meaning': '脱下；起飞'},
    {'word': 'take up', 'meaning': '开始从事'},
    {'word': 'take care of', 'meaning': '照顾'},
    {'word': 'turn on', 'meaning': '打开'},
    {'word': 'turn off', 'meaning': '关闭'},
    {'word': 'turn down', 'meaning': '拒绝；调低'},
    {'word': 'come up with', 'meaning': '想出'},
    {'word': 'get along with', 'meaning': '与...相处'},
    {'word': 'get rid of', 'meaning': '摆脱'},
    {'word': 'make up', 'meaning': '编造；化妆'},
    {'word': 'break down', 'meaning': '崩溃；抛锚'},
    {'word': 'break out', 'meaning': '爆发'},
    {'word': 'carry out', 'meaning': '执行'},
    {'word': 'bring up', 'meaning': '抚养；提出'},
    {'word': 'set up', 'meaning': '建立'},
    {'word': 'show up', 'meaning': '出现'},
    {'word': 'work out', 'meaning': '算出；锻炼'},
    {'word': 'figure out', 'meaning': '弄清楚'},
    {'word': 'find out', 'meaning': '发现；查明'},
    {'word': 'point out', 'meaning': '指出'},
    {'word': 'run out of', 'meaning': '用完'},
    {'word': 'in fact', 'meaning': '事实上'},
    {'word': 'in general', 'meaning': '总的来说'},
    {'word': 'on purpose', 'meaning': '故意地'},
    {'word': 'by accident', 'meaning': '偶然地'},
    {'word': 'at first', 'meaning': '起初'},
    {'word': 'at last', 'meaning': '终于'},
    {'word': 'after all', 'meaning': '毕竟'},
    {'word': 'as well', 'meaning': '也'},
    {'word': 'so far', 'meaning': '到目前为止'},
    {'word': 'a lot of', 'meaning': '许多的'},
  ];

  // ─── 备用词缀池 ───
  static const List<Map<String, String>> _fallbackAffixes = [
    {'word': 'un-', 'meaning': '前缀，表示"不；否定"'},
    {'word': 'dis-', 'meaning': '前缀，表示"不；相反"'},
    {'word': 're-', 'meaning': '前缀，表示"再；重新"'},
    {'word': 'pre-', 'meaning': '前缀，表示"在...之前"'},
    {'word': 'mis-', 'meaning': '前缀，表示"错误地"'},
    {'word': 'over-', 'meaning': '前缀，表示"过度；在上"'},
    {'word': 'out-', 'meaning': '前缀，表示"超过；在外"'},
    {'word': 'sub-', 'meaning': '前缀，表示"在下面；次"'},
    {'word': 'inter-', 'meaning': '前缀，表示"在...之间"'},
    {'word': 'trans-', 'meaning': '前缀，表示"跨越"'},
    {'word': 'anti-', 'meaning': '前缀，表示"反对"'},
    {'word': 'non-', 'meaning': '前缀，表示"非；不"'},
    {'word': 'multi-', 'meaning': '前缀，表示"多"'},
    {'word': 'semi-', 'meaning': '前缀，表示"半"'},
    {'word': 'super-', 'meaning': '前缀，表示"超级"'},
    {'word': '-tion', 'meaning': '后缀，构成名词'},
    {'word': '-ness', 'meaning': '后缀，构成名词（表状态）'},
    {'word': '-ment', 'meaning': '后缀，构成名词（表行为）'},
    {'word': '-able', 'meaning': '后缀，表示"能...的"'},
    {'word': '-ful', 'meaning': '后缀，表示"充满...的"'},
    {'word': '-less', 'meaning': '后缀，表示"没有...的"'},
    {'word': '-ous', 'meaning': '后缀，表示"...的"'},
    {'word': '-ly', 'meaning': '后缀，构成副词'},
    {'word': '-er', 'meaning': '后缀，表示"做...的人"'},
    {'word': '-ist', 'meaning': '后缀，表示"...者"'},
    {'word': '-ize', 'meaning': '后缀，表示"使...化"'},
    {'word': '-ify', 'meaning': '后缀，表示"使成为"'},
    {'word': '-ive', 'meaning': '后缀，表示"有...性质的"'},
    {'word': '-al', 'meaning': '后缀，表示"...的"'},
    {'word': '-en', 'meaning': '后缀，表示"使变成"'},
  ];

  /// 根据类型选择对应的 fallback 池
  List<Map<String, String>> _getFallbackForType(String wordType) {
    switch (wordType) {
      case 'phrase':
        return _fallbackPhrases;
      case 'affix':
        return _fallbackAffixes;
      default:
        return _fallbackWords;
    }
  }

  /// 英选汉的干扰项：返回 ChoiceOption(text=中文释义, subText=英文单词)
  /// ★ v3.5: 三类匹配 — 单词配单词，短语配短语，词缀配词缀
  List<ChoiceOption> _getChineseDistractorsWithWord(
      String currentWordId, String correctWord, String correctMeaning, int count) {
    final results = <ChoiceOption>[];
    final usedMeanings = <String>{correctMeaning};
    final correctType = _getWordType(correctWord);

    _log('🎲 英选汉干扰项: "$correctWord" type=$correctType');

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
      if (w.isEmpty) continue;
      // ★ 类型匹配
      if (_getWordType(w) != correctType) continue;
      final m = _extractMeaning(word);
      if (_isValidMeaning(m) && !usedMeanings.contains(m)) {
        results.add(ChoiceOption(text: m, subText: w));
        usedMeanings.add(m);
      }
    }

    // 第二轮：从对应类型的 fallback 补充
    if (results.length < count) {
      final fallbacks = List<Map<String, String>>.from(_getFallbackForType(correctType));
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

    // 第三轮：实在不够，放宽从同批次取任意类型
    if (results.length < count) {
      for (final card in candidates) {
        if (results.length >= count) break;
        final word = card['word'] as Map<String, dynamic>;
        final w = word['word'] as String? ?? '';
        if (w.isEmpty) continue;
        final m = _extractMeaning(word);
        if (_isValidMeaning(m) && !usedMeanings.contains(m)) {
          results.add(ChoiceOption(text: m, subText: w));
          usedMeanings.add(m);
        }
      }
    }

    _log('🎲 英选汉干扰项结果: ${results.map((r) => '${r.subText}=${r.text}').toList()}');
    return results;
  }

  /// 汉选英的干扰项：返回 ChoiceOption(text=英文单词, subText=中文释义)
  /// ★ v3.5: 三类匹配 — 单词配单词，短语配短语，词缀配词缀
  List<ChoiceOption> _getEnglishDistractorsWithMeaning(
      String currentWordId, String correctWord, int count) {
    final results = <ChoiceOption>[];
    final usedWords = <String>{correctWord.toLowerCase()};
    final correctType = _getWordType(correctWord);

    _log('🎲 汉选英干扰项: "$correctWord" type=$correctType');

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
      // ★ 类型匹配
      if (_getWordType(w) != correctType) continue;
      final m = _extractMeaning(word);
      final validM = _isValidMeaning(m) ? m : null;
      results.add(ChoiceOption(text: w, subText: validM));
      usedWords.add(w.toLowerCase());
    }

    // 第二轮：从对应类型的 fallback 补充
    if (results.length < count) {
      final fallbacks = List<Map<String, String>>.from(_getFallbackForType(correctType));
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

    // 第三轮：实在不够，放宽从同批次取任意类型
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

    _log('🎲 汉选英干扰项结果: ${results.map((r) => r.text).toList()}');
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

    final oldStep = item.currentStep.name;
    _log('📝 答题: wordId=$wordId step=$oldStep ${isCorrect ? "✅正确" : "❌错误"}');

    for (int i = 0; i < items.length; i++) {
      if (i != idx && items[i].cooldown > 0) items[i].cooldown--;
    }

    if (isCorrect) {
      switch (item.currentStep) {
        case TestStep.enToCn:
          item.currentStep = TestStep.cnToEn;
          item.cooldown = _minGap;
          _unlockNextWord(items);
          _log('📝 → 进入cnToEn, cooldown=$_minGap');
          break;
        case TestStep.cnToEn:
          item.currentStep = TestStep.spelling;
          item.cooldown = _minGap;
          _unlockNextWord(items);
          _log('📝 → 进入spelling, cooldown=$_minGap');
          break;
        case TestStep.spelling:
          item.completed = true;
          item.cooldown = 0;
          _unlockNextWord(items);
          state = state.copyWith(completedWordCount: state.completedWordCount + 1);
          _log('📝 → 单词完成!');
          break;
      }
    } else {
      item.currentStep = TestStep.enToCn;
      item.cooldown = _minGap;
      _unlockNextWord(items);
      _log('📝 → 回退到enToCn, cooldown=$_minGap');
    }
    state = state.copyWith(queueItems: items);
    // ★ 每次答题后保存进度
    _saveSession();
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