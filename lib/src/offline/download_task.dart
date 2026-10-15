enum DownloadStatus { queued, downloading, paused, failed, complete }

class DownloadTask {
  final String key;
  final int bangumiId;
  final int episode;
  final int line;
  final String title;
  final String episodeTitle;
  String url;
  final Map<String, String> headers;
  DownloadStatus status;
  String error;
  String media;
  int received;
  int total;
  int segmentsDone;
  int segmentsTotal;
  int position;
  String validator;
  bool danmakuCached;
  bool danmakuCaching;
  DownloadTask(
      {required this.bangumiId,
      required this.episode,
      required this.line,
      required this.title,
      required this.episodeTitle,
      this.url = '',
      this.headers = const {},
      this.status = DownloadStatus.queued,
      this.error = '',
      this.media = '',
      this.received = 0,
      this.total = 0,
      this.segmentsDone = 0,
      this.segmentsTotal = 0,
      this.position = 0,
      this.validator = '',
      this.danmakuCached = false,
      this.danmakuCaching = false,
      String? key})
      : key = key ?? '${bangumiId}_${episode}_$line';
  double? get progress => segmentsTotal > 0
      ? segmentsDone / segmentsTotal
      : total > 0
          ? (received / total).clamp(0, 1).toDouble()
          : null;
  Map<String, dynamic> toJson() => {
        'key': key,
        'bangumiId': bangumiId,
        'episode': episode,
        'line': line,
        'title': title,
        'episodeTitle': episodeTitle,
        'url': url,
        'headers': headers,
        'status': status.name,
        'error': error,
        'media': media,
        'received': received,
        'total': total,
        'segmentsDone': segmentsDone,
        'segmentsTotal': segmentsTotal,
        'position': position,
        'validator': validator,
        'danmakuCached': danmakuCached,
      };
  factory DownloadTask.fromJson(Map<String, dynamic> j) => DownloadTask(
        key: j['key'],
        bangumiId: j['bangumiId'],
        episode: j['episode'],
        line: j['line'],
        title: j['title'],
        episodeTitle: j['episodeTitle'],
        url: j['url'] ?? '',
        headers: Map<String, String>.from(j['headers'] ?? {}),
        status: DownloadStatus.values.byName(j['status']),
        error: j['error'] ?? '',
        media: j['media'] ?? '',
        received: j['received'] ?? 0,
        total: j['total'] ?? 0,
        segmentsDone: j['segmentsDone'] ?? 0,
        segmentsTotal: j['segmentsTotal'] ?? 0,
        position: j['position'] ?? 0,
        validator: j['validator'] ?? '',
        danmakuCached: j['danmakuCached'] ?? false,
      );
}
