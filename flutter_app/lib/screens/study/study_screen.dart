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
  String _detailBriefMeaning = ''; // ★ v5.3: 详情页词义

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
  // ★ v5.3: 测试页面四阶段动画序列
  // 流程: ①整词+播放 → ②音节拆分+播放 → ③词根词缀+播放 → ④总结展示
  // ═══════════════════════════════════════════════════════════════════════

  void _startQuizSyllableSequence(String wordId, {bool hasMorphemes = false}) {
    final key = 'quiz_syl_$wordId';
    if (key == _lastAutoPlayedKey || wordId.isEmpty) return;
    _lastAutoPlayedKey = key;
    _lastQuizWordId = wordId;
    setState(() => _quizSyllablePhase = 'whole');

    final url = '${ApiConfig.baseUrl}/media/$wordId/audio?accent=us';

    void playAudio(String nextPhase, VoidCallback? onDone) {
      if (!mounted || _lastQuizWordId != wordId) return;
      _audioElement?.pause();
      _audioElement = html.AudioElement(url);
      setState(() => _isPlaying = true);
      _audioElement!.onEnded.listen((_) {
        if (!mounted) return;
        setState(() => _isPlaying = false);
        if (onDone != null) onDone();
      });
      _audioElement!.onError.listen((_) {
        if (mounted) {
          setState(() => _isPlaying = false);
          if (onDone != null) onDone();
        }
      });
      _audioElement!.play();
    }

    // ── 第一遍：显示整词 ──
    Future.delayed(const Duration(milliseconds: 300), () {
      playAudio('whole', () {
        // ── 第一遍结束 → 0.8s → 切到音节拆分 + 播放第二遍 ──
        Future.delayed(const Duration(milliseconds: 800), () {
          if (!mounted || _lastQuizWordId != wordId) return;
          setState(() => _quizSyllablePhase = 'split');
          Future.delayed(const Duration(milliseconds: 100), () {
            playAudio('split', () {
              // ── 第二遍结束 → 0.8s → 切到词根词缀 + 播放第三遍 ──
              if (hasMorphemes) {
                Future.delayed(const Duration(milliseconds: 800), () {
                  if (!mounted || _lastQuizWordId != wordId) return;
                  setState(() => _quizSyllablePhase = 'morpheme');
                  Future.delayed(const Duration(milliseconds: 100), () {
                    playAudio('morpheme', () {
                      // ── 第三遍结束 → 0.8s → 切到总结展示 ──
                      Future.delayed(const Duration(milliseconds: 800), () {
                        if (!mounted || _lastQuizWordId != wordId) return;
                        setState(() => _quizSyllablePhase = 'summary');
                      });
                    });
                  });
                });
              }
            });
          });
        });
      });
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
      return _buildDetailMorphemeText(_detailMorphemes, wordText, _detailBriefMeaning);
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

  Widget _buildDetailMorphemeText(List<Map<String, dynamic>> morphemes, String wordText, String briefMeaning) {
    final shortMeaning = _cleanMeaning(briefMeaning);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < morphemes.length; i++) ...[
          if (i > 0) Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text('  +  ',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withOpacity(0.5),
                shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                morphemes[i]['part'] as String? ?? '',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: _detailMorphemeColors[morphemes[i]['type']] ?? Colors.white,
                  shadows: const [Shadow(blurRadius: 8, color: Colors.black54, offset: Offset(0, 1))],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _getMorphemeMeaning(morphemes[i]),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _detailMorphemeColors[morphemes[i]['type']]?.withOpacity(0.8) ?? Colors.white70,
                  shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            ],
          ),
        ],
        // = 单词
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text('  =  ',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withOpacity(0.5),
              shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              wordText,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                shadows: [Shadow(blurRadius: 8, color: Colors.black54, offset: Offset(0, 1))],
              ),
            ),
            if (shortMeaning.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                shortMeaning,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// 获取词素的展示含义：优先 meaning，其次 origin，最后显示词素本身
  String _getMorphemeMeaning(Map<String, dynamic> m) {
    final meaning = (m['meaning'] as String? ?? '').trim();
    if (meaning.isNotEmpty) return meaning;
    final origin = (m['origin'] as String? ?? '').trim();
    if (origin.isNotEmpty) return origin;
    // 没有中文含义时显示词素英文本身（自由词根通常是可识别的单词）
    return m['part'] as String? ?? '';
  }

  /// ★ v5.8: 构词推导 — 用自然的中文解释词素如何组合成单词含义
  String _buildDerivation(List<Map<String, dynamic>> morphemes, String wordMeaning) {
    if (morphemes.length < 2) return '';

    // 收集各部分含义
    final parts = <Map<String, String>>[];
    for (final m in morphemes) {
      final meaning = (m['meaning'] as String? ?? '').trim();
      final type = (m['type'] as String? ?? 'root');
      final part = (m['part'] as String? ?? '');
      if (meaning.isEmpty) continue;
      parts.add({'meaning': meaning, 'type': type, 'part': part});
    }
    if (parts.isEmpty) return '';

    // 分离：前缀 + 词根 + 后缀
    final prefixes = parts.where((p) => p['type'] == 'prefix').toList();
    final roots = parts.where((p) => p['type'] == 'root').toList();
    final suffixes = parts.where((p) => p['type'] == 'suffix').toList();

    // 构建核心含义（前缀 + 词根）
    String core = '';
    for (final p in prefixes) {
      final m = p['meaning']!;
      // 前缀取第一个含义
      core += m.split(',').first.split('，').first;
    }
    for (final r in roots) {
      // 词根取最自然的含义（优先选2字以上的中文词）
      final meanings = r['meaning']!.split(RegExp(r'[,，]'));
      String best = meanings.first;
      for (final m in meanings) {
        final trimmed = m.trim();
        if (trimmed.length >= 2 && trimmed.length > best.trim().length) {
          best = trimmed;
        }
      }
      core += best.trim();
    }
    if (core.isEmpty) return '';

    // 用后缀模板包装核心含义
    String result = core;
    for (final s in suffixes) {
      result = _applySuffix(result, s['meaning']!);
    }

    // 清理
    result = result.replaceAll('的的', '的');
    result = result.replaceAll('的地', '地');
    if (result.startsWith('的')) result = result.substring(1);

    // 拼接最终词义
    final shortMeaning = _cleanMeaning(wordMeaning);
    if (shortMeaning.isEmpty || result == shortMeaning) return result;

    return '$result → $shortMeaning';
  }

  /// 根据后缀含义模板，自然地包装核心词义
  String _applySuffix(String core, String suffixMeaning) {
    final s = suffixMeaning.trim();

    // 直接助词：的、地、者、化
    if (s == '的' || s == '…的') return '${core}的';
    if (s == '地' || s == '…地') return '${core}地';
    if (s == '者' || s == '…者') return '${core}的人';
    if (s == '化') return '使$core';

    // 模板型：有…性质的 → 具有[core]性质的
    if (s.contains('…')) {
      return s.replaceAll('…', core).replaceAll('...', core);
    }

    // 名词化后缀（组合判断优先）
    if (s.contains('行为') && s.contains('结果')) return '${core}的行为或结果';
    if (s.contains('行为') || s.contains('过程')) return '${core}的过程';
    if (s.contains('结果') || s.contains('产物')) return '${core}的结果';
    if (s.contains('性质') && s.contains('状态')) return '${core}的状态';
    if (s.contains('性质')) return '${core}的特性';
    if (s.contains('状态')) return '${core}的状态';
    if (s.contains('名词') || s.contains('事物')) return '${core}的事物';
    if (s.contains('能') && s.contains('的')) return '能够${core}的';
    if (s.contains('被') && s.contains('的')) return '可以被${core}的';
    if (s.contains('学科') || s.contains('学')) return '关于${core}的学科';
    if (s.contains('倾向') || s.contains('主义')) return '${core}主义';

    // 形容词化
    if (s.endsWith('的')) return '$core$s';

    // 副词化
    if (s.endsWith('地')) return '$core$s';

    // 默认：用"的"连接
    final clean = s.replaceAll('…', '').replaceAll('...', '');
    return '$core$clean';
  }

  /// 从完整释义中提取简短中文含义
  /// 例: "n. (U/C)车祸，事故；意外的事" → "车祸,事故"
  String _cleanMeaning(String raw) {
    if (raw.isEmpty) return '';
    // 去掉词性标记 (n. / v. / adj. / adv. 等)
    var s = raw.replaceAll(RegExp(r'^[a-zA-Z]+\.\s*'), '');
    // 去掉括号标记 (U/C) 等
    s = s.replaceAll(RegExp(r'\([^)]*\)'), '');
    // 取第一个分号或句号之前的部分
    final idx = s.indexOf(RegExp(r'[；;。]'));
    if (idx > 0) s = s.substring(0, idx);
    return s.trim();
  }

  /// 从 definitions 列表中提取第一个中文释义
  String _extractBriefMeaning(List defs) {
    for (final def in defs.take(2)) {
      if (def is! Map) continue;
      for (final key in ['cn', 'meaning', 'definition_cn']) {
        final val = (def[key] as String? ?? '').trim();
        if (val.isNotEmpty && RegExp(r'[\u4e00-\u9fff]').hasMatch(val)) {
          return val;
        }
      }
    }
    return '';
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

    // ★ v5.3: 四阶段动画判定
    final isSingleWord = isEnToCn
        && !question.word.contains(' ')
        && !question.word.startsWith('-')
        && !question.word.endsWith('-');
    final hasSyllables = isSingleWord && question.syllables.length > 1;
    final hasMorphemes = isSingleWord && question.morphemes.isNotEmpty;
    final phase = _quizSyllablePhase; // whole / split / morpheme / summary

    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const SizedBox(height: 8),
            if (isCnToEn) ...[
              // 汉→英：显示中文含义
              Text(
                question.meaning,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            ] else if (isSpelling) ...[
              // 拼写题：显示中文含义
              Text(
                question.meaning,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            ] else if (hasSyllables && phase == 'summary') ...[
              // ★ 第四阶段：总结展示 — 三行居中带标签
              _buildQuizSummary(question),
            ] else ...[
              // ★ 第一/二/三阶段：渐进式展示
              // 已完成阶段显示在上方（小字灰色）
              if (phase == 'split' || phase == 'morpheme') ...[
                // 整词退到上方
                _buildPhaseLabel(question.word, '读音'),
                const SizedBox(height: 6),
              ],
              if (phase == 'morpheme' && hasSyllables) ...[
                // 音节也退到上方
                _buildPhaseLabel(question.syllables.join(' · '), '音节拆分'),
                const SizedBox(height: 10),
              ],
              // 当前阶段居中大字
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: phase == 'morpheme' && hasMorphemes
                      ? _buildQuizMorphemeText(question.morphemes)
                      : phase == 'split' && hasSyllables
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
              if (!isSpelling && question.phonetic != null && phase == 'whole') ...[
                const SizedBox(height: 8),
                Text(
                  question.phonetic!,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// ★ v5.3: 已完成阶段的小标签（灰色，靠左）
  Widget _buildPhaseLabel(String text, String label) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textHint,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.divider,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textHint,
            ),
          ),
        ),
      ],
    );
  }

  /// ★ v5.3: 总结展示 — 居中对齐，三个带边框的卡片
  Widget _buildQuizSummary(TestQuestion question) {
    // ★ v5.6: 优先使用后端 syllable_ipa（管理员手动编辑的数据），无数据时才自动拆分
    final syllablePhonetics = question.syllableIpa.isNotEmpty
        ? question.syllableIpa
        : _splitPhonetic(question.phonetic ?? '', question.syllables);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── ① 单词 + 音标 + 喇叭 ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                question.word,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              if (question.phonetic != null) ...[
                const SizedBox(width: 8),
                Text(
                  question.phonetic!,
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                ),
              ],
              _buildPlayButton(question.wordId, size: 22),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // ── ② 音节拆分 + 各音节音标 ──
        if (question.syllables.length > 1) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
              color: AppColors.primary.withOpacity(0.03),
            ),
            child: Row(
              children: [
                // 固定宽度标签（与构词对齐）
                SizedBox(
                  width: 36,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('音节',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 音节内容
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < question.syllables.length; i++) ...[
                        if (i > 0) Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text('  ·  ',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textHint),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              question.syllables[i],
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              syllablePhonetics.length > i ? syllablePhonetics[i] : '',
                              style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

        // ── ③ 构词拆分 ──
        if (question.morphemes.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
              color: Colors.orange.withOpacity(0.03),
            ),
            child: Row(
              children: [
                // 固定宽度标签（与音节对齐）
                SizedBox(
                  width: 36,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('构词',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.deepOrange),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 构词内容
                Flexible(
                  child: _buildQuizMorphemeText(question.morphemes),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// ★ v5.4: 将完整音标按拼音风格拆分到各个音节
  /// 核心算法：最大声母原则（Maximal Onset Principle）
  /// 两个元音之间的辅音串，从右往左尽可能多地归入下一音节做"声母"，
  /// 剩余辅音留在上一音节做"韵尾"。这与汉语拼音"声母+韵母"逻辑一致。
  /// 特殊处理：重音符号(ˈˌ)始终归入下一音节；n/l/m/ŋ 后跟其他辅音时留在上一音节。
  /// 例: "accurately" /ˈækjərətli/ → /ˈæk/ /jər/ /rət/ /li/ ✗(旧)
  ///     → /ˈæk/ /jə/ /rət/ /li/ ✓(新：r归入rate音节做声母)
  List<String> _splitPhonetic(String phonetic, List<String> syllables) {
    if (phonetic.isEmpty || syllables.isEmpty) return [];

    var raw = phonetic.trim();
    if (raw.startsWith('/')) raw = raw.substring(1);
    if (raw.endsWith('/')) raw = raw.substring(0, raw.length - 1);
    raw = raw.trim();
    if (raw.isEmpty) return [];

    const ipaVowels = 'æɑɒʌɛəɪɔʊaeiouɜɝɚ';
    const stressChars = 'ˈˌ';
    const diphthongSeconds = {'ɪ', 'ʊ', 'ə'};

    final chars = raw.runes.map((r) => String.fromCharCode(r)).toList();
    final n = chars.length;

    // ── 合法英语声母（onset）集合 ──
    // 单辅音声母：几乎所有辅音都可以做声母
    const singleOnsets = <String>{
      'p', 'b', 't', 'd', 'k', 'ɡ', 'g', 'f', 'v', 'θ', 'ð',
      's', 'z', 'ʃ', 'ʒ', 'h', 'm', 'n', 'l', 'r', 'ɹ', 'w', 'j',
      'tʃ', 'dʒ', 'ŋ',
    };
    // 双辅音声母
    const doubleOnsets = <String>{
      'pl', 'pr', 'pɹ', 'bl', 'br', 'bɹ', 'tr', 'tɹ', 'dr', 'dɹ',
      'kl', 'kr', 'kɹ', 'ɡl', 'ɡr', 'ɡɹ', 'gl', 'gr',
      'fl', 'fr', 'fɹ', 'θr', 'θɹ', 'ʃr', 'ʃɹ',
      'sl', 'sm', 'sn', 'sw', 'sp', 'st', 'sk',
      'sf', 'sv',
      'tw', 'dw', 'kw', 'ɡw', 'gw', 'hw',
      'pj', 'bj', 'tj', 'dj', 'kj', 'ɡj', 'gj', 'fj', 'vj',
      'hj', 'mj', 'nj', 'lj',
    };
    // 三辅音声母
    const tripleOnsets = <String>{
      'spl', 'spr', 'spɹ', 'str', 'stɹ', 'skr', 'skɹ',
      'skl', 'skw', 'spj', 'stj', 'skj',
    };

    // 1. 找元音核心位置（双元音算一个）
    final vowelPos = <int>[];
    // vowelEnd[i] = 第i个元音核心结束位置（不含）
    final vowelEnd = <int>[];
    int ci = 0;
    while (ci < n) {
      if (ipaVowels.contains(chars[ci])) {
        vowelPos.add(ci);
        if (ci + 1 < n && ipaVowels.contains(chars[ci + 1]) &&
            diphthongSeconds.contains(chars[ci + 1])) {
          // 双元音：跳过第二个元音字符
          int end = ci + 2;
          // 跳过长音符号 ː
          if (end < n && chars[end] == 'ː') end++;
          vowelEnd.add(end);
          ci = end;
        } else {
          int end = ci + 1;
          // 跳过长音符号 ː
          if (end < n && chars[end] == 'ː') end++;
          vowelEnd.add(end);
          ci = end;
        }
      } else {
        ci++;
      }
    }

    // 元音数不匹配 → 按比例回退
    if (vowelPos.length != syllables.length) {
      return _proportionalPhoneticSplit(chars, syllables);
    }

    // 2. 对每对相邻元音之间的辅音串，用最大声母原则确定分割点
    final splitPoints = <int>[];
    for (int s = 0; s < vowelPos.length - 1; s++) {
      final gapStart = vowelEnd[s]; // 上一个元音结束
      final gapEnd = vowelPos[s + 1]; // 下一个元音开始

      if (gapStart >= gapEnd) {
        // 无辅音间隙，直接在元音结束处分割
        splitPoints.add(gapStart);
        continue;
      }

      // 收集间隙中的辅音（跳过重音符号记录位置）
      final gapChars = <String>[]; // 纯辅音
      final gapOrigIdx = <int>[]; // 每个辅音在chars中的原始位置
      int firstStressIdx = -1; // 间隙中第一个重音符号的原始位置

      for (int g = gapStart; g < gapEnd; g++) {
        if (stressChars.contains(chars[g])) {
          if (firstStressIdx < 0) firstStressIdx = g;
        } else {
          gapChars.add(chars[g]);
          gapOrigIdx.add(g);
        }
      }

      // 如果有重音符号，从重音符号处分割（重音符号及后面的归下一音节）
      if (firstStressIdx >= 0) {
        splitPoints.add(firstStressIdx);
        continue;
      }

      // 无重音符号：用最大声母原则
      // 从右往左尝试：3个辅音、2个辅音、1个辅音 做下一音节的声母
      final cLen = gapChars.length;
      int onsetLen = 0; // 归入下一音节的辅音数

      if (cLen >= 3) {
        final tri = gapChars.sublist(cLen - 3).join('');
        if (tripleOnsets.contains(tri)) {
          onsetLen = 3;
        }
      }
      if (onsetLen == 0 && cLen >= 2) {
        final duo = gapChars.sublist(cLen - 2).join('');
        if (doubleOnsets.contains(duo)) {
          onsetLen = 2;
        }
      }
      if (onsetLen == 0 && cLen >= 1) {
        final single = gapChars[cLen - 1];
        if (singleOnsets.contains(single)) {
          onsetLen = 1;
        }
      }

      // 保底：至少1个辅音做声母（避免元音开头）
      if (onsetLen == 0) onsetLen = 1;
      // 保底：至少保留上一音节的元音（不能把所有辅音都给下一音节）
      // 但如果上一音节已有元音，可以把所有辅音都给下一音节
      if (onsetLen > cLen) onsetLen = cLen;

      // 分割点 = 第一个归入下一音节的辅音的原始位置
      final splitIdx = gapOrigIdx[cLen - onsetLen];
      splitPoints.add(splitIdx);
    }

    // 3. 提取各音节片段，包装为 /.../ 格式
    final result = <String>[];
    int start = 0;
    for (int s = 0; s < syllables.length; s++) {
      final end = (s < splitPoints.length) ? splitPoints[s] : n;
      if (start >= n) { result.add(''); continue; }
      final segment = chars.sublist(start, end.clamp(start, n)).join('');
      result.add('/$segment/');
      start = end;
    }
    return result;
  }

  /// 按比例回退分割（元音数不匹配时使用）
  List<String> _proportionalPhoneticSplit(List<String> chars, List<String> syllables) {
    final totalText = syllables.join('').length;
    final totalPhon = chars.length;
    final result = <String>[];
    int start = 0;
    for (int i = 0; i < syllables.length; i++) {
      int count;
      if (i == syllables.length - 1) {
        count = totalPhon - start;
      } else {
        count = (totalPhon * syllables[i].length / totalText).round().clamp(1, totalPhon - start);
      }
      if (start + count > totalPhon) count = totalPhon - start;
      if (count <= 0) { result.add(''); continue; }
      result.add('/${chars.sublist(start, start + count).join('')}/');
      start += count;
    }
    return result;
  }

  /// ★ v5.3: 测试页词根词缀展示 — 纯拆分，不显示中文含义
  Widget _buildQuizMorphemeText(List<Map<String, dynamic>> morphemes) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        for (int i = 0; i < morphemes.length; i++) ...[
          if (i > 0) Text(
            ' + ',
            style: TextStyle(fontSize: 16, color: AppColors.textHint),
          ),
          Text(
            morphemes[i]['part'] as String? ?? '',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _morphemeColors[morphemes[i]['type']] ?? AppColors.textPrimary,
            ),
          ),
        ],
      ],
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

  Widget _buildMorphemeText(List<Map<String, dynamic>> morphemes, double fontSize, String wordText, String wordMeaning, {String? storedDerivation}) {
    final shortMeaning = _cleanMeaning(wordMeaning);
    // ★ v5.8: 优先用后端存储的推导解释，无数据时用算法生成
    final derivation = (storedDerivation != null && storedDerivation.isNotEmpty)
        ? storedDerivation
        : _buildDerivation(morphemes, wordMeaning);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第一行：词素拆分 achieve + ment = achievement
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 4,
          runSpacing: 8,
          children: [
            for (int i = 0; i < morphemes.length; i++) ...[
              if (i > 0) Padding(
                padding: const EdgeInsets.only(bottom: 14, left: 2, right: 2),
                child: Text('+',
                  style: TextStyle(fontSize: fontSize * 0.55, fontWeight: FontWeight.w400, color: AppColors.textHint),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    morphemes[i]['part'] as String? ?? '',
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                      color: _morphemeColors[morphemes[i]['type']] ?? AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _getMorphemeMeaning(morphemes[i]),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: (_morphemeColors[morphemes[i]['type']] ?? AppColors.textSecondary).withOpacity(0.65),
                    ),
                  ),
                ],
              ),
            ],
            // = 单词 + 词义
            Padding(
              padding: const EdgeInsets.only(bottom: 14, left: 4, right: 2),
              child: Text('=',
                style: TextStyle(fontSize: fontSize * 0.55, fontWeight: FontWeight.w400, color: AppColors.textHint),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  wordText,
                  style: TextStyle(
                    fontSize: fontSize * 0.8,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                if (shortMeaning.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    shortMeaning,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary.withOpacity(0.5),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        // 第二行：推导解释
        if (derivation.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '💡 $derivation',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF795548),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
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
      // ★ v5.3: 提取简短中文释义供词根词缀展示使用
      _detailBriefMeaning = _extractBriefMeaning(definitions);
      Future.microtask(() => _startSyllableSequence(wordId, syllables));
    } else if (!shouldAnimate && _lastDetailWordId != wordId) {
      // 短语/词缀等不做动画，正常自动播放一次
      _lastDetailWordId = wordId;
      _syllablePhase = 'idle';
      _syllables = [];
      _detailMorphemes = [];
      _detailBriefMeaning = '';
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
                            child: _buildMorphemeText(morphemes, 24, wordText, _extractBriefMeaning(definitions), storedDerivation: word['derivation'] as String?),
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
