import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xs/src/offline/download_manager.dart';
import 'package:xs/src/offline/download_task.dart';

/// Does not call any online API, including metadata and episode lookup.
class OfflinePlayerPage extends StatefulWidget {
  const OfflinePlayerPage({super.key});
  @override
  State<OfflinePlayerPage> createState() => _OfflinePlayerPageState();
}

class _OfflinePlayerPageState extends State<OfflinePlayerPage> {
  late final DownloadTask task = Get.arguments as DownloadTask;
  late final Player player = Player();
  late final VideoController video = VideoController(player);
  StreamSubscription<Duration>? positionSubscription;
  StreamSubscription<String>? errorSubscription;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final path = DownloadManager.instance.mediaPath(task);
      if (!await File(path).exists()) {
        throw const FileSystemException('缓存文件已丢失，请重新下载');
      }
      if (!mounted) return;
      errorSubscription = player.stream.error.listen((message) {
        if (mounted) setState(() => error = '播放失败：$message');
      });
      await player.open(Media(path), play: false);
      if (task.position > 0) {
        await player.seek(Duration(seconds: task.position));
      }
      positionSubscription = player.stream.position.listen((position) {
        if ((position.inSeconds - task.position).abs() >= 5) {
          task.position = position.inSeconds;
          DownloadManager.instance.changed();
        }
      });
      await WakelockPlus.enable();
      await player.play();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  void dispose() {
    task.position = player.state.position.inSeconds;
    DownloadManager.instance.changed();
    unawaited(positionSubscription?.cancel());
    unawaited(errorSubscription?.cancel());
    unawaited(player.dispose());
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('第${task.episode}集 ${task.episodeTitle}')),
        body: Column(children: [
          Expanded(
              child: Center(
                  child: error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(error!))
                      : Video(
                          controller: video, controls: MaterialVideoControls))),
          SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    const Icon(Icons.offline_pin_outlined),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${task.title} · 离线播放'))
                  ]))),
        ]),
      );
}
