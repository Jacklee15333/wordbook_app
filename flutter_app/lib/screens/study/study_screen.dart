// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  study_screen.dart  v4.7  2026-03-11                                ║
// ║  v4.7: 单词学习界面加载本地图片（media_storage/image）              ║
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

    // ★ v4.6: 汉→英阶段不自动播放（避免暴露答案），其余步骤正常播放
    if (!study.isShowingResult && question.step != TestStep.cnToEn) {
      _autoPlay('q_${question.wordId}_${question.step.name}', question.wordId);
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

    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const SizedBox(height: 8),
            if (isEnToCn || isSpelling) ...[
              // ★ v4.5: 单词 + 喇叭横排
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      isSpelling ? question.meaning : question.word,
                      style: TextStyle(
                        fontSize: isSpelling ? 20 : 32,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: isSpelling ? 0 : -0.5,
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

                    // ── 左下角：单词 + 音标 + 喇叭 ──
                    Positioned(
                      left: 16, right: 16, bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  wordText,
                                  style: const TextStyle(
                                    fontSize: 34, fontWeight: FontWeight.w800,
                                    color: Colors.white, letterSpacing: -0.5,
                                    shadows: [Shadow(blurRadius: 10, color: Colors.black54, offset: Offset(0, 2))],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _playWord(wordId),
                                child: Container(
                                  width: 34, height: 34,
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
                // 下部：释义等内容（纯白背景，文字清晰）
                // ══════════════════════════════════════════
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  color: AppColors.background,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ★ 释义
                      if (definitions.isNotEmpty) ...[
                        const Text('释义',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        const SizedBox(height: 12),
                        ...definitions.map<Widget>((def) {
                          final pos = (def['pos'] as String? ?? '').trim();
                          final cn = (def['cn'] as String? ?? '').trim();
                          final meaning = (def['meaning'] as String? ?? '').trim();
                          final defCn = (def['definition_cn'] as String? ?? '').trim();
                          final definition = (def['definition'] as String? ?? '').trim();
                          final example = (def['example'] as String? ?? '').trim();
                          final exampleCn = (def['example_cn'] as String? ?? '').trim();

                          String displayCn = '';
                          if (cn.isNotEmpty) {
                            displayCn = cn;
                          } else if (meaning.isNotEmpty && RegExp(r'[\u4e00-\u9fff]').hasMatch(meaning)) {
                            displayCn = meaning;
                          } else if (defCn.isNotEmpty) {
                            displayCn = defCn;
                          }

                          if (displayCn.isEmpty && definition.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.cardBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (pos.isNotEmpty) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(pos,
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Expanded(
                                        child: Text(
                                          displayCn.isNotEmpty ? displayCn : definition,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (definition.isNotEmpty && displayCn.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(definition,
                                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                                  ],
                                  if (example.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.background,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(example,
                                            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontStyle: FontStyle.italic)),
                                          if (exampleCn.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(exampleCn,
                                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ],

                      if (definitions.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('暂无详细释义数据',
                              style: TextStyle(fontSize: 14, color: AppColors.textHint)),
                          ),
                        ),

                      // ── 后续可在这里添加词根词缀、巧记等卡片 ──
                    ],
                  ),
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
