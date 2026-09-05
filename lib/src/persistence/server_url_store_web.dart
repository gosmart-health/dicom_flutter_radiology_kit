import 'dart:convert';
import 'package:web/web.dart' as web;

/// Web implementation of [DicomServerUrlStore] using browser's localStorage via package:web.
class DicomServerUrlStore {
  static const int maxHistory = 5;
  static const String defaultUrl = 'http://localhost:8000';
  static const String _historyKey = 'dicom_server_root_history';
  static const String _lastUsedKey = 'dicom_server_root_last_used';

  // In-memory fallback if localStorage throws (e.g. security exception or disabled)
  static List<String>? _memoryHistory;
  static String? _memoryLastUsed;

  /// Retrieves the history of up to 5 DICOMWeb server root URLs.
  /// If empty, defaults to a list containing [defaultFallback].
  static List<String> getHistory({String defaultFallback = defaultUrl}) {
    try {
      final raw = web.window.localStorage.getItem(_historyKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = json.decode(raw);
        if (decoded is List) {
          final list = decoded
              .map((e) => e?.toString().trim() ?? '')
              .where((e) => e.isNotEmpty)
              .take(maxHistory)
              .toList();
          if (list.isNotEmpty) {
            _memoryHistory = list;
            return List<String>.unmodifiable(list);
          }
        }
      }
    } catch (_) {
      // Fall back to in-memory state
    }

    if (_memoryHistory != null && _memoryHistory!.isNotEmpty) {
      return List<String>.unmodifiable(_memoryHistory!);
    }

    return List<String>.unmodifiable([defaultFallback]);
  }

  /// Retrieves the last used server root URL, or the first entry from history,
  /// or [defaultFallback] if none exists.
  static String getLastUsedUrl({String defaultFallback = defaultUrl}) {
    try {
      final last = web.window.localStorage.getItem(_lastUsedKey);
      if (last != null && last.trim().isNotEmpty) {
        _memoryLastUsed = last.trim();
        return _memoryLastUsed!;
      }
    } catch (_) {
      // Fall back to in-memory state
    }

    if (_memoryLastUsed != null && _memoryLastUsed!.trim().isNotEmpty) {
      return _memoryLastUsed!.trim();
    }

    final history = getHistory(defaultFallback: defaultFallback);
    return history.isNotEmpty ? history.first : defaultFallback;
  }

  static List<String> _loadPersistedHistory() {
    if (_memoryHistory != null) return _memoryHistory!;
    try {
      final raw = web.window.localStorage.getItem(_historyKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = json.decode(raw);
        if (decoded is List) {
          final list = decoded
              .map((e) => e?.toString().trim() ?? '')
              .where((e) => e.isNotEmpty)
              .take(maxHistory)
              .toList();
          if (list.isNotEmpty) {
            _memoryHistory = list;
            return list;
          }
        }
      }
    } catch (_) {
      // Fall back to memory
    }
    return [];
  }

  /// Records a used server root URL into history.
  /// Trims whitespace, deduplicates, moves to top (index 0), caps at [maxHistory],
  /// and updates the last used selection in browser persistence.
  static void recordUrl(String url) {
    final clean = url.trim();
    if (clean.isEmpty) return;

    final current = List<String>.from(_loadPersistedHistory());
    current.removeWhere((item) => item.toLowerCase() == clean.toLowerCase());
    current.insert(0, clean);

    final trimmed = current.take(maxHistory).toList();
    _memoryHistory = trimmed;
    _memoryLastUsed = clean;

    try {
      web.window.localStorage.setItem(_historyKey, json.encode(trimmed));
      web.window.localStorage.setItem(_lastUsedKey, clean);
    } catch (_) {
      // Graceful fallback if localStorage writes fail
    }
  }

  /// Updates the last used server root URL.
  static void setLastUsedUrl(String url) {
    recordUrl(url);
  }

  /// Clears persisted and in-memory history.
  static void clear() {
    _memoryHistory = null;
    _memoryLastUsed = null;
    try {
      web.window.localStorage.removeItem(_historyKey);
      web.window.localStorage.removeItem(_lastUsedKey);
    } catch (_) {
      // Ignore
    }
  }
}
