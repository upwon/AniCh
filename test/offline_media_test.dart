import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xs/src/offline/download_manager.dart';
import 'package:xs/src/offline/download_task.dart';

void main() {
  test('AES-128 HLS downloads then fully decodes with network disabled',
      () async {
    final dir = await Directory.systemTemp.createTemp('anich-real-media');
    final remote = await Directory('${dir.path}/remote').create();
    final local = await Directory('${dir.path}/local').create();
    await File('${remote.path}/key').writeAsBytes(List.generate(16, (i) => i));
    await File('${remote.path}/keyinfo').writeAsString(
        'key\n${remote.path}/key\n00000000000000000000000000000001\n');
    final fixture = await Process.run('ffmpeg', [
      '-hide_banner',
      '-loglevel',
      'error',
      '-f',
      'lavfi',
      '-i',
      'testsrc=size=64x64:rate=5',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440',
      '-t',
      '2',
      '-threads',
      '1',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-f',
      'hls',
      '-hls_time',
      '1',
      '-hls_key_info_file',
      '${remote.path}/keyinfo',
      '-hls_segment_filename',
      '${remote.path}/seg%02d.ts',
      '${remote.path}/index.m3u8',
    ]);
    expect(fixture.exitCode, 0, reason: fixture.stderr.toString());
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final name = request.uri.path.split('/').last;
      final file = File('${remote.path}/$name');
      if (await file.exists()) {
        request.response.add(await file.readAsBytes());
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    final manager = DownloadManager();
    await manager.init(directory: local);
    final task = DownloadTask(
        bangumiId: 1,
        episode: 1,
        line: 0,
        title: 'fixture',
        episodeTitle: 'encrypted HLS',
        url: 'http://127.0.0.1:${server.port}/index.m3u8');
    try {
      await manager.enqueue(task);
      for (var i = 0;
          i < 500 &&
              task.status != DownloadStatus.complete &&
              task.status != DownloadStatus.failed;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(task.status, DownloadStatus.complete, reason: task.error);
      await server.close(force: true);
      // Explicit allowlist excludes http/https/tcp; decoding cannot reach a server.
      final decoded = await Process.run('ffmpeg', [
        '-hide_banner',
        '-loglevel',
        'error',
        '-protocol_whitelist',
        'file,crypto,data',
        '-i',
        manager.mediaPath(task),
        '-f',
        'null',
        '-',
      ]);
      expect(decoded.exitCode, 0, reason: decoded.stderr.toString());
    } finally {
      await manager.shutdown();
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  });
}
