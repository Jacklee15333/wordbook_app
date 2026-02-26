import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

class StudyState {
  final bool isLoading;
  final List<Map<String, dynamic>> newWords;
  final List<Map<String, dynamic>> reviewWords;
  final int currentIndex;
  final bool isShowingAnswer;
  final int streakDays;
  final int totalNew;
  final int totalReview;
  final int completedCount;
  final String? error;

  const StudyState({
    this.isLoading = true,
    this.newWords = const [],
    this.reviewWords = const [],
    this.currentIndex = 0,
    this.isShowingAnswer = false,
    this.streakDays = 0,
    this.totalNew = 0,
    this.totalReview = 0,
    this.completedCount = 0,
    this.error,
  });

  List<Map<String, dynamic>> get allCards => [...reviewWords, ...newWords];
  Map<String, dynamic>? get currentCard =>
      currentIndex < allCards.length ? allCards[currentIndex] : null;
  bool get isComplete => currentIndex >= allCards.length;
  int get totalCards => allCards.length;
  double get progressPercent =>
      totalCards > 0 ? completedCount / totalCards : 0;

  StudyState copyWith({
    bool? isLoading,
    List<Map<String, dynamic>>? newWords,
    List<Map<String, dynamic>>? reviewWords,
    int? currentIndex,
    bool? isShowingAnswer,
    int? streakDays,
    int? totalNew,
    int? totalReview,
    int? completedCount,
    String? error,
  }) {
    return StudyState(
      isLoading: isLoading ?? this.isLoading,
      newWords: newWords ?? this.newWords,
      reviewWords: reviewWords ?? this.reviewWords,
      currentIndex: currentIndex ?? this.currentIndex,
      isShowingAnswer: isShowingAnswer ?? this.isShowingAnswer,
      streakDays: streakDays ?? this.streakDays,
      totalNew: totalNew ?? this.totalNew,
      totalReview: totalReview ?? this.totalReview,
      completedCount: completedCount ?? this.completedCount,
      error: error,
    );
  }
}

class StudyNotifier extends StateNotifier<StudyState> {
  final ApiService _api;
  String? _wordbookId;

  StudyNotifier(this._api) : super(const StudyState());

  Future<void> loadTodayTask(String wordbookId) async {
    _wordbookId = wordbookId;
    state = const StudyState(isLoading: true);

    try {
      final data = await _api.getTodayTask(wordbookId);
      state = StudyState(
        isLoading: false,
        newWords: List<Map<String, dynamic>>.from(data['new_words'] ?? []),
        reviewWords: List<Map<String, dynamic>>.from(data['review_words'] ?? []),
        streakDays: data['streak_days'] ?? 0,
        totalNew: data['new_count'] ?? 0,
        totalReview: data['review_count'] ?? 0,
      );
    } catch (e) {
      state = StudyState(
        isLoading: false,
        error: 'Failed to load tasks: ${_extractError(e)}',
      );
    }
  }

  void showAnswer() {
    state = state.copyWith(isShowingAnswer: true);
  }

  Future<void> rateWord(int rating) async {
    final card = state.currentCard;
    if (card == null || _wordbookId == null) return;

    final wordId = card['word']['id'];

    try {
      await _api.submitReview(
        wordId: wordId,
        rating: rating,
        wordbookId: _wordbookId!,
        reviewedAt: DateTime.now(),
      );
    } catch (e) {
      // TODO: save to offline queue
    }

    state = state.copyWith(
      currentIndex: state.currentIndex + 1,
      isShowingAnswer: false,
      completedCount: state.completedCount + 1,
    );
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
