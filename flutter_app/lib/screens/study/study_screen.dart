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
  // 拼写题状态
  List<String> _selectedLetters = [];
  List<bool> _letterUsed = [];
  int? _selectedOptionIndex;
  bool _isAnimating = false;

  @override
  Widget build(BuildContext context) {
    final study = ref.watch(studyProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${study.completedWordCount} / ${study.totalWords} 单词'
          '  ·  ${study.completedQuestions} / ${study.totalQuestions} 题',
          style: const TextStyle(fontSize: 14),
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
              : study.isComplete
                  ? _buildCompleteView(study)
                  : study.currentQuestion != null
                      ? _buildQuestionView(study)
                      : _buildCompleteView(study),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 题目视图（根据步骤分发）
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildQuestionView(StudyState study) {
    final question = study.currentQuestion!;

    return Column(
      children: [
        // 步骤指示器
        _buildStepIndicator(question.step),

        // 题目区域
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 16),
                // 题干
                _buildQuestionCard(question),
                const SizedBox(height: 24),

                // 选项区域（选择题）或 拼写区域
                if (question.step == TestStep.spelling)
                  _buildSpellingArea(question, study)
                else
                  _buildChoiceOptions(question, study),
              ],
            ),
          ),
        ),

        // 底部：结果反馈 + 下一题按钮
        if (study.isShowingResult) _buildResultFooter(study),
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
            // 提示文字
            Text(
              isEnToCn
                  ? '请选择该单词的中文释义'
                  : isCnToEn
                      ? '请选择对应的英文单词'
                      : '请拼写出该单词',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textHint,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),

            // 主题干
            if (isEnToCn || isSpelling) ...[
              // 显示英文单词
              Text(
                isSpelling ? question.meaning : question.word,
                style: TextStyle(
                  fontSize: isSpelling ? 20 : 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: isSpelling ? 0 : -0.5,
                ),
                textAlign: TextAlign.center,
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
              if (isSpelling) ...[
                const SizedBox(height: 16),
                // 拼写提示
                Text(
                  question.spellingHint ?? '',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 4,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ] else ...[
              // 汉选英：显示中文
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
  // 选择题选项
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
            // 正确答案始终高亮绿色（不管用户是否选了它）
            bgColor = AppColors.success.withOpacity(0.1);
            borderColor = AppColors.success;
            textColor = AppColors.success;
            icon = Icons.check_circle_rounded;
          } else if (isSelected && !isCorrect) {
            // 用户选错的选项标红
            bgColor = AppColors.error.withOpacity(0.1);
            borderColor = AppColors.error;
            textColor = AppColors.error;
            icon = Icons.cancel_rounded;
          } else {
            // 其他未选中的错误选项变灰
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Row(
                  children: [
                    // 序号
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
                                String.fromCharCode(65 + index), // A, B, C, D
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: textColor,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        option.text,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: textColor,
                        ),
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

    // 短暂延迟后自动提交
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
  // 拼写区域
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSpellingArea(TestQuestion question, StudyState study) {
    // 初始化字母使用状态
    if (_letterUsed.length != question.scrambledLetters.length) {
      _letterUsed =
          List.generate(question.scrambledLetters.length, (_) => false);
      _selectedLetters = [];
    }

    return Column(
      children: [
        // 已选字母显示区（输入框效果）
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: study.isShowingResult
                  ? (study.lastResult?.isCorrect == true
                      ? AppColors.success
                      : AppColors.error)
                  : AppColors.primary.withOpacity(0.5),
              width: 2,
            ),
          ),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (int i = 0; i < _selectedLetters.length; i++)
                GestureDetector(
                  onTap: study.isShowingResult
                      ? null
                      : () => _removeLetterAt(i, question),
                  child: Container(
                    width: 36,
                    height: 40,
                    decoration: BoxDecoration(
                      color: study.isShowingResult
                          ? (study.lastResult?.isCorrect == true
                              ? AppColors.success.withOpacity(0.15)
                              : AppColors.error.withOpacity(0.15))
                          : AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        _selectedLetters[i],
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: study.isShowingResult
                              ? (study.lastResult?.isCorrect == true
                                  ? AppColors.success
                                  : AppColors.error)
                              : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              // 光标占位
              if (!study.isShowingResult && _selectedLetters.length < question.word.length)
                Container(
                  width: 36,
                  height: 40,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: AppColors.primary.withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 可选字母
        if (!study.isShowingResult)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: List.generate(question.scrambledLetters.length, (index) {
              final letter = question.scrambledLetters[index];
              final isUsed = _letterUsed[index];

              return GestureDetector(
                onTap: isUsed ? null : () => _selectLetter(index, question),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isUsed ? 0.3 : 1.0,
                  child: Container(
                    width: 44,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isUsed
                          ? AppColors.divider
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
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
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Center(
                      child: Text(
                        letter.toLowerCase(),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: isUsed
                              ? AppColors.textHint
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),

        const SizedBox(height: 16),

        // 操作按钮
        if (!study.isShowingResult)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 退格按钮
              OutlinedButton.icon(
                onPressed: _selectedLetters.isEmpty
                    ? null
                    : () => _removeLastLetter(question),
                icon: const Icon(Icons.backspace_outlined, size: 18),
                label: const Text('退格'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              // 清空按钮
              OutlinedButton.icon(
                onPressed: _selectedLetters.isEmpty
                    ? null
                    : () => _clearLetters(question),
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('清空'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              // 提交按钮
              ElevatedButton.icon(
                onPressed: _selectedLetters.isEmpty
                    ? null
                    : () {
                        final answer = _selectedLetters.join();
                        ref
                            .read(studyProvider.notifier)
                            .submitSpellingAnswer(answer);
                      },
                icon: const Icon(Icons.check, size: 18),
                label: const Text('确认'),
              ),
            ],
          ),
      ],
    );
  }

  void _selectLetter(int index, TestQuestion question) {
    setState(() {
      _selectedLetters.add(question.scrambledLetters[index]);
      _letterUsed[index] = true;
    });
  }

  void _removeLetterAt(int selectedIdx, TestQuestion question) {
    final letter = _selectedLetters[selectedIdx];
    setState(() {
      _selectedLetters.removeAt(selectedIdx);
      // 找到第一个匹配的已使用字母并恢复
      for (int i = 0; i < question.scrambledLetters.length; i++) {
        if (_letterUsed[i] &&
            question.scrambledLetters[i] == letter) {
          _letterUsed[i] = false;
          break;
        }
      }
    });
  }

  void _removeLastLetter(TestQuestion question) {
    if (_selectedLetters.isNotEmpty) {
      _removeLetterAt(_selectedLetters.length - 1, question);
    }
  }

  void _clearLetters(TestQuestion question) {
    setState(() {
      _selectedLetters = [];
      _letterUsed =
          List.generate(question.scrambledLetters.length, (_) => false);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 结果反馈 + 下一题按钮
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildResultFooter(StudyState study) {
    final result = study.lastResult;
    if (result == null) return const SizedBox.shrink();

    final isCorrect = result.isCorrect;

    return SafeArea(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isCorrect
              ? AppColors.success.withOpacity(0.08)
              : AppColors.error.withOpacity(0.08),
          border: Border(
            top: BorderSide(
              color: isCorrect
                  ? AppColors.success.withOpacity(0.3)
                  : AppColors.error.withOpacity(0.3),
            ),
          ),
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
              ],
            ),
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
                  ref.read(studyProvider.notifier).nextQuestion();
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
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 完成视图
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
