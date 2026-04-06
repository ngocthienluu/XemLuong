import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'salary_service.dart';

/// Lưu trữ lịch sử lương vào SharedPreferences
class SalaryStorage {
  static const String _historyKey = 'salary_history';
  static const String _lastUidKey = 'last_processed_uid';

  /// Lưu 1 record mới
  Future<void> saveSalaryRecord(SalaryRecord record) async {
    final history = await loadHistory();
    
    // Kiểm tra tháng đã có chưa
    final existingIndex = history.indexWhere(
      (r) => r.salaryMonth == record.salaryMonth,
    );

    if (existingIndex >= 0) {
      history[existingIndex] = record;
    } else {
      history.insert(0, record);
    }

    // Hàm helper để so sánh
    int compareMonths(String ma, String mb) {
      int getYear(String m) {
        final match = RegExp(r'(\d{4})').firstMatch(m);
        return match != null ? int.parse(match.group(1)!) : 0;
      }
      int getMonth(String m) {
        final match = RegExp(r'(\d{1,2})').firstMatch(m);
        return match != null ? int.parse(match.group(1)!) : 0;
      }
      final yComp = getYear(mb).compareTo(getYear(ma));
      if (yComp != 0) return yComp;
      return getMonth(mb).compareTo(getMonth(ma));
    }

    history.sort((a, b) => compareMonths(a.salaryMonth, b.salaryMonth));

    // Lưu tối đa 24 tháng
    if (history.length > 24) {
      history.removeRange(24, history.length);
    }

    await _saveHistory(history);

    // Cập nhật UID mới nhất
    if (record.mailUid != null) {
      await _saveLastUid(record.mailUid!);
    }
  }

  /// Lưu nhiều records cùng lúc
  Future<void> saveSalaryRecords(List<SalaryRecord> records) async {
    if (records.isEmpty) return;
    
    final history = await loadHistory();
    
    for (final record in records) {
      final existingIndex = history.indexWhere(
        (r) => r.salaryMonth == record.salaryMonth,
      );
      if (existingIndex >= 0) {
        history[existingIndex] = record;
      } else {
        history.add(record);
      }
    }

    // Hàm helper để so sánh
    int compareMonths(String ma, String mb) {
      int getYear(String m) {
        final match = RegExp(r'(\d{4})').firstMatch(m);
        return match != null ? int.parse(match.group(1)!) : 0;
      }
      int getMonth(String m) {
        final match = RegExp(r'(\d{1,2})').firstMatch(m);
        return match != null ? int.parse(match.group(1)!) : 0;
      }
      final yComp = getYear(mb).compareTo(getYear(ma));
      if (yComp != 0) return yComp;
      return getMonth(mb).compareTo(getMonth(ma));
    }

    history.sort((a, b) => compareMonths(a.salaryMonth, b.salaryMonth));
    if (history.length > 24) {
      history.removeRange(24, history.length);
    }

    await _saveHistory(history);

    // Cập nhật UID mới nhất
    final maxUid = records
        .where((r) => r.mailUid != null)
        .fold<int>(0, (max, r) => r.mailUid! > max ? r.mailUid! : max);
    if (maxUid > 0) {
      final currentUid = await getLastProcessedUid();
      if (currentUid == null || maxUid > currentUid) {
        await _saveLastUid(maxUid);
      }
    }
  }

  /// Load toàn bộ lịch sử
  Future<List<SalaryRecord>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(raw);
      return jsonList
          .map((e) => SalaryRecord.fromMap(Map<String, String>.from(e)))
          .toList();
    } catch (e) {
      print('[SalaryStorage] Error loading history: $e');
      return [];
    }
  }

  /// Load record mới nhất
  Future<SalaryRecord?> loadLatest() async {
    final history = await loadHistory();
    return history.isNotEmpty ? history.first : null;
  }

  /// Lấy UID mail đã xử lý cuối cùng
  Future<int?> getLastProcessedUid() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastUidKey);
  }

  Future<void> _saveHistory(List<SalaryRecord> history) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = history.map((r) => r.toMap()).toList();
    await prefs.setString(_historyKey, jsonEncode(jsonList));
  }

  Future<void> _saveLastUid(int uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastUidKey, uid);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    await prefs.remove(_lastUidKey);
  }
}
