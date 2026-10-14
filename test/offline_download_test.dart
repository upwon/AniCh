import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xs/src/offline/download_manager.dart';
import 'package:xs/src/offline/download_task.dart';
import 'package:xs/src/offline/hls.dart';

Future<void> waitFor(bool Function() condition) async {
  for (var i = 0; i < 500; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Download did not reach expected state');
}

DownloadTask task(String url, {int episode = 1}) => DownloadTask(
    bangumiId: 10,
    episode: episode,
    line: 0,
    title: '测试番剧',
    episodeTitle: '测试',
    url: url);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'HLS localizes encrypted keys, fMP4 init, repeated byte ranges and query URLs',
      () {
    final plan = localizeHls('''#EXTM3U
#EXT-X-KEY:METHOD=AES-128,URI="../key?k=1",IV=0x0001
#EXT-X-MAP:URI="init.mp4"
#EXTINF:1,
#EXT-X-BYTERANGE:4@0
video.ts?token=1
#EXTINF:1,
#EXT-X-BYTERANGE:4@4
video.ts?token=1
#EXT-X-ENDLIST''', Uri.parse('https://example.com/a/index.m3u8'));
    expect(plan.resources.length, 3);
    expect(plan.resources.first.url, 'https://example.com/key?k=1');
    expect(plan.playlist, isNot(contains('https://')));
    expect(plan.playlist, contains('IV=0x0001'));
    expect(plan.playlist, contains('#EXT-X-BYTERANGE:4@4'));
    expect(plan.playlist, isNot(contains('token=1')));
  });
  test('master chooses highest bandwidth and rejects separate external audio',
      () {
    expect(
        hlsVariant(
            '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100\na.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=200\nb.m3u8',
            Uri.parse('https://a.test/master')),
        'https://a.test/b.m3u8');
    expect(
        () => hlsVariant(
            '#EXT-X-MEDIA:TYPE=AUDIO,URI="audio.m3u8"\n#EXT-X-STREAM-INF:BANDWIDTH=100\na.m3u8',
            Uri.parse('https://a.test/master')),
        throwsFormatException);
    expect(
        () => localizeHls(
            '#EXTM3U\n#EXTINF:1\na.ts', Uri.parse('https://a.test/v')),
        throwsFormatException);
    expect(
        () => localizeHls(
            '#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI="k"\na.ts\n#EXT-X-ENDLIST',
            Uri.parse('https://a.test/v')),
        throwsFormatException);
  });

  late HttpServer server;
  late Directory dir;
  late DownloadManager manager;
  late String base;
  var segmentCalls = 0;
  var rangeCalls = 0;
  final video = List<int>.generate(128 * 1024, (i) => i % 251);
  setUp(() async {
    segmentCalls = 0;
    rangeCalls = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((r) async {
      final path = r.uri.path;
      if (path == '/bad') {
        r.response.statusCode = 403;
        await r.response.close();
        return;
      }
      if (path == '/html') {
        r.response.headers.contentType = ContentType.html;
        r.response.write('<html>error</html>');
        await r.response.close();
        return;
      }
      if (path == '/hls' || path == '/master') {
        r.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl');
        r.response.write(path == '/master'
            ? '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100\nhls'
            : '#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\nseg.ts\n#EXT-X-ENDLIST');
        await r.response.close();
        return;
      }
      if (path == '/seg.ts') {
        segmentCalls++;
        r.response.add([1, 2, 3, 4]);
        await r.response.close();
        return;
      }
      var offset = 0;
      var end = video.length - 1;
      r.response.headers.set('etag', '"video1"');
      final range = r.headers.value('range');
      if (range != null) {
        final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
        offset = int.parse(match.group(1)!);
        if (match.group(2)!.isNotEmpty)
          end = int.parse(match.group(2)!).clamp(offset, end);
        r.response.statusCode = 206;
        r.response.headers
            .set('content-range', 'bytes $offset-$end/${video.length}');
        if (offset > 0) rangeCalls++;
      }
      r.response.contentLength = end - offset + 1;
      try {
        for (var i = offset; i <= end; i += 4096) {
          r.response.add(video.sublist(i, (i + 4096).clamp(0, end + 1)));
          await r.response.flush();
          if (path == '/slow')
            await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      } catch (_) {
      } finally {
        await r.response.close();
      }
    });
    dir = await Directory.systemTemp.createTemp('anich-test');
    manager = DownloadManager();
    await manager.init(directory: dir);
  });
  tearDown(() async {
    await manager.shutdown();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });
  test(
      'downloads direct media, persists metadata, plays without a server and deletes',
      () async {
    final t = task('$base/video');
    expect(await manager.enqueue(t), true);
    expect(await manager.enqueue(task('$base/video')), false);
    await waitFor(() => t.status == DownloadStatus.complete);
    expect(await File(manager.mediaPath(t)).readAsBytes(), video);
    await manager.save();
    final restored = DownloadManager();
    await restored.init(directory: dir);
    expect(restored.tasks.single.status, DownloadStatus.complete);
    await server.close(force: true);
    expect(await File(restored.mediaPath(restored.tasks.single)).readAsBytes(),
        video);
    await restored.remove(restored.tasks.single);
    expect(restored.tasks, isEmpty);
    await restored.shutdown();
  });
  test('downloads extensionless nested HLS and every local resource', () async {
    final t = task('$base/master');
    await manager.enqueue(t);
    await waitFor(() => t.status == DownloadStatus.complete);
    expect(t.media, 'index.m3u8');
    final playlist = await File(manager.mediaPath(t)).readAsString();
    expect(playlist, contains('part_0.ts'));
    expect(playlist, isNot(contains(base)));
    expect(await File('${manager.folder(t)}/part_0.ts').readAsBytes(),
        [1, 2, 3, 4]);
    expect(segmentCalls, 1);
  });
  test('pause, validated byte-range resume and queue continue', () async {
    final t = task('$base/slow');
    await manager.enqueue(t);
    await waitFor(() => t.received > 0);
    await manager.pause(t);
    expect(t.status, DownloadStatus.paused);
    await manager.resume(t);
    await waitFor(() => t.status == DownloadStatus.complete);
    expect(await File(manager.mediaPath(t)).readAsBytes(), video);
    expect(rangeCalls, greaterThan(0));
  });
  test(
      'failed downloads are never marked complete and do not block the next task',
      () async {
    final bad = task('$base/bad');
    final good = task('$base/video', episode: 2);
    await manager.enqueue(bad);
    await manager.enqueue(good);
    await waitFor(() => good.status == DownloadStatus.complete);
    expect(bad.status, DownloadStatus.failed);
    expect(bad.error, contains('403'));
  });
  test('HTML responses fail instead of creating playable files', () async {
    final t = task('$base/html');
    await manager.enqueue(t);
    await waitFor(() => t.status == DownloadStatus.failed);
    expect(await File(manager.mediaPath(t)).exists(), false);
  });
  test('interrupted jobs restore paused, not automatically downloading',
      () async {
    await File('${dir.path}/tasks.json').writeAsString(jsonEncode(
        [(task('$base/slow')..status = DownloadStatus.downloading).toJson()]));
    final restored = DownloadManager();
    await restored.init(directory: dir);
    expect(restored.tasks.single.status, DownloadStatus.paused);
    await restored.shutdown();
  });
}
