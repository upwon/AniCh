import 'package:get_storage/get_storage.dart';
import 'package:xs/src/pages/search/models/search_type.dart';

class SearchHistoryStorage {
  static const int maxItems = 20;
  static final GetStorage _box = GetStorage();

  static String _key(SearchType type) => 'search_history_${type.name}';

  static List<String> load(SearchType type) {
    final value = _box.read(_key(type));
    if (value is! List) return [];
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(maxItems)
        .toList();
  }

  static List<String> addQuery(List<String> current, String query) {
    final normalized = query.trim();
    if (normalized.isEmpty) return current.take(maxItems).toList();
    return [
      normalized,
      ...current.where((item) => item.trim() != normalized),
    ].take(maxItems).toList();
  }

  static List<String> add(SearchType type, String query) {
    final updated = addQuery(load(type), query);
    _box.write(_key(type), updated);
    return updated;
  }

  static List<String> remove(SearchType type, String query) {
    final updated = load(type)..remove(query);
    _box.write(_key(type), updated);
    return updated;
  }

  static void clear(SearchType type) => _box.remove(_key(type));
}
