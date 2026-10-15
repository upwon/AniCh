import 'package:xs/protobuf/danmaku.pb.dart';
import 'package:xs/src/apis/bangumi.dart';
import 'download_task.dart';

/// Fetches AniCh's aggregated episode comments as one local protobuf file.
/// Null means the API failed or returned no usable comments.
Future<List<int>?> fetchEpisodeDanmaku(DownloadTask task) async {
  const pageSize = 3000;
  const maxComments = 60000;
  final merged = danmaku_();
  var skip = 0;

  while (skip < maxComments) {
    final response = await BangumiApi.getDanmaku(
        id: task.bangumiId, episode: task.episode, skip: skip);
    if (response.statusCode != 200 || response.data is! List<int>) return null;

    final page = danmaku_.fromBuffer(response.data as List<int>);
    if (page.data.isEmpty) break;
    merged.data.addAll(page.data);
    skip += page.data.length;
    if (page.data.length < pageSize) break;
  }

  if (merged.data.isEmpty) return null;
  return merged.writeToBuffer();
}
