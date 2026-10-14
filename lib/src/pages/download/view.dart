import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:xs/src/offline/download_manager.dart';
import 'package:xs/src/offline/download_task.dart';

String formatBytes(int bytes) => bytes >= 1024 * 1024 * 1024
    ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

class DownloadPage extends StatelessWidget {
  const DownloadPage({super.key});
  @override
  Widget build(BuildContext context) {
    final manager = DownloadManager.instance;
    return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
              title: const Text('离线缓存'),
              bottom: const TabBar(tabs: [
                Tab(text: '正在缓存'),
                Tab(text: '已缓存'),
              ])),
          body: AnimatedBuilder(
              animation: manager,
              builder: (context, _) => Column(
                    children: [
                      Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            Expanded(
                                child: Text(
                                    '${manager.tasks.length} 个任务 · 已下载 ${formatBytes(manager.tasks.fold<int>(0, (n, t) => n + t.received))}')),
                            TextButton(
                                onPressed: () async {
                                  for (final t in manager.tasks.toList()) {
                                    await manager.pause(t);
                                  }
                                },
                                child: const Text('全部暂停')),
                          ])),
                      Expanded(
                          child: TabBarView(children: [
                        _list(
                            context,
                            manager.tasks
                                .where(
                                    (t) => t.status != DownloadStatus.complete)
                                .toList()),
                        _list(
                            context,
                            manager.tasks
                                .where(
                                    (t) => t.status == DownloadStatus.complete)
                                .toList()),
                      ])),
                    ],
                  )),
        ));
  }

  Widget _list(BuildContext context, List<DownloadTask> tasks) {
    if (tasks.isEmpty)
      return const Center(
          child: Text('暂无缓存\n在播放页点击“缓存”选择剧集', textAlign: TextAlign.center));
    final groups = <int, List<DownloadTask>>{};
    for (final t in tasks) {
      groups.putIfAbsent(t.bangumiId, () => []).add(t);
    }
    return ListView(
        padding: const EdgeInsets.all(12),
        children: groups.values
            .map((group) => Card(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(group.first.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium)),
                            ...group.map((t) => _item(context, t)),
                          ])),
                ))
            .toList());
  }

  Widget _item(BuildContext context, DownloadTask t) {
    final manager = DownloadManager.instance;
    final complete = t.status == DownloadStatus.complete;
    final active = t.status == DownloadStatus.queued ||
        t.status == DownloadStatus.downloading;
    final labels = {
      DownloadStatus.queued: '等待缓存',
      DownloadStatus.downloading: '正在缓存',
      DownloadStatus.paused: '已暂停',
      DownloadStatus.failed: '缓存失败',
      DownloadStatus.complete: '已缓存',
    };
    return ListTile(
      onTap:
          complete ? () => Get.toNamed('/offline_player', arguments: t) : null,
      leading: Icon(
          complete ? Icons.play_circle : Icons.download_for_offline_outlined),
      title: Text('第${t.episode}集 ${t.episodeTitle}'),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            '${labels[t.status]} · 线路${t.line + 1} · ${formatBytes(t.received)}'),
        if (t.segmentsTotal > 0)
          Text('分片 ${t.segmentsDone}/${t.segmentsTotal}'),
        if (t.status == DownloadStatus.failed)
          Text(t.error,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (!complete)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                  value: t.progress ?? (active ? null : 0))),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!complete)
          IconButton(
              tooltip: active ? '暂停' : '继续／重试',
              onPressed: () => active ? manager.pause(t) : manager.resume(t),
              icon: Icon(active ? Icons.pause : Icons.play_arrow)),
        IconButton(
            tooltip: '删除缓存',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final yes = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                        title: const Text('删除这集缓存？'),
                        content: const Text('本地视频与未完成的下载文件都会删除。'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消')),
                          TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('删除'))
                        ],
                      ));
              if (yes == true) await manager.remove(t);
            }),
      ]),
    );
  }
}
