import 'dart:convert';
import 'package:xs/protobuf/bangumi.pb.dart';
import 'package:xs/src/apis/bangumi.dart';
import 'download_task.dart';

vod_ parseVodResponse(dynamic payload) {
  final bytes = switch (payload) {
    List<int> value => value,
    String value => utf8.encode(value),
    _ => throw const FormatException('播放线路响应格式不正确'),
  };

  final first = bytes.indexWhere(
      (byte) => byte != 0x20 && byte != 0x0a && byte != 0x0d && byte != 0x09);
  if (first >= 0 && bytes[first] == 0x5b) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! List ||
        decoded.any((value) => value is! int || value < 0 || value > 255)) {
      throw const FormatException('播放线路响应中的字节数据不正确');
    }
    return vod_.fromBuffer(decoded.cast<int>());
  }
  if (first >= 0 && bytes[first] == 0x7b) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map && decoded['error'] == true) {
      throw FormatException(decoded['message']?.toString() ?? '播放线路接口返回错误');
    }
  }

  return vod_.fromBuffer(bytes);
}

String decodeVodUrl(String value) {
  if (value.startsWith('https://') || value.startsWith('http://')) return value;
  return utf8.decode(base64
      .decode(base64.normalize(value.substring(0, 3) + value.substring(4))));
}

Future<String> resolveDownload(DownloadTask task) async {
  final response = await BangumiApi.getBangumiEpisodeVod(
          id: task.bangumiId, episode: task.episode)
      .timeout(const Duration(seconds: 25));
  final vod = parseVodResponse(response.data);
  if (task.line >= vod.data.length) {
    throw const FormatException('所选线路已失效，请删除任务并换线路缓存');
  }
  return decodeVodUrl(vod.data[task.line].url);
}
