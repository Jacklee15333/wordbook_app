import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/study_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 配色
// ═══════════════════════════════════════════════════════════════════════════

class _C {
  static const bg = Color(0xFFF0F2F5);
  static const primary = Color(0xFF3B82F6);
  static const success = Color(0xFF22C55E);
  static const error = Color(0xFFEF4444);
  static const textPrimary = Color(0xFF1E293B);
  static const textSecondary = Color(0xFF64748B);
  static const textHint = Color(0xFF94A3B8);
  static const divider = Color(0xFFE2E8F0);
  static const card = Color(0xFFFAFBFC);
  static const cardBorder = Color(0xFFE8ECF0);
}

class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({super.key});

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen>
    with SingleTickerProviderStateMixin {
  int? _selectedOptionIndex;
  bool _isAnimating = false;

  // 拼写
  List<String> _orderedChunks = [];
  List<bool> _chunkUsed = [];

  // PASS 印章动画
  bool _showPassStamp = false;
  late AnimationController _stampController;
  late Animation<double> _stampScale;
  late Animation<double> _stampOpacity;

  @override
  void initState() {
    super.initState();
    _stampController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _stampScale = Tween<double>(begin: 2.5, end: 1.0).animate(
      CurvedAnimation(parent: _stampController, curve: Curves.elasticOut),
    );
    _stampOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _stampController,
        curve: const Interval(0, 0.3, curve: Curves.easeIn),
      ),
    );
  }

  @override
  void dispose() {
    _stampController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final study = ref.watch(studyProvider);

    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(study),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: study.progressPercent,
                  backgroundColor: _C.divider,
                  valueColor: const AlwaysStoppedAnimation(_C.primary),
                  minHeight: 4,
                ),
              ),
            ),
            Expanded(
              child: study.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : study.error != null
                      ? _buildErrorView(study.error!)
                      : study.isComplete
                          ? _buildCompleteView(study)
                          : study.currentQuestion != null
                              ? _buildQuestionView(study)
                              : _buildCompleteView(study),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 顶栏
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildTopBar(StudyState study) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: _C.textSecondary, size: 22),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          Text(
            '${study.completedWordCount} / ${study.totalWords} 单词  ·  ${study.completedQuestions} / ${study.totalQuestions} 题',
            style: const TextStyle(
              fontSize: 13,
              color: _C.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 题目视图
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildQuestionView(StudyState study) {
    final question = study.currentQuestion!;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        children: [
          _buildStepBadge(question),
          const SizedBox(height: 16),
          _buildQuestionCard(question),
          const SizedBox(height: 20),

          if (question.step == TestStep.spelling)
            _buildSpellingArea(question, study)
          else
            _buildChoiceOptions(question, study),

          // ── 结果反馈（内嵌，不在底部固定） ──
          if (study.isShowingResult) ...[
            const SizedBox(height: 20),
            _buildResultCard(study),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 步骤标签
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildStepBadge(TestQuestion question) {
    final stepNum = question.step.index + 1;
    final stepLabel = ['英→汉', '汉→英', '拼写'][question.step.index];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: _C.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < 3; i++) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < stepNum
                    ? _C.primary
                    : _C.primary.withOpacity(0.2),
              ),
            ),
            if (i < 2) const SizedBox(width: 4),
          ],
          const SizedBox(width: 8),
          Text(
            '$stepNum/3  $stepLabel',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _C.primary,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 题干卡片
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildQuestionCard(TestQuestion question) {
    final isEnToCn = question.step == TestStep.enToCn;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _C.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          if (isEnToCn) ...[
            Text(
              question.word,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: _C.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            if (question.phonetic != null) ...[
              const SizedBox(height: 8),
              Text(
                question.phonetic!,
                style: const TextStyle(fontSize: 16, color: _C.textHint),
              ),
            ],
          ] else ...[
            Text(
              question.meaning,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _C.textPrimary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 选择题选项
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildChoiceOptions(TestQuestion question, StudyState study) {
    return Column(
      children: List.generate(question.options.length, (index) {
        final option = question.options[index];
        final isSelected = _selectedOptionIndex == index;
        final showResult = study.isShowingResult;
        final isCorrect = index == question.correctIndex;

        Color bg = _C.card;
        Color border = _C.cardBorder;
        Color text = _C.textPrimary;
        Color pair = _C.textHint;

        if (showResult) {
          if (isCorrect) {
            bg = _C.success.withOpacity(0.08);
            border = _C.success.withOpacity(0.4);
            text = _C.success;
            pair = _C.success.withOpacity(0.65);
          } else if (isSelected && !isCorrect) {
            bg = _C.error.withOpacity(0.06);
            border = _C.error.withOpacity(0.4);
            text = _C.error;
            pair = _C.error.withOpacity(0.65);
          } else {
            text = _C.textHint;
            pair = _C.textHint.withOpacity(0.6);
            border = _C.divider;
          }
        } else if (isSelected) {
          bg = _C.primary.withOpacity(0.06);
          border = _C.primary.withOpacity(0.3);
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: showResult || _isAnimating
                  ? null
                  : () => _onOptionTap(index),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border, width: 1.2),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option.text,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: text,
                              height: 1.4,
                            ),
                          ),
                          if (showResult && option.pairText.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              option.pairText,
                              style: TextStyle(
                                fontSize: 13,
                                color: pair,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (showResult && isCorrect)
                      const Icon(Icons.check_circle_rounded,
                          color: _C.success, size: 20),
                    if (showResult && isSelected && !isCorrect)
                      const Icon(Icons.cancel_rounded,
                          color: _C.error, size: 20),
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
        setState(() => _isAnimating = false);
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 拼写区域（拼块排序 + PASS印章）
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSpellingArea(TestQuestion question, StudyState study) {
    if (_chunkUsed.length != question.shuffledChunks.length) {
      _chunkUsed = List.generate(question.shuffledChunks.length, (_) => false);
      _orderedChunks = [];
    }

    final showResult = study.isShowingResult;
    final isCorrect = study.lastResult?.isCorrect == true;

    return Column(
      children: [
        // 答案槽 + PASS印章叠加
        Stack(
          alignment: Alignment.center,
          children: [
            // 答案槽
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: showResult
                    ? (isCorrect
                        ? _C.success.withOpacity(0.06)
                        : _C.error.withOpacity(0.06))
                    : _C.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: showResult
                      ? (isCorrect
                          ? _C.success.withOpacity(0.35)
                          : _C.error.withOpacity(0.35))
                      : _orderedChunks.isNotEmpty
                          ? _C.primary.withOpacity(0.3)
                          : _C.cardBorder,
                  width: 1.5,
                ),
              ),
              child: _orderedChunks.isEmpty && !showResult
                  ? Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          question.correctChunks.length,
                          (i) => Container(
                            width: 40,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: _C.divider,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (int i = 0; i < _orderedChunks.length; i++)
                          GestureDetector(
                            onTap: showResult
                                ? null
                                : () => _removeChunk(i, question),
                            child: _buildChunk(
                              _orderedChunks[i],
                              showResult
                                  ? (isCorrect ? _CS.correct : _CS.wrong)
                                  : _CS.selected,
                            ),
                          ),
                      ],
                    ),
            ),

            // ★ PASS 印章（只在拼写正确时显示）
            if (_showPassStamp)
              AnimatedBuilder(
                animation: _stampController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _stampOpacity.value,
                    child: Transform.scale(
                      scale: _stampScale.value,
                      child: Transform.rotate(
                        angle: -0.2, // 微微倾斜
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: _C.success, width: 4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'PASS',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: _C.success,
                              letterSpacing: 6,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),

        // 答错：正确答案
        if (showResult && !isCorrect) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _C.success.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _C.success.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '正确答案',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _C.success.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: question.correctChunks
                      .map((c) => _buildChunk(c, _CS.correct))
                      .toList(),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),

        // 可选块
        if (!showResult)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: List.generate(question.shuffledChunks.length, (index) {
              final chunk = question.shuffledChunks[index];
              final isUsed = _chunkUsed[index];

              return GestureDetector(
                onTap: isUsed ? null : () => _selectChunk(index, question),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isUsed ? 0.25 : 1.0,
                  child: _buildChunk(
                    chunk,
                    isUsed ? _CS.disabled : _CS.available,
                  ),
                ),
              );
            }),
          ),

        if (!showResult) ...[
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _orderedChunks.isEmpty
                    ? null
                    : () => _clearChunks(question),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重置'),
                style: TextButton.styleFrom(
                  foregroundColor: _C.textSecondary,
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _orderedChunks.isEmpty
                    ? null
                    : () {
                        ref
                            .read(studyProvider.notifier)
                            .submitSpellingAnswer(_orderedChunks);
                        _triggerPassIfCorrect();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('确认',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildChunk(String text, _CS style) {
    Color bg, tc, bc;

    switch (style) {
      case _CS.available:
        bg = _C.card;
        tc = _C.textPrimary;
        bc = _C.cardBorder;
        break;
      case _CS.selected:
        bg = _C.primary.withOpacity(0.08);
        tc = _C.primary;
        bc = _C.primary.withOpacity(0.25);
        break;
      case _CS.correct:
        bg = _C.success.withOpacity(0.08);
        tc = _C.success;
        bc = _C.success.withOpacity(0.25);
        break;
      case _CS.wrong:
        bg = _C.error.withOpacity(0.06);
        tc = _C.error;
        bc = _C.error.withOpacity(0.25);
        break;
      case _CS.disabled:
        bg = _C.divider.withOpacity(0.4);
        tc = _C.textHint;
        bc = Colors.transparent;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: bc, width: 1.2),
        boxShadow: style == _CS.available
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: tc,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  void _selectChunk(int index, TestQuestion question) {
    setState(() {
      _orderedChunks.add(question.shuffledChunks[index]);
      _chunkUsed[index] = true;
    });

    // 全选完自动提交
    if (_orderedChunks.length == question.shuffledChunks.length) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          ref
              .read(studyProvider.notifier)
              .submitSpellingAnswer(_orderedChunks);
          _triggerPassIfCorrect();
        }
      });
    }
  }

  void _removeChunk(int idx, TestQuestion question) {
    final chunk = _orderedChunks[idx];
    setState(() {
      _orderedChunks.removeAt(idx);
      for (int i = 0; i < question.shuffledChunks.length; i++) {
        if (_chunkUsed[i] && question.shuffledChunks[i] == chunk) {
          _chunkUsed[i] = false;
          break;
        }
      }
    });
  }

  void _clearChunks(TestQuestion question) {
    setState(() {
      _orderedChunks = [];
      _chunkUsed = List.generate(question.shuffledChunks.length, (_) => false);
    });
  }

  /// 拼写正确时触发 PASS 印章
  void _triggerPassIfCorrect() {
    // 需要延迟一帧让 state 更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final study = ref.read(studyProvider);
      if (study.lastResult?.isCorrect == true &&
          study.currentQuestion?.step == TestStep.spelling) {
        setState(() => _showPassStamp = true);
        _stampController.forward(from: 0);
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 结果卡片（内嵌在内容区）
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildResultCard(StudyState study) {
    final result = study.lastResult;
    if (result == null) return const SizedBox.shrink();

    final isCorrect = result.isCorrect;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCorrect
            ? _C.success.withOpacity(0.06)
            : _C.error.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              (isCorrect ? _C.success : _C.error).withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                isCorrect
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                color: isCorrect ? _C.success : _C.error,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isCorrect) ...[
                      Text(
                        '${result.word} = ${result.meaning}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _C.error,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '答错会重新从第一步开始',
                        style: TextStyle(
                          fontSize: 12,
                          color: _C.error.withOpacity(0.6),
                        ),
                      ),
                    ] else
                      const Text(
                        '正确',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _C.success,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _selectedOptionIndex = null;
                  _orderedChunks = [];
                  _chunkUsed = [];
                  _showPassStamp = false;
                });
                ref.read(studyProvider.notifier).nextQuestion();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isCorrect ? _C.success : _C.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                '下一题',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 完成 / 错误
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildCompleteView(StudyState study) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: _C.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.celebration_rounded,
                  size: 44, color: _C.success),
            ),
            const SizedBox(height: 24),
            const Text('学习完成！',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _C.textPrimary)),
            const SizedBox(height: 8),
            Text(
              '${study.completedWordCount} 个单词  ·  ${study.completedQuestions} 道题',
              style: const TextStyle(fontSize: 14, color: _C.textSecondary),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _C.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('返回',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: _C.error),
            const SizedBox(height: 16),
            Text(error,
                style: const TextStyle(color: _C.textSecondary),
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

enum _CS { available, selected, correct, wrong, disabled }