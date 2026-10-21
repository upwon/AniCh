import 'package:flutter_test/flutter_test.dart';
import 'package:xs/src/pages/search_panel/search_history_storage.dart';

void main() {
  group('SearchHistoryStorage.addQuery', () {
    test('moves a repeated query to the front and trims whitespace', () {
      final result = SearchHistoryStorage.addQuery(
        ['鬼灭之刃', '星际牛仔', '葬送的芙莉莲'],
        '  星际牛仔  ',
      );

      expect(result, ['星际牛仔', '鬼灭之刃', '葬送的芙莉莲']);
    });

    test('ignores blank queries and limits history to 20 entries', () {
      final current = List.generate(21, (index) => 'query-$index');

      expect(SearchHistoryStorage.addQuery(current, '   '), current.take(20));
      expect(
        SearchHistoryStorage.addQuery(current, 'new-query'),
        ['new-query', ...current.take(19)],
      );
    });
  });
}
