/// VM / Non-browser fallback for [DicomServerUrlStore].
class DicomServerUrlStore {
  static const int maxHistory = 5;
  static const String defaultUrl = 'http://localhost:8000';

  static List<String>? _memoryHistory;
  static String? _memoryLastUsed;

  /// Retrieves the history of up to 5 DICOMWeb server root URLs.
  /// If empty, defaults to a list containing [defaultFallback].
  static List<String> getHistory({String defaultFallback = defaultUrl}) {
    if (_memoryHistory != null && _memoryHistory!.isNotEmpty) {
      return List<String>.unmodifiable(_memoryHistory!);
    }
    return List<String>.unmodifiable([defaultFallback]);
  }

  /// Retrieves the last used server root URL, or the first entry from history,
  /// or [defaultFallback] if none exists.
  static String getLastUsedUrl({String defaultFallback = defaultUrl}) {
    if (_memoryLastUsed != null && _memoryLastUsed!.trim().isNotEmpty) {
      return _memoryLastUsed!.trim();
    }
    final history = getHistory(defaultFallback: defaultFallback);
    return history.isNotEmpty ? history.first : defaultFallback;
  }

  /// Records a used server root URL into history.
  /// Trims whitespace, deduplicates, moves to top (index 0), caps at [maxHistory],
  /// and updates the last used selection.
  static void recordUrl(String url) {
    final clean = url.trim();
    if (clean.isEmpty) return;

    final current = List<String>.from(_memoryHistory ?? []);
    current.removeWhere((item) => item.toLowerCase() == clean.toLowerCase());
    current.insert(0, clean);

    _memoryHistory = current.take(maxHistory).toList();
    _memoryLastUsed = clean;
  }

  /// Updates the last used server root URL.
  static void setLastUsedUrl(String url) {
    recordUrl(url);
  }

  /// Clears in-memory history (useful for test resets).
  static void clear() {
    _memoryHistory = null;
    _memoryLastUsed = null;
  }
}
