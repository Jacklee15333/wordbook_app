// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  study_screen.dart  v5.0  2026-04-01                                ║
// ║  v5.0: 单词学习界面音节拆分动画（pyphen 专业音节数据）              ║
// ╚═══════════════════════════════════════════════════════════════════════╝

import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../providers/study_provider.dart';

class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({super.key});

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> {
  List<String> _selectedLetters = [];
  List<bool> _letterUsed = [];
  int? _selectedOptionIndex;
  bool _isAnimating = false;

  // ★ v4.4: 浏览器原生 Audio 播放 — 最可靠
  html.AudioElement? _audioElement;
  bool _isPlaying = false;
  String _lastAutoPlayedKey = '';

  // ★ v5.0: 音节拆分动画状态（详情页用）
  List<String> _syllables = [];
  // idle → firstPlay → pause → animating → done → morpheme
  String _syllablePhase = 'idle';
  int _activeSyllableIndex = -1;
  bool _syllablesExpanded = false;
  String _lastDetailWordId = '';
  List<Map<String, dynamic>> _detailMorphemes = []; // ★ v5.2

  // ★ v5.2: 测试页面动画状态
  // whole → split → morpheme
  String _quizSyllablePhase = 'whole';
  String _lastQuizWordId = '';

  @override
  void dispose() {
    _audioElement?.pause();
    _audioElement = null;
    super.dispose();
  }

  /// 播放单词发音（通过后端 /media/{word_id}/audio 接口）
  Future<void> _playWord(String wordId, {String accent = 'us'}) async {
    if (_isPlaying || wordId.isEmpty) return;
    setState(() => _isPlaying = true);
    try {
      final url = '${ApiConfig.baseUrl}/media/$wordId/audio?accent=$accent';
      // 停掉上一个
      _audioElement?.pause();
      // 创建新的 Audio 元素
      _audioElement = html.AudioElement(url);
      _audioElement!.onEnded.listen((_) {
        if (mounted) setState(() => _isPlaying = false);
      });
      _audioElement!.onError.listen((_) {
        debugPrint('[AUDIO] 播放失败: $url');
        if (mounted) setState(() => _isPlaying = false);
      });
      await _audioElement!.play();
    } catch (e) {
      debugPrint('[AUDIO] 异常: $e');
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  /// 自动播放 — 仅当 key 变化时触发
  void _autoPlay(String key, String wordId) {
    if (key == _lastAutoPlayedKey || wordId.isEmpty) return;
    _lastAutoPlayedKey = key;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _playWord(wordId);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ★ v5.2: 测试页面动画序列
  // 流程: 整词+播放 → 0.8s → 音节拆分+播放 → 0.8s → 词根词缀展示
  // ═══════════════════════════════════════════════════════════════════════

  void _startQuizSyllableSequence(String wordId, {bool hasMorphemes = false}) {
    final key = 'quiz_syl_$wordId';
    if (key == _lastAutoPlayedKey || wordId.isEmpty) return;
    _lastAutoPlayedKey = key;
    _lastQuizWordId = wordId;
    setState(() => _quizSyllablePhase = 'whole');

    final url = '${ApiConfig.baseUrl}/media/$wordId/audio?accent=us';

    // ── 第一遍：显示整词，播放音频 ──
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _audioElement?.pause();
      _audioElement = html.AudioElement(url);
      setState(() => _isPlaying = true);

      _audioElement!.onEnded.listen((_) {
        if (!mounted) return;
        setState(() => _isPlaying = false);

        // ── 停顿0.8s后切换到音节拆分 + 播放第二遍 ──
        Future.delayed(const Duration(milliseconds: 800), () {
          if (!mounted || _lastQuizWordId != wordId) return;
          setState(() => _quizSyllablePhase = 'split');

          // 播放第二遍
          Future.delayed(const Duration(milliseconds: 100), () {
            if (!mounted || _lastQuizWordId != wordId) return;
            _audioElement?.pause();
            _audioElement = html.AudioElement(url);
            setState(() => _isPlaying = true);
            _audioElement!.onEnded.listen((_) {
              if (mounted) setState(() => _isPlaying = false);
              // ── 第二遍播完后，如果有词根词缀数据，停顿0.8s后展示 ──
              if (hasMorphemes) {
                Future.delayed(const Duration(milliseconds: 800), () {
                  if (!mounted || _lastQuizWordId != wordId) return;
                  setState(() => _quizSyllablePhase = 'morpheme');
                });
              }
            });
            _audioElement!.onError.listen((_) {
              if (mounted) {
                setState(() => _isPlaying = false);
                if (hasMorphemes) {
                  setState(() => _quizSyllablePhase = 'morpheme');
                }
              }
            });
            _audioElement!.play();
          });
        });
      });

      _audioElement!.onError.listen((_) {
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
          _quizSyllablePhase = 'split';
        });
      });

      _audioElement!.play();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ★ v5.0: 音节拆分动画序列
  // 流程: 播放第一遍 → 停顿 → 音节展开 → 播放第二遍 + 逐个高亮
  // ═══════════════════════════════════════════════════════════════════════

  void _startSyllableSequence(String wordId, List<String> syllables) {
    if (syllables.length <= 1 || wordId.isEmpty) return;
    if (_lastDetailWordId == wordId) return; // 同一单词不重复
    _lastDetailWordId = wordId;

    _syllables = syllables;
    _syllablePhase = 'firstPlay';
    _activeSyllableIndex = -1;
    _syllablesExpanded = false;

    final url = '${ApiConfig.baseUrl}/media/$wordId/audio?accent=us';

    // ── 第一遍播放 ──
    _audioElement?.pause();
    _audioElement = html.AudioElement(url);
    setState(() => _isPlaying = true);

    _audioElement!.onEnded.listen((_) {
      if (!mounted || _syllablePhase != 'firstPlay') return;
      setState(() {
        _isPlaying = false;
        _syllablePhase = 'pause';
      });

      // ── 停顿 800ms ──
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted || _syllablePhase != 'pause') return;

        // ── 先展开音节（间距动画） ──
        setState(() {
          _syllablePhase = 'animating';
          _syllablesExpanded = true;
        });

        // ── 展开动画完成后播放第二遍 + 高亮 ──
        Future.delayed(const Duration(milliseconds: 450), () {
          if (!mounted || _syllablePhase != 'animating') return;

          final audio2 = html.AudioElement(url);
          _audioElement = audio2;
          setState(() => _isPlaying = true);

          // 监听 metadata 获取真实时长
          audio2.onLoadedMetadata.listen((_) {
            final dur = audio2.duration;
            if (dur != null && !dur.isNaN && dur > 0) {
              _scheduleSyllableHighlights((dur * 1000).round());
            } else {
              _scheduleSyllableHighlights(null);
            }
          });

          audio2.onEnded.listen((_) {
            if (mounted) setState(() => _isPlaying = false);
          });
          audio2.onError.listen((_) {
            if (mounted) setState(() => _isPlaying = false);
          });

          audio2.play();
        });
      });
    });

    _audioElement!.onError.listen((_) {
      if (mounted) setState(() {
        _isPlaying = false;
        _syllablePhase = 'idle';
      });
    });

    _audioElement!.play();
  }

  void _scheduleSyllableHighlights(int? audioDurationMs) {
    final totalChars = _syllables.join('').length;
    // 用真实时长或估算值（每个字符 ~80ms + 300ms 基础）
    final totalMs = audioDurationMs ?? (totalChars * 80 + 300);

    int elapsed = 100; // 起始延迟
    for (int i = 0; i < _syllables.length; i++) {
      final ratio = _syllables[i].length / totalChars;
      final syllableMs = (totalMs * ratio).round().clamp(150, 800);
      final capturedIndex = i;

      Future.delayed(Duration(milliseconds: elapsed), () {
        if (mounted && _syllablePhase == 'animating') {
          setState(() => _activeSyllableIndex = capturedIndex);
        }
      });
      elapsed += syllableMs;
    }

    // 高亮结束 → done 状态 → 0.8s后 → morpheme 状态
    Future.delayed(Duration(milliseconds: elapsed + 400), () {
      if (mounted) {
        setState(() {
          _syllablePhase = 'done';
          _activeSyllableIndex = -1;
        });
        // ★ v5.2: 如果有词根词缀数据，等0.8s后切换到构词法展示
        if (_detailMorphemes.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted && _syllablePhase == 'done') {
              setState(() => _syllablePhase = 'morpheme');
            }
          });
        }
      }
    });
  }

  /// ★ v5.0: 音节动画单词显示 — 替代静态 Text
  Widget _buildAnimatedWordText(String wordText, String wordId) {
    // ★ v5.2: 词根词缀阶段 → 显示构词法拆解（详情页白色版本）
    if (_syllablePhase == 'morpheme' && _detailMorphemes.isNotEmpty) {
      return _buildDetailMorphemeText(_detailMorphemes);
    }

    final showSplit = (_syllablePhase == 'animating' || _syllablePhase == 'done')
        && _syllables.length > 1;

    // 未开始或无音节数据 → 静态显示
    if (!showSplit) {
      return Text(
        wordText,
        style: const TextStyle(
          fontSize: 34, fontWeight: FontWeight.w800,
          color: Colors.white, letterSpacing: -0.5,
          shadows: [Shadow(blurRadius: 10, color: Colors.black54, offset: Offset(0, 2))],
        ),
      );
    }

    // 音节拆分显示
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        for (int i = 0; i < _syllables.length; i++) ...[
          // 分隔符（从第二个音节开始）
          if (i > 0)
            AnimatedOpacity(
              opacity: _syllablesExpanded ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 350),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  ' · ',
                  style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w400,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ),
            ),
          // 音节文字
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 250),
            style: TextStyle(
              fontSize: _activeSyllableIndex == i ? 38 : 34,
              fontWeight: FontWeight.w800,
              color: _activeSyllableIndex == i
                  ? const Color(0xFFFFD54F) // 高亮黄金色
                  : Colors.white,
              letterSpacing: -0.3,
              shadows: [
                Shadow(
                  blurRadius: _activeSyllableIndex == i ? 16 : 10,
                  color: _activeSyllableIndex == i
                      ? const Color(0xFFFFD54F).withOpacity(0.5)
                      : Colors.black54,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(_syllables[i]),
          ),
        ],
      ],
    );
  }

  /// ★ v5.2: 详情页词根词缀展示（白色系，适合背景图片上叠加）
  static const _detailMorphemeColors = {
    'prefix': Color(0xFF90CAF9),  // 浅蓝
    'root':   Color(0xFFFFD54F),  // 金黄
    'suffix': Color(0xFFA5D6A7),  // 浅绿
  };

  Widget _buildDetailMorphemeText(List<Map<String, dynamic>> morphemes) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第一行：彩色词素拆分
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < morphemes.length; i++) ...[
              if (i > 0) Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('+',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.6),
                    shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                ),
              ),
              Text(
                morphemes[i]['part'] as String? ?? '',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: _detailMorphemeColors[morphemes[i]['type']] ?? Colors.white,
                  shadows: const [Shadow(blurRadius: 8, color: Colors.black54, offset: Offset(0, 1))],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        // 第二行：每个词素的含义
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < morphemes.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  morphemes[i]['meaning'] as String? ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _detailMorphemeColors[morphemes[i]['type']] ?? Colors.white70,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// 构建小型发音按钮（放在单词右侧）
  Widget _buildPlayButton(String wordId, {double size = 28, String accent = 'us'}) {
    return GestureDetector(
      onTap: () => _playWord(wordId, accent: accent),
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Icon(
          _isPlaying ? Icons.volume_up_rounded : Icons.volume_up_outlined,
          color: AppColors.primary.withOpacity(0.6),
          size: size,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final study = ref.watch(studyProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '第 ${study.completedWordCount + 1} 词  /  共 ${study.totalWords} 词',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
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
      body: study.isLoading
          ? const Center(child: CircularProgressIndicator())
          : study.error != null
              ? _buildErrorView(study.error!)
              : study.isShowingWordDetail
                  ? _buildWordDetailView(study)
                  : study.isComplete
                      ? _buildCompleteView(study)
                      : study.currentQuestion != null
                          ? _buildQuestionView(study)
                          : _buildCompleteView(study),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 题目视图
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildQuestionView(StudyState study) {
    final question = study.currentQuestion!;

    // ★ v5.1: 检测题目切换，重置测试页音节状态
    if (question.wordId != _lastQuizWordId) {
      _quizSyllablePhase = 'whole';
    }

    // ★ v5.2: 英→汉 + 有音节数据 → 走动画序列（整词→音节→词根词缀）
    final hasQuizSyllables = question.step == TestStep.enToCn
        && question.syllables.length > 1
        && !question.word.contains(' ')
        && !question.word.startsWith('-')
        && !question.word.endsWith('-');
    final hasQuizMorphemes = question.morphemes.isNotEmpty;

    if (!study.isShowingResult && question.step != TestStep.cnToEn) {
      if (hasQuizSyllables) {
        _startQuizSyllableSequence(question.wordId, hasMorphemes: hasQuizMorphemes);
      } else {
        _autoPlay('q_${question.wordId}_${question.step.name}', question.wordId);
      }
    }

    return Column(
      children: [
        _buildStepIndicator(question.step),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              children: [
                const SizedBox(height: 16),
                _buildQuestionCard(question),
                const SizedBox(height: 24),
                if (question.step == TestStep.spelling)
                  _buildSpellingArea(question, study)
                else
                  _buildChoiceOptions(question, study),
                if (study.isShowingResult) ...[
                  const SizedBox(height: 20),
                  _buildResultFooter(study),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 步骤指示器
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildStepIndicator(TestStep step) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          _buildStepChip('英→汉', TestStep.enToCn, step),
          _buildStepConnector(step.index >= TestStep.cnToEn.index),
          _buildStepChip('汉→英', TestStep.cnToEn, step),
          _buildStepConnector(step.index >= TestStep.spelling.index),
          _buildStepChip('拼写', TestStep.spelling, step),
        ],
      ),
    );
  }

  Widget _buildStepChip(String label, TestStep thisStep, TestStep currentStep) {
    final isActive = thisStep == currentStep;
    final isPast = thisStep.index < currentStep.index;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary
            : isPast
                ? AppColors.success.withOpacity(0.15)
                : AppColors.divider.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isActive
              ? Colors.white
              : isPast
                  ? AppColors.success
                  : AppColors.textHint,
        ),
      ),
    );
  }

  Widget _buildStepConnector(bool active) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: active ? AppColors.success.withOpacity(0.3) : AppColors.divider,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 题干卡片
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildQuestionCard(TestQuestion question) {
    final isEnToCn = question.step == TestStep.enToCn;
    final isCnToEn = question.step == TestStep.cnToEn;
    final isSpelling = question.step == TestStep.spelling;

    // ★ v5.2: 根据动画阶段决定显示方式
    final isSingleWord = isEnToCn
        && !question.word.contains(' ')
        && !question.word.startsWith('-')
        && !question.word.endsWith('-');

    final showSyllableDot = isSingleWord
        && _quizSyllablePhase == 'split'
        && question.syllables.length > 1;

    final showMorpheme = isSingleWord
        && _quizSyllablePhase == 'morpheme'
        && question.morphemes.isNotEmpty;

    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const SizedBox(height: 8),
            if (isEnToCn || isSpelling) ...[
              // ★ v5.2: 单词展示（整词 → 音节拆分 → 词根词缀）
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: isSpelling
                      ? Text(
                          question.meaning,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        )
                      : showMorpheme
                        ? _buildMorphemeText(question.morphemes, 28)
                        : showSyllableDot
                          ? _buildSyllableDotText(question.syllables, 32)
                          : Text(
                              question.word,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                  ),
                  if (isEnToCn) _buildPlayButton(question.wordId),
                ],
              ),
              if (!isSpelling && question.phonetic != null) ...[
                const SizedBox(height: 8),
                Text(
                  question.phonetic!,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ] else ...[
              Text(
                question.meaning,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ★ v5.1: 音节圆点分隔展示（用于测试页面）
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSyllableDotText(List<String> syllables, double fontSize) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < syllables.length; i++) ...[
          if (i > 0) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text('·',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(syllables[i],
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ★ v5.2: 词根词缀构词法展示
  // 颜色: 前缀=蓝色  词根=橙色  后缀=绿色
  // ═══════════════════════════════════════════════════════════════════════

  static const _morphemeColors = {
    'prefix': Color(0xFF2196F3),  // 蓝色
    'root':   Color(0xFFE65100),  // 橙色
    'suffix': Color(0xFF4CAF50),  // 绿色
  };

  Widget _buildMorphemeText(List<Map<String, dynamic>> morphemes, double fontSize) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第一行：带颜色的词素拆分  ac + cept + ance
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < morphemes.length; i++) ...[
              if (i > 0) Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('+',
                  style: TextStyle(
                    fontSize: fontSize * 0.7,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textHint,
                  ),
                ),
              ),
              Text(
                morphemes[i]['part'] as String? ?? '',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  color: _morphemeColors[morphemes[i]['type']] ?? AppColors.textPrimary,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        // 第二行：每个词素的含义
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < morphemes.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    morphemes[i]['part'] as String? ?? '',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _morphemeColors[morphemes[i]['type']] ?? AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    (morphemes[i]['meaning'] as String? ?? '').isEmpty
                        ? (morphemes[i]['origin'] as String? ?? '')
                        : (morphemes[i]['meaning'] as String? ?? ''),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ★ v3.0: 选择题选项 — 答题后公布每个选项的完整答案
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildChoiceOptions(TestQuestion question, StudyState study) {
    return Column(
      children: List.generate(question.options.length, (index) {
        final option = question.options[index];
        final isSelected = _selectedOptionIndex == index;
        final isShowingResult = study.isShowingResult;
        final isCorrect = index == question.correctIndex;

        Color bgColor = AppColors.surface;
        Color borderColor = AppColors.cardBorder;
        Color textColor = AppColors.textPrimary;
        IconData? icon;

        if (isShowingResult) {
          if (isCorrect) {
            bgColor = AppColors.success.withOpacity(0.1);
            borderColor = AppColors.success;
            textColor = AppColors.success;
            icon = Icons.check_circle_rounded;
          } else if (isSelected && !isCorrect) {
            bgColor = AppColors.error.withOpacity(0.1);
            borderColor = AppColors.error;
            textColor = AppColors.error;
            icon = Icons.cancel_rounded;
          } else {
            textColor = AppColors.textHint;
          }
        } else if (isSelected) {
          bgColor = AppColors.primary.withOpacity(0.08);
          borderColor = AppColors.primary;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: isShowingResult || _isAnimating
                  ? null
                  : () => _onOptionTap(index),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 序号/图标
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isShowingResult && isCorrect
                            ? AppColors.success.withOpacity(0.2)
                            : isShowingResult && isSelected && !isCorrect
                                ? AppColors.error.withOpacity(0.2)
                                : AppColors.divider.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: icon != null
                            ? Icon(icon, size: 18, color: textColor)
                            : Text(
                                String.fromCharCode(65 + index),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: textColor,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // ★ v3.0: 选项内容 — 答题后显示完整答案
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option.text,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                          // ★ 答题后显示附加信息（英文单词或中文释义）
                          if (isShowingResult && option.subText != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              option.subText!,
                              style: TextStyle(
                                fontSize: 13,
                                color: isCorrect
                                    ? AppColors.success.withOpacity(0.8)
                                    : isSelected && !isCorrect
                                        ? AppColors.error.withOpacity(0.7)
                                        : AppColors.textHint,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  void _onOptionTap(int index) {
    setState(() {
      _selectedOptionIndex = index;
      _isAnimating = true;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        ref.read(studyProvider.notifier).submitChoiceAnswer(index);
        setState(() {
          _isAnimating = false;
        });
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ★ v3.2: 拼写区域 — 音节块拼接（类似截图效果）
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSpellingArea(TestQuestion question, StudyState study) {
    // scrambledLetters 现在存的是打乱的音节块
    final chunks = question.scrambledLetters;
    // spellingHint 存的是正确顺序（用|分隔）
    final correctChunks = question.spellingHint?.split('|') ?? [];

    if (_letterUsed.length != chunks.length) {
      _letterUsed = List.generate(chunks.length, (_) => false);
      _selectedLetters = [];
    }

    return Column(
      children: [
        const SizedBox(height: 8),

        // ★ 顶部：已选块 / 空位槽
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: List.generate(correctChunks.length, (slotIdx) {
            final bool isFilled = slotIdx < _selectedLetters.length;
            final String? chunk = isFilled ? _selectedLetters[slotIdx] : null;

            // 判断对错（结果显示时）
            final bool showResult = study.isShowingResult;
            final bool isCorrectChunk = showResult &&
                chunk != null &&
                slotIdx < correctChunks.length &&
                chunk == correctChunks[slotIdx];

            return GestureDetector(
              onTap: (showResult || !isFilled)
                  ? null
                  : () => _removeChunkAt(slotIdx, chunks),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                constraints: const BoxConstraints(minWidth: 60),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: showResult
                      ? (study.lastResult?.isCorrect == true
                          ? AppColors.success.withOpacity(0.12)
                          : isCorrectChunk
                              ? AppColors.success.withOpacity(0.12)
                              : AppColors.error.withOpacity(0.12))
                      : isFilled
                          ? AppColors.primary.withOpacity(0.1)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    bottom: BorderSide(
                      color: showResult
                          ? (study.lastResult?.isCorrect == true
                              ? AppColors.success
                              : AppColors.error)
                          : isFilled
                              ? AppColors.primary
                              : AppColors.textHint.withOpacity(0.4),
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  isFilled ? chunk! : '      ',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: showResult
                        ? (study.lastResult?.isCorrect == true
                            ? AppColors.success
                            : AppColors.error)
                        : AppColors.primary,
                    letterSpacing: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }),
        ),

        const SizedBox(height: 32),

        // ★ 底部：可选的音节块按钮
        if (!study.isShowingResult)
          Wrap(
            spacing: 14,
            runSpacing: 14,
            alignment: WrapAlignment.center,
            children: List.generate(chunks.length, (index) {
              final chunk = chunks[index];
              final isUsed = _letterUsed[index];

              return GestureDetector(
                onTap: isUsed ? null : () => _selectChunk(index, chunks),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isUsed ? 0.25 : 1.0,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 64),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: isUsed
                          ? AppColors.divider.withOpacity(0.5)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isUsed
                            ? AppColors.divider
                            : AppColors.cardBorder,
                        width: 1.5,
                      ),
                      boxShadow: isUsed
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                    ),
                    child: Text(
                      chunk,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: isUsed
                            ? AppColors.textHint
                            : AppColors.textPrimary,
                        letterSpacing: 1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }),
          ),

        // ★ 结果显示时如果答错，显示正确答案
        if (study.isShowingResult &&
            study.lastResult?.isCorrect == false) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '正确拼写：${question.word}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.success,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _selectChunk(int index, List<String> chunks) {
    final correctChunks =
        ref.read(studyProvider).currentQuestion?.spellingHint?.split('|') ?? [];
    setState(() {
      _selectedLetters.add(chunks[index]);
      _letterUsed[index] = true;
    });

    // 如果全部块都已选择，自动提交
    if (_selectedLetters.length == correctChunks.length) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          final answer = _selectedLetters.join();
          ref.read(studyProvider.notifier).submitSpellingAnswer(answer);
        }
      });
    }
  }

  void _removeChunkAt(int selectedIdx, List<String> chunks) {
    final chunk = _selectedLetters[selectedIdx];
    setState(() {
      _selectedLetters.removeAt(selectedIdx);
      // 找到对应的原始块并恢复
      for (int i = 0; i < chunks.length; i++) {
        if (_letterUsed[i] && chunks[i] == chunk) {
          _letterUsed[i] = false;
          break;
        }
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 结果反馈
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildResultFooter(StudyState study) {
    final result = study.lastResult;
    if (result == null) return const SizedBox.shrink();

    final isCorrect = result.isCorrect;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isCorrect
            ? AppColors.success.withOpacity(0.08)
            : AppColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            Row(
              children: [
                Icon(
                  isCorrect
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: isCorrect ? AppColors.success : AppColors.error,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCorrect ? '回答正确！' : '回答错误',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color:
                              isCorrect ? AppColors.success : AppColors.error,
                        ),
                      ),
                      if (!isCorrect) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${result.word} = ${result.meaning}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '答错会重新从第一步开始',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.error.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // ★ v4.5: 小喇叭放在结果行右侧
                _buildPlayButton(study.currentQuestion?.wordId ?? '', size: 24),
              ],
            ),
            // ★ v4.5: 喇叭和下一题按钮之间，小喇叭靠右
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _selectedOptionIndex = null;
                    _selectedLetters = [];
                    _letterUsed = [];
                  });
                  if (study.isComplete) {
                    Navigator.pop(context);
                  } else {
                    ref.read(studyProvider.notifier).nextQuestion();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isCorrect ? AppColors.success : AppColors.primary,
                ),
                child: Text(
                  study.isComplete ? '完成' : '下一题',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ★ v4.0: 单词学习界面 — 做完三步测试后展示
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildWordDetailView(StudyState study) {
    final word = study.wordDetailData;
    if (word == null) return const SizedBox.shrink();

    final wordText = word['word'] as String? ?? '';
    final phoneticUs = word['phonetic_us'] as String? ?? '';
    final phoneticUk = word['phonetic_uk'] as String? ?? '';
    final definitions = word['definitions'] as List? ?? [];

    final wordId = word['id']?.toString() ?? '';
    final imageUrl = wordId.isNotEmpty
        ? '${ApiConfig.baseUrl}/media/$wordId/image'
        : '';

    // ★ v5.0: 提取音节数据并触发动画序列
    final rawSyllables = word['syllables'] as List?;
    final syllables = rawSyllables?.map((s) => s.toString()).toList() ?? <String>[];
    // 仅对单个英文单词触发（不含空格、不含连字符开头/结尾）
    final shouldAnimate = syllables.length > 1
        && !wordText.contains(' ')
        && !wordText.startsWith('-')
        && !wordText.endsWith('-');
    if (shouldAnimate && _lastDetailWordId != wordId) {
      // ★ v5.2: 提取词根词缀数据供动画序列使用
      final rawMorphemes = word['morphemes'] as List?;
      _detailMorphemes = rawMorphemes
          ?.map((m) => Map<String, dynamic>.from(m as Map))
          .toList() ?? <Map<String, dynamic>>[];
      Future.microtask(() => _startSyllableSequence(wordId, syllables));
    } else if (!shouldAnimate && _lastDetailWordId != wordId) {
      // 短语/词缀等不做动画，正常自动播放一次
      _lastDetailWordId = wordId;
      _syllablePhase = 'idle';
      _syllables = [];
      _detailMorphemes = [];
      _autoPlay('detail_$wordId', wordId);
    }

    // ★ v4.7: 提取简短释义（显示在单词右侧）
    String briefMeaning = '';
    for (final def in definitions.take(2)) {
      final pos = (def['pos'] as String? ?? '').trim();
      final cn = (def['cn'] as String? ?? '').trim();
      final meaning = (def['meaning'] as String? ?? '').trim();
      final defCn = (def['definition_cn'] as String? ?? '').trim();

      String text = '';
      if (cn.isNotEmpty && RegExp(r'[\u4e00-\u9fff]').hasMatch(cn)) {
        text = cn;
      } else if (meaning.isNotEmpty && RegExp(r'[\u4e00-\u9fff]').hasMatch(meaning)) {
        text = meaning;
      } else if (defCn.isNotEmpty) {
        text = defCn;
      }
      if (text.isEmpty) continue;

      final prefix = pos.isNotEmpty ? '$pos ' : '';
      if (briefMeaning.isEmpty) {
        briefMeaning = '$prefix$text';
      } else {
        briefMeaning += '；$prefix$text';
        break; // 最多两条
      }
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ══════════════════════════════════════════
                // 上部：图片区域（完整展示，不裁切）
                // ══════════════════════════════════════════
                Stack(
                  children: [
                    // ── 深色底色 + 完整图片 ──
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 220),
                      color: const Color(0xFF141C2A),
                      child: imageUrl.isNotEmpty
                          ? Image.network(
                              imageUrl,
                              width: double.infinity,
                              fit: BoxFit.contain, // ★ 完整显示，不裁切
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const SizedBox(
                                  height: 220,
                                  child: Center(
                                    child: SizedBox(width: 28, height: 28,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38)),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  height: 220,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
                                    ),
                                  ),
                                );
                              },
                            )
                          : Container(
                              height: 220,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
                                ),
                              ),
                            ),
                    ),

                    // ── 底部渐变（让文字和图片过渡自然） ──
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      height: 100,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              const Color(0xFF141C2A).withOpacity(0.85),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── 右上角 ✅ 完成标识 ──
                    Positioned(
                      top: 10, right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text('学习完成',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),

                    // ── 左下角：单词 + 喇叭 + 释义（一行） ──
                    Positioned(
                      left: 16, right: 16, bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ★ v4.7: 单词 + 喇叭 + 释义 在同一行
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // ★ v5.0: 音节动画单词
                              Flexible(
                                child: _buildAnimatedWordText(wordText, wordId),
                              ),
                              const SizedBox(width: 8),
                              // 喇叭
                              GestureDetector(
                                onTap: () => _playWord(wordId),
                                child: Container(
                                  width: 34, height: 34,
                                  margin: const EdgeInsets.only(bottom: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _isPlaying ? Icons.volume_up_rounded : Icons.volume_up_outlined,
                                    color: Colors.white, size: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // 释义
                              if (briefMeaning.isNotEmpty)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                      briefMeaning,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withOpacity(0.85),
                                        shadows: const [Shadow(blurRadius: 8, color: Colors.black54, offset: Offset(0, 1))],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (phoneticUs.isNotEmpty || phoneticUk.isNotEmpty)
                            Row(
                              children: [
                                if (phoneticUs.isNotEmpty)
                                  GestureDetector(
                                    onTap: () => _playWord(wordId, accent: 'us'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.volume_up_outlined, size: 12, color: Colors.white70),
                                          const SizedBox(width: 3),
                                          Text('美 $phoneticUs',
                                            style: const TextStyle(fontSize: 12, color: Colors.white70)),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (phoneticUs.isNotEmpty && phoneticUk.isNotEmpty)
                                  const SizedBox(width: 6),
                                if (phoneticUk.isNotEmpty)
                                  GestureDetector(
                                    onTap: () => _playWord(wordId, accent: 'uk'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.volume_up_outlined, size: 12, color: Colors.white70),
                                          const SizedBox(width: 3),
                                          Text('英 $phoneticUk',
                                            style: const TextStyle(fontSize: 12, color: Colors.white70)),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                // ══════════════════════════════════════════
                // 下部：词根词缀构词法卡片
                // ══════════════════════════════════════════
                Builder(
                  builder: (context) {
                    final rawMorphemes = word['morphemes'] as List?;
                    final morphemes = rawMorphemes
                        ?.map((m) => Map<String, dynamic>.from(m as Map))
                        .toList() ?? <Map<String, dynamic>>[];

                    if (morphemes.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      color: AppColors.background,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 标题行
                          Row(
                            children: [
                              Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Text('构词法拆解',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // 词根词缀展示
                          Center(
                            child: _buildMorphemeText(morphemes, 24),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        // ★ 底部按钮
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _selectedOptionIndex = null;
                  _selectedLetters = [];
                  _letterUsed = [];
                  // ★ v5.0: 重置音节动画状态
                  _syllablePhase = 'idle';
                  _syllables = [];
                  _activeSyllableIndex = -1;
                  _syllablesExpanded = false;
                  _lastDetailWordId = '';
                  _detailMorphemes = []; // ★ v5.2
                });
                if (study.isComplete) {
                  Navigator.pop(context);
                } else {
                  ref.read(studyProvider.notifier).dismissWordDetail();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: Text(
                study.isComplete ? '完成学习' : '下一词',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildCompleteView(StudyState study) {
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
            const Text('学习完成！',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              '你已完成 ${study.completedWordCount} 个单词的三步测试',
              style: const TextStyle(
                  fontSize: 16, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              '共完成 ${study.completedQuestions} 道题',
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textHint),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回首页'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 错误视图
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildErrorView(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(error,
                style: const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}
