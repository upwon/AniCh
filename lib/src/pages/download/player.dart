import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xs/protobuf/danmaku.pb.dart';
import 'package:xs/src/offline/download_manager.dart';
import 'package:xs/src/offline/download_task.dart';
import 'package:xs/src/utils/color.dart';
import 'package:xs/src/widgets/danmaku_settings/storage.dart';
import 'package:xs/src/widgets/danmaku_settings/view.dart';
import 'package:xs/src/widgets/danmaku_shield/storage.dart';
import 'package:xs/src/widgets/danmaku_shield/view.dart';
import 'package:xs/src/widgets/ns_danmaku/danmaku_controller.dart';
import 'package:xs/src/widgets/ns_danmaku/danmaku_view.dart';
import 'package:xs/src/widgets/ns_danmaku/models/danmaku_item.dart';
import 'package:xs/src/widgets/ns_danmaku/models/danmaku_option.dart';
import 'package:xs/src/widgets/ns_danmaku/utils.dart';

/// Plays only local media and the danmaku protobuf saved beside that media.
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
  StreamSubscription<bool>? playingSubscription;
  StreamSubscription<String>? errorSubscription;
  DanmakuController? danmakuController;
  List<data_> danmaku = [];
  String? error;
  bool showDanmaku = true;
  bool showControls = true;
  bool fullScreen = false;
  bool longPressing = false;
  double previousRate = 1;
  Duration sliderPosition = Duration.zero;
  Duration? seekPreview;
  double gestureStartX = 0;
  Duration gestureStartPosition = Duration.zero;
  Timer? hideTimer;
  int danmakuIndex = 0;
  Duration previousPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    showDanmaku = DanmakuSettingsStorage.danmakuEnable.value;
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final path = DownloadManager.instance.mediaPath(task);
      if (!await File(path).exists()) {
        throw const FileSystemException('缓存文件已丢失，请重新下载');
      }
      final danmakuFile = File('${DownloadManager.instance.folder(task)}/danmaku.pb');
      if (await danmakuFile.exists()) {
        try {
          danmaku = danmaku_.fromBuffer(await danmakuFile.readAsBytes()).data
            ..sort((a, b) => a.time.compareTo(b.time));
        } catch (_) {
          danmaku = [];
        }
      }
      if (!mounted) return;
      errorSubscription = player.stream.error.listen((message) {
        if (mounted) setState(() => error = '播放失败：$message');
      });
      await player.open(Media(path), play: false);
      if (task.position > 0) {
        await player.seek(Duration(seconds: task.position));
      }
      previousPosition = Duration(seconds: task.position);
      danmakuIndex = _lowerBound(previousPosition.inMilliseconds / 1000);
      positionSubscription = player.stream.position.listen(_onPosition);
      playingSubscription = player.stream.playing.listen((playing) {
        if (playing) {
          danmakuController?.resume();
        } else {
          danmakuController?.pause();
        }
      });
      await WakelockPlus.enable();
      await player.play();
      _scheduleHide();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  int _lowerBound(double seconds) {
    var low = 0;
    var high = danmaku.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (danmaku[mid].time < seconds) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  void _onPosition(Duration position) {
    if (!mounted) return;
    setState(() => sliderPosition = position);
    if (position + const Duration(milliseconds: 300) < previousPosition ||
        position - previousPosition > const Duration(seconds: 2)) {
      danmakuIndex = _lowerBound(position.inMilliseconds / 1000 - .2);
    }
    previousPosition = position;
    if (!showDanmaku || danmakuController == null) return;
    final currentSeconds = position.inMilliseconds / 1000;
    final due = <DanmakuItem>[];
    while (danmakuIndex < danmaku.length &&
        danmaku[danmakuIndex].time <= currentSeconds + .05) {
      final item = danmaku[danmakuIndex++];
      if (item.time >= currentSeconds - .8 &&
          DanmakuShieldStorage.shieldCheck(item.text)) {
        due.add(DanmakuItem(
          item.text,
          color: ColorUtil.fromHex(item.color),
          time: item.time,
          type: DanmakuUtils.getPosition(item.type),
        ));
      }
    }
    if (due.isNotEmpty) danmakuController!.addItems(due);
  }

  void _scheduleHide() {
    hideTimer?.cancel();
    hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && player.state.playing && !longPressing) {
        setState(() => showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => showControls = !showControls);
    if (showControls) _scheduleHide();
  }

  Future<void> _longPressStart(LongPressStartDetails _) async {
    if (!player.state.playing) return;
    previousRate = player.state.rate;
    setState(() => longPressing = true);
    await player.setRate(2);
  }

  Future<void> _longPressEnd(LongPressEndDetails _) async {
    if (!longPressing) return;
    setState(() => longPressing = false);
    await player.setRate(previousRate);
    _scheduleHide();
  }

  Future<void> _seek(Duration position) async {
    final duration = player.state.duration;
    final target = Duration(
        milliseconds: position.inMilliseconds
            .clamp(0, duration.inMilliseconds)
            .toInt());
    danmakuIndex = _lowerBound(target.inMilliseconds / 1000);
    await player.seek(target);
  }

  void _horizontalDragStart(DragStartDetails details) {
    gestureStartX = details.globalPosition.dx;
    gestureStartPosition = player.state.position;
    seekPreview = gestureStartPosition;
  }

  void _horizontalDragUpdate(DragUpdateDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    final delta = details.globalPosition.dx - gestureStartX;
    final seekSeconds =
        player.state.duration.inSeconds * (delta / (width * 2));
    final target = (gestureStartPosition.inSeconds + seekSeconds)
        .clamp(0, player.state.duration.inSeconds)
        .toInt();
    setState(() => seekPreview = Duration(seconds: target));
  }

  Future<void> _horizontalDragEnd(DragEndDetails _) async {
    final target = seekPreview;
    seekPreview = null;
    if (target != null) await _seek(target);
    if (mounted) setState(() {});
    _scheduleHide();
  }

  Future<void> _doubleTap(TapDownDetails details) async {
    final delta = details.globalPosition.dx < MediaQuery.sizeOf(context).width / 2
        ? const Duration(seconds: -10)
        : const Duration(seconds: 10);
    await _seek(player.state.position + delta);
    if (mounted) {
      setState(() => seekPreview = player.state.position);
      Future<void>.delayed(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => seekPreview = null);
      });
    }
  }

  Future<void> _toggleFullScreen() async {
    final entering = !fullScreen;
    setState(() => fullScreen = entering);
    await SystemChrome.setPreferredOrientations(entering
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(
        entering ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  Future<void> _showDanmakuSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        minChildSize: .45,
        maxChildSize: .95,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('弹幕设置',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  DanmakuSettingsView(
                    danmakuController: danmakuController,
                    showExternalSources: false,
                    onDanmakuEnableChanged: (enabled) {
                      if (!mounted) return;
                      setState(() => showDanmaku = enabled);
                      if (enabled) {
                        danmakuIndex = _lowerBound(
                            player.state.position.inMilliseconds / 1000);
                      } else {
                        danmakuController?.clear();
                      }
                    },
                    onTapDanmakuShield: () {
                      Navigator.pop(sheetContext);
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => DraggableScrollableSheet(
                          expand: false,
                          initialChildSize: .6,
                          minChildSize: .4,
                          maxChildSize: .9,
                          builder: (context, scrollController) => Column(
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('关键词屏蔽',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600)),
                              ),
                              Expanded(
                                child: DanmakuShieldView.builddanmakuShieldView(),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    _scheduleHide();
  }

  String _time(Duration value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    return hours > 0
        ? '${two(hours)}:${two(minutes)}:${two(seconds)}'
        : '${two(minutes)}:${two(seconds)}';
  }

  @override
  void dispose() {
    task.position = player.state.position.inSeconds;
    DownloadManager.instance.changed();
    hideTimer?.cancel();
    unawaited(positionSubscription?.cancel());
    unawaited(playingSubscription?.cancel());
    unawaited(errorSubscription?.cancel());
    danmakuController?.clear();
    unawaited(player.dispose());
    unawaited(WakelockPlus.disable());
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !fullScreen,
        onPopInvoked: (didPop) {
          if (!didPop && fullScreen) _toggleFullScreen();
        },
        child: Scaffold(
        appBar: fullScreen
            ? null
            : AppBar(title: Text('第${task.episode}集 ${task.episodeTitle}')),
        body: Column(children: [
          Expanded(
            child: Center(
              child: error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24), child: Text(error!))
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggleControls,
                      onDoubleTapDown: _doubleTap,
                      onHorizontalDragStart: _horizontalDragStart,
                      onHorizontalDragUpdate: _horizontalDragUpdate,
                      onHorizontalDragEnd: _horizontalDragEnd,
                      onLongPressStart: _longPressStart,
                      onLongPressEnd: _longPressEnd,
                      child: Stack(fit: StackFit.expand, children: [
                        Video(
                          controller: video,
                          controls: (_) => const SizedBox.shrink(),
                        ),
                        if (showDanmaku && danmaku.isNotEmpty)
                          IgnorePointer(
                            child: DanmakuView(
                              option: DanmakuOption(
                                fontSize: DanmakuSettingsStorage.danmakuSize.value,
                                area: DanmakuSettingsStorage.danmakuArea.value,
                                duration: DanmakuSettingsStorage.danmakuSpeed.value,
                                opacity: DanmakuSettingsStorage.danmakuOpacity.value,
                              ),
                              createdController: (controller) {
                                danmakuController = controller;
                                if (!player.state.playing) controller.pause();
                              },
                            ),
                          ),
                        if (longPressing)
                          const Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(18))),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 10),
                                child: Text('2.0× 倍速播放',
                                    style: TextStyle(color: Colors.white)),
                              ),
                            ),
                          ),
                        if (seekPreview != null && !showControls)
                          Center(
                              child: Text(
                                  '${_time(seekPreview!)} / ${_time(player.state.duration)}',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 20))),
                        if (showControls) _controls(),
                      ]),
                    ),
            ),
          ),
          if (!fullScreen) SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.offline_pin_outlined),
                const SizedBox(width: 8),
                Expanded(child: Text('${task.title} · 离线播放')),
                Text(danmaku.isEmpty ? '无已缓存弹幕' : '${danmaku.length} 条弹幕'),
              ]),
            ),
          ),
        ]),
        ),
      );

  Widget _controls() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(.35),
        child: Column(children: [
          const Spacer(),
          Row(children: [
            IconButton(
              color: Colors.white,
              icon: Icon(player.state.playing ? Icons.pause : Icons.play_arrow),
              onPressed: () => player.state.playing ? player.pause() : player.play(),
            ),
            Text(_time(sliderPosition),
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            Expanded(
              child: Slider(
                min: 0,
                max: player.state.duration.inMilliseconds
                    .clamp(1, 1 << 31)
                    .toDouble(),
                value: sliderPosition.inMilliseconds
                    .clamp(0, player.state.duration.inMilliseconds)
                    .toDouble(),
                onChanged: (value) =>
                    setState(() => sliderPosition = Duration(milliseconds: value.toInt())),
                onChangeEnd: (value) => _seek(Duration(milliseconds: value.toInt())),
              ),
            ),
            Text(_time(player.state.duration),
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            IconButton(
              tooltip: showDanmaku ? '关闭弹幕' : '打开弹幕',
              color: Colors.white,
              icon: Icon(showDanmaku ? Icons.subtitles : Icons.subtitles_off),
              onPressed: danmaku.isEmpty
                  ? null
                  : () => setState(() {
                        showDanmaku = !showDanmaku;
                        if (showDanmaku) {
                          danmakuIndex = _lowerBound(
                              player.state.position.inMilliseconds / 1000);
                        } else {
                          danmakuController?.clear();
                        }
                      }),
            ),
            PopupMenuButton<double>(
              tooltip: '播放速度',
              initialValue: player.state.rate,
              color: const Color(0xff222222),
              onSelected: (rate) => player.setRate(rate),
              itemBuilder: (context) => [
                for (final rate in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                  PopupMenuItem(
                    value: rate,
                    child: Text('${rate}×',
                        style: const TextStyle(color: Colors.white)),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.speed, color: Colors.white),
              ),
            ),
            IconButton(
              tooltip: fullScreen ? '退出全屏' : '全屏',
              color: Colors.white,
              icon: Icon(fullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
              onPressed: _toggleFullScreen,
            ),
            IconButton(
              tooltip: '弹幕设置',
              color: Colors.white,
              icon: const Icon(Icons.tune),
              onPressed: _showDanmakuSettings,
            ),
          ]),
        ]),
      ),
    );
  }
}
