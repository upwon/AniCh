import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'download_task.dart';
import 'hls.dart';

typedef ResolveDownload = Future<String> Function(DownloadTask task);
typedef ResolveDanmaku = Future<List<int>?> Function(DownloadTask task);

/// One durable queue per app. Incomplete files never appear as playable media.
class DownloadManager extends ChangeNotifier {
  static final instance = DownloadManager();
  static const _notificationChannel = MethodChannel('io.github.upwon.anich.offline/downloads');
  final Dio dio;
  DownloadManager({Dio? client})
      : dio = client ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'User-Agent': 'AniCh Offline/1.1'},
            ));
  final List<DownloadTask> tasks = [];
  late Directory root;
  ResolveDownload? resolver;
  ResolveDanmaku? danmakuResolver;
  CancelToken? _token;
  Future<void>? _worker;
  DownloadTask? _active;
  bool _closed = false;
  Future<void> _saving = Future.value();
  Timer? _saveTimer;
  DateTime _lastNotificationUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool _notificationStarted = false;

  Future<void> init({Directory? directory}) async {
    root = directory ??
        Directory('${(await getApplicationSupportDirectory()).path}/offline');
    await root.create(recursive: true);
    final index = File('${root.path}/tasks.json');
    if (await index.exists()) {
      final list = jsonDecode(await index.readAsString()) as List;
      tasks.addAll(
          list.map((j) => DownloadTask.fromJson(Map<String, dynamic>.from(j))));
      for (final t in tasks) {
        if (!RegExp(r'^\d+_\d+_\d+$').hasMatch(t.key)) {
          throw const FormatException('无效缓存索引');
        }
        if (t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.queued) {
          t.status = DownloadStatus.paused;
        }
        if (t.status == DownloadStatus.complete &&
            !await File(mediaPath(t)).exists()) {
          t.status = DownloadStatus.failed;
          t.error = '本地文件已丢失，请重新缓存';
        }
        if (t.danmakuCached &&
            !await File('${folder(t)}/danmaku.pb').exists()) {
          t.danmakuCached = false;
        }
        // Older builds persisted raw transport exceptions, which could contain
        // temporary signed media URLs. Replace those messages on upgrade.
        if (t.error.contains('http://') || t.error.contains('https://')) {
          t.error =
              '线路连接中断，已保留已下载部分；点重试可续传，或更换线路。';
        }
      }
    }
    await save();
    notifyListeners();
  }

  String folder(DownloadTask t) => '${root.path}/${t.key}';
  String mediaPath(DownloadTask t) => '${folder(t)}/${t.media}';
  void changed() {
    notifyListeners();
    _updateForegroundNotification();
    if (_closed) return;
    _saveTimer ??= Timer(const Duration(milliseconds: 500), () {
      _saveTimer = null;
      unawaited(save());
    });
  }

  void _updateForegroundNotification() {
    if (!Platform.isAndroid) return;
    final pending = tasks
        .where((t) => t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.queued)
        .toList();
    if (pending.isEmpty) {
      if (_notificationStarted) {
        _notificationStarted = false;
        unawaited(_invokeNotification('stop'));
      }
      return;
    }

    final now = DateTime.now();
    final task = pending.first;
    final isActive = task.status == DownloadStatus.downloading;
    if (isActive &&
        now.difference(_lastNotificationUpdate).inMilliseconds < 1000) {
      return;
    }
    _lastNotificationUpdate = now;
    final downloaded = (task.received / (1024 * 1024)).toStringAsFixed(1);
    final total = task.total > 0
        ? ' / ${(task.total / (1024 * 1024)).toStringAsFixed(1)} MB'
        : ' MB';
    final progress = task.total > 0
        ? (task.received * 100 ~/ task.total).clamp(0, 100)
        : 0;
    _notificationStarted = true;
    unawaited(_invokeNotification('update', {
      'title': isActive ? '正在离线缓存' : '等待缓存',
      'text': '${task.title} · ${task.episodeTitle} · $downloaded$total',
      'progress': progress,
      'indeterminate': task.total <= 0,
    }));
  }

  Future<void> _invokeNotification(String method,
      [Map<String, Object?>? args]) async {
    try {
      await _notificationChannel.invokeMethod<void>(method, args);
    } on PlatformException {
      // A denied or unavailable notification must not interrupt a download.
    } on MissingPluginException {
      // Desktop builds and tests do not register the Android service channel.
    }
  }

  Future<void> save() {
    final snapshot = jsonEncode(tasks.map((t) => t.toJson()).toList());
    _saving = _saving.catchError((Object _) {}).then((_) async {
      final tmp = File('${root.path}/tasks.json.tmp');
      await tmp.writeAsString(snapshot, flush: true);
      await tmp.rename('${root.path}/tasks.json');
    });
    return _saving;
  }

  Future<bool> enqueue(DownloadTask task) async {
    if (tasks.any((t) => t.key == task.key)) return false;
    if (Platform.isAndroid) {
      // Notification permission is requested at the moment the user starts a download.
      // A denial must not prevent caching while the app remains open.
      try {
        await Permission.notification.request();
      } catch (_) {}
    }
    tasks.add(task);
    await save();
    changed();
    _pump();
    return true;
  }

  Future<bool> cacheDanmaku(DownloadTask task) async {
    if (danmakuResolver == null || task.danmakuCached) return task.danmakuCached;
    if (task.danmakuCaching) return false;
    task.danmakuCaching = true;
    changed();
    try {
      final bytes = await danmakuResolver!(task);
      if (bytes == null || bytes.isEmpty) return false;
      final target = File('${folder(task)}/danmaku.pb');
      final tmp = File('${target.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
      task.danmakuCached = true;
      await save();
      return true;
    } catch (_) {
      return false;
    } finally {
      task.danmakuCaching = false;
      changed();
    }
  }

  Future<void> resume(DownloadTask t) async {
    // A cancelled transfer must fully close its file before it can be resumed.
    if (_active == t) await _worker;
    if (!tasks.contains(t) || t.status == DownloadStatus.complete) return;
    t.status = DownloadStatus.queued;
    t.error = '';
    await save();
    changed();
    _pump();
  }

  Future<void> pause(DownloadTask t) async {
    if (t.status != DownloadStatus.queued &&
        t.status != DownloadStatus.downloading) return;
    t.status = DownloadStatus.paused;
    if (_active == t) _token?.cancel('paused');
    changed();
    await save();
  }

  Future<void> remove(DownloadTask t) async {
    await pause(t);
    if (_active == t) await _worker;
    final dir = Directory(folder(t));
    if (await dir.exists()) await dir.delete(recursive: true);
    tasks.remove(t);
    await save();
    changed();
  }

  void _pump() {
    if (_closed || _worker != null) return;
    final pending = tasks.where((t) => t.status == DownloadStatus.queued);
    if (pending.isEmpty) return;
    final task = pending.first;
    _active = task;
    _token = CancelToken();
    _worker = _run(task, _token!).whenComplete(() {
      _worker = null;
      _active = null;
      _pump();
    });
  }

  void _check(CancelToken token) {
    if (token.isCancelled) {
      throw token.cancelError!;
    }
  }

  Future<void> _run(DownloadTask t, CancelToken token) async {
    try {
      t.status = DownloadStatus.downloading;
      await save();
      changed();
      await Directory(folder(t)).create(recursive: true);
      final planFile = File('${folder(t)}/plan.json');
      if (await planFile.exists()) {
        await _hls(
            t,
            token,
            Map<String, dynamic>.from(
                jsonDecode(await planFile.readAsString())));
      } else {
        if (resolver != null) t.url = await resolver!(t);
        _check(token);
        if (t.url.isEmpty) throw const FormatException('没有可用的播放地址');
        var uri = Uri.parse(t.url);
        if (!['http', 'https'].contains(uri.scheme)) {
          throw const FormatException('不支持该播放地址');
        }
        // A small probe detects extensionless HLS without loading a video in RAM.
        final probe = await dio.get<ResponseBody>(uri.toString(),
            cancelToken: token,
            options: Options(
                responseType: ResponseType.stream,
                headers: {...t.headers, 'Range': 'bytes=0-4095'}));
        final stream = StreamIterator(probe.data!.stream);
        final sample = <int>[];
        try {
          while (sample.length < 4096 && await stream.moveNext()) {
            sample.addAll(stream.current);
            if (sample.length >= 7) break;
          }
        } finally {
          await stream.cancel();
        }
        final looksHls = utf8
            .decode(sample.take(4096).toList(), allowMalformed: true)
            .trimLeft()
            .startsWith('#EXTM3U');
        if (looksHls) {
          HlsPlan? plan;
          for (var depth = 0; depth < 5; depth++) {
            final response = await dio.get<String>(uri.toString(),
                cancelToken: token,
                options: Options(
                    responseType: ResponseType.plain, headers: t.headers));
            final text = response.data!;
            if (text.length > 4 * 1024 * 1024) {
              throw const FormatException('播放列表过大');
            }
            // Resolve relative URIs against the final redirected playlist URL.
            final base = response.realUri;
            final variant = hlsVariant(text, base);
            if (variant == null) {
              plan = localizeHls(text, base);
              break;
            }
            uri = Uri.parse(variant);
          }
          if (plan == null) throw const FormatException('播放列表嵌套层数过多');
          final json = {
            'playlist': plan.playlist,
            'resources': plan.resources.map((r) => r.toJson()).toList()
          };
          await planFile.writeAsString(jsonEncode(json), flush: true);
          await _hls(t, token, json);
        } else {
          t.media = 'video.mp4';
          await _file(t.url, File(mediaPath(t)), t, token, resume: true);
        }
      }
      // Keep video success independent from the optional danmaku API.
      await cacheDanmaku(t);
      _check(token);
      t.status = DownloadStatus.complete;
      t.error = '';
    } catch (e) {
      if (t.status != DownloadStatus.paused) {
        t.status = DownloadStatus.failed;
        t.error = _friendlyError(e);
      }
    } finally {
      await save();
      changed();
    }
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      final cause = error.error;
      final interrupted = cause is HttpException &&
          cause.message.toLowerCase().contains('connection closed');
      if (interrupted || error.type == DioExceptionType.connectionError) {
        return '线路连接中断，已保留已下载部分；点重试可续传，或更换线路。';
      }
      final status = error.response?.statusCode;
      return status == null
          ? '网络或线路错误，已保留已下载部分；点重试可续传，或更换线路。'
          : '线路返回 HTTP $status，点重试可续传，或更换线路。';
    }
    if (error is HttpException || error is SocketException) {
      return '线路连接中断，已保留已下载部分；点重试可续传，或更换线路。';
    }
    if (error is FormatException) return error.message;
    // Avoid persisting exception strings that may include signed media URLs.
    return '缓存失败，请重试或更换线路。';
  }

  Future<void> _hls(
      DownloadTask t, CancelToken token, Map<String, dynamic> plan) async {
    final resources = plan['resources'] as List;
    t.segmentsTotal = resources.length;
    t.segmentsDone = 0;
    t.received = 0;
    for (final r in resources) {
      _check(token);
      final file = File('${folder(t)}/${r['name']}');
      if (!await file.exists() || await file.length() == 0) {
        await _file(r['url'], file, t, token);
      }
      t.segmentsDone++;
      t.received += await file.length();
      changed();
    }
    t.media = 'index.m3u8';
    final tmp = File('${folder(t)}/index.m3u8.tmp');
    await tmp.writeAsString(plan['playlist'], flush: true);
    await tmp.rename(mediaPath(t));
  }

  Future<void> _file(
      String url, File target, DownloadTask task, CancelToken token,
      {bool resume = false}) async {
    if (await target.exists() && await target.length() > 0) return;
    final partial = File('${target.path}.part');
    var offset = resume && await partial.exists() ? await partial.length() : 0;
    // Without a server validator, restarting is safer than joining different videos.
    if (resume && task.validator.isEmpty) offset = 0;
    final response = await dio.get<ResponseBody>(url,
        cancelToken: token,
        options: Options(responseType: ResponseType.stream, headers: {
          ...task.headers,
          if (offset > 0) 'Range': 'bytes=$offset-',
          if (offset > 0) 'If-Range': task.validator,
        }));
    final contentType = response.headers.value('content-type') ?? '';
    if (contentType.contains('text/html') ||
        contentType.contains('application/json')) {
      await response.data!.stream.listen((_) {}).cancel();
      throw const FormatException('该线路返回了网页，无法下载视频');
    }
    if (offset > 0 && response.statusCode == 206) {
      final range = response.headers.value('content-range') ?? '';
      if (!range.startsWith('bytes $offset-')) {
        await response.data!.stream.listen((_) {}).cancel();
        throw const FormatException('服务器返回了错误的续传位置');
      }
    } else {
      offset = 0;
    }
    final size =
        int.tryParse(response.headers.value('content-length') ?? '') ?? -1;
    if (resume) {
      task.validator = response.headers.value('etag') ??
          response.headers.value('last-modified') ??
          '';
      task.received = offset;
      task.total = size >= 0 ? offset + size : 0;
      await save();
    }
    final sink =
        partial.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
    var count = 0;
    var lastNotice = DateTime.now();
    try {
      await for (final chunk in response.data!.stream) {
        _check(token);
        sink.add(chunk);
        count += chunk.length;
        if (resume) task.received = offset + count;
        if (DateTime.now().difference(lastNotice).inMilliseconds >= 250) {
          changed();
          lastNotice = DateTime.now();
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    _check(token);
    if (count == 0 || (size >= 0 && count != size)) {
      throw const FormatException('下载内容不完整，请重试');
    }
    await partial.rename(target.path);
  }

  Future<void> shutdown() async {
    _closed = true;
    _saveTimer?.cancel();
    for (final task in tasks.toList()) {
      await pause(task);
    }
    await _worker;
    await save();
    dio.close(force: true);
  }
}
