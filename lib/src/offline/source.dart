import 'dart:convert';
import 'package:xs/protobuf/bangumi.pb.dart';
import 'package:xs/src/apis/bangumi.dart';
import 'download_task.dart';

String decodeVodUrl(String value) {
  if (value.startsWith('https://') || value.startsWith('http://')) return value;
  return utf8.decode(base64
      .decode(base64.normalize(value.substring(0, 3) + value.substring(4))));
}

Future<String> resolveDownload(DownloadTask task) async {
  final response = await BangumiApi.getBangumiEpisodeVod(
          id: task.bangumiId, episode: task.episode)
      .timeout(const Duration(seconds: 25));
  final vod = vod_.fromBuffer((response.data as List).cast<int>());
  if (task.line >= vod.data.length) {
    throw const FormatException('所选线路已失效，请删除任务并换线路缓存');
  }
  return decodeVodUrl(vod.data[task.line].url);
}
