import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xs/protobuf/bangumi.pb.dart';
import 'package:xs/src/offline/source.dart';

void main() {
  final encoded = vod_()
    ..data.add(vod_item_(url: 'https://media.example/video.m3u8', sort: 1));

  test('parses raw protobuf response bytes', () {
    final result = parseVodResponse(encoded.writeToBuffer());
    expect(result.data.single.url, 'https://media.example/video.m3u8');
  });

  test('parses protobuf bytes wrapped in a JSON integer array', () {
    final result = parseVodResponse(jsonEncode(encoded.writeToBuffer()));
    expect(result.data.single.url, 'https://media.example/video.m3u8');
  });

  test('rejects JSON error objects instead of treating them as media data', () {
    expect(() => parseVodResponse('{"error":true}'), throwsFormatException);
  });
}
