/// ===========================================================
/// Flutter 前端修改 - 新版导入对话框
/// ===========================================================
/// 文件: lib/widgets/import_words_dialog_v2.dart
/// 
/// 这是一个全新的导入对话框 Widget，替代原有的导入对话框。
/// 功能：提交导入 → 显示处理进度 → 展示结果摘要
/// ===========================================================

import 'dart:async';
import 'package:flutter/material.dart';
// import 'package:your_app/services/api_service.dart';  // 根据你项目实际路径调整

class ImportWordsDialogV2 extends StatefulWidget {
  final String wordbookId;
  final List<String> words;

  const ImportWordsDialogV2({
    Key? key,
    required this.wordbookId,
    required this.words,
  }) : super(key: key);

  @override
  State<ImportWordsDialogV2> createState() => _ImportWordsDialogV2State();
}

class _ImportWordsDialogV2State extends State<ImportWordsDialogV2> {
  // 状态: idle -> submitting -> processing -> completed -> error
  String _status = 'idle';
  String? _taskId;
  String? _errorMessage;
  Timer? _pollTimer;

  // 进度数据
  int _totalWords = 0;
  int _matchedCount = 0;
  int _aiGeneratedCount = 0;
  int _aiFailedCount = 0;
  double _progress = 0;

  // 结果数据
  List<dynamic> _matchedItems = [];
  List<dynamic> _generatedItems = [];
  List<dynamic> _failedItems = [];

  @override
  void initState() {
    super.initState();
    _submitImport();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// 提交导入任务
  Future<void> _submitImport() async {
    setState(() => _status = 'submitting');

    try {
      // TODO: 使用你项目的 ApiService 实例
      // final result = await apiService.importWordsV2(widget.wordbookId, widget.words);
      // _taskId = result['task_id'];
      // _totalWords = result['total_words'];

      // === 模拟，替换为实际API调用 ===
      // final result = await ApiService.instance.importWordsV2(widget.wordbookId, widget.words);
      // _taskId = result['task_id'];
      // _totalWords = result['total_words'];
      
      setState(() {
        _status = 'processing';
        // _totalWords = result['total_words'];
      });

      _startPolling();
    } catch (e) {
      setState(() {
        _status = 'error';
        _errorMessage = e.toString();
      });
    }
  }

  /// 开始轮询进度
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_taskId == null) return;

      try {
        // TODO: 替换为实际API调用
        // final progress = await apiService.getImportProgress(_taskId!);
        // setState(() {
        //   _matchedCount = progress['matched_count'];
        //   _aiGeneratedCount = progress['ai_generated_count'];
        //   _aiFailedCount = progress['ai_failed_count'];
        //   _progress = (progress['progress'] as num).toDouble();
        //   if (progress['status'] == 'completed' || progress['status'] == 'failed') {
        //     _status = progress['status'];
        //     timer.cancel();
        //     if (progress['status'] == 'completed') _loadResults();
        //   }
        // });
      } catch (e) {
        debugPrint('Poll error: $e');
      }
    });
  }

  /// 加载最终结果
  Future<void> _loadResults() async {
    if (_taskId == null) return;

    try {
      // TODO: 替换为实际API调用
      // final results = await apiService.getImportResults(_taskId!);
      // setState(() {
      //   _matchedItems = results['matched'] ?? [];
      //   _generatedItems = results['generated'] ?? [];
      //   _failedItems = results['failed'] ?? [];
      // });
    } catch (e) {
      debugPrint('Load results error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            _buildHeader(),
            const Divider(height: 1),
            // Content
            Flexible(child: _buildContent()),
            // Footer
            const Divider(height: 1),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    String title;
    switch (_status) {
      case 'submitting':
        title = '正在提交...';
        break;
      case 'processing':
        title = '处理中...';
        break;
      case 'completed':
        title = '导入完成';
        break;
      case 'error':
        title = '导入失败';
        break;
      default:
        title = '导入单词';
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(
            _status == 'completed'
                ? Icons.check_circle
                : _status == 'error'
                    ? Icons.error
                    : Icons.import_export,
            color: _status == 'completed'
                ? Colors.green
                : _status == 'error'
                    ? Colors.red
                    : Colors.blue,
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_status) {
      case 'submitting':
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在提交导入任务...'),
              ],
            ),
          ),
        );

      case 'processing':
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 8,
                  backgroundColor: Colors.grey[200],
                ),
              ),
              const SizedBox(height: 12),
              Text('${_progress.toStringAsFixed(0)}% 完成',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              // 统计
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatChip('总数', _totalWords, Colors.grey),
                  _buildStatChip('匹配', _matchedCount, Colors.green),
                  _buildStatChip('生成', _aiGeneratedCount, Colors.orange),
                  _buildStatChip('失败', _aiFailedCount, Colors.red),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '正在后台处理，请耐心等待...\n词库匹配的单词会自动导入，AI生成的需要管理员审核后入库。',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );

      case 'completed':
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 统计摘要
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatChip('总数', _totalWords, Colors.grey),
                    _buildStatChip('匹配导入', _matchedCount, Colors.green),
                    _buildStatChip('待审核', _aiGeneratedCount, Colors.orange),
                    _buildStatChip('失败', _aiFailedCount, Colors.red),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (_matchedCount > 0) ...[
                Text(
                  '✅ ${_matchedCount} 个单词已从词库匹配并自动导入',
                  style: TextStyle(fontSize: 14, color: Colors.green[700]),
                ),
                const SizedBox(height: 8),
              ],

              if (_aiGeneratedCount > 0) ...[
                Text(
                  '🤖 ${_aiGeneratedCount} 个单词由AI/词典生成，等待管理员在后台审核入库',
                  style: TextStyle(fontSize: 14, color: Colors.orange[700]),
                ),
                const SizedBox(height: 8),
              ],

              if (_aiFailedCount > 0) ...[
                Text(
                  '❌ ${_aiFailedCount} 个单词生成失败',
                  style: TextStyle(fontSize: 14, color: Colors.red[700]),
                ),
              ],
            ],
          ),
        );

      case 'error':
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('导入失败: ${_errorMessage ?? "未知错误"}',
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        );

      default:
        return const SizedBox();
    }
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_status == 'completed' || _status == 'error')
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          if (_status == 'processing')
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('后台继续处理'),
            ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}


/// ===========================================================
/// 使用方式（在词书详情页调用）：
/// ===========================================================
/// 
/// // 替换原来的导入逻辑：
/// showDialog(
///   context: context,
///   barrierDismissible: false,
///   builder: (context) => ImportWordsDialogV2(
///     wordbookId: wordbook.id,
///     words: parsedWordList,
///   ),
/// );
