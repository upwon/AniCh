import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:xs/protobuf/bangumi.pb.dart';
import 'package:xs/src/pages/bangumi_detail/models/bangumi_detail_model.dart';
import 'download_manager.dart';
import 'download_task.dart';

Future<void> showDownloadSelection(
  BuildContext context, {
  required int id,
  required BangumiDetailModel data,
  required List<bangumi_episodes_data_> episodes,
  required int initialEpisode,
  required int initialLine,
  required List<vod_item_> lines,
}) async {
  if (lines.isEmpty) {
    SmartDialog.showToast('请先等待播放线路加载');
    return;
  }
  final available = episodes.where((e) => e.status).toList();
  if (available.isEmpty) {
    SmartDialog.showToast('暂无可缓存的剧集');
    return;
  }
  final selected = <int>{
    available.any((e) => e.sort == initialEpisode)
        ? initialEpisode
        : available.first.sort
  };
  var line = initialLine.clamp(0, lines.length - 1).toInt();
  final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
          builder: (context, setState) => SizedBox(
                height: MediaQuery.of(context).size.height * .7,
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('缓存选集',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            value: line,
                            decoration:
                                const InputDecoration(labelText: '缓存线路'),
                            items: List.generate(
                                lines.length,
                                (i) => DropdownMenuItem(
                                    value: i,
                                    child: Text(
                                        '线路${i + 1} ${lines[i].caption}'))),
                            onChanged: (i) => setState(() => line = i!),
                          ),
                          Row(children: [
                            TextButton(
                                onPressed: () => setState(() {
                                      selected.clear();
                                      selected
                                          .addAll(available.map((e) => e.sort));
                                    }),
                                child: const Text('全选')),
                            TextButton(
                                onPressed: () => setState(selected.clear),
                                child: const Text('清空')),
                            const Spacer(),
                            Text('已选 ${selected.length} 集'),
                          ]),
                          Expanded(
                              child: ListView(
                                  children: available
                                      .map((e) => CheckboxListTile(
                                            contentPadding: EdgeInsets.zero,
                                            value: selected.contains(e.sort),
                                            title:
                                                Text('第${e.sort}集 ${e.title}'),
                                            onChanged: (v) => setState(() => v!
                                                ? selected.add(e.sort)
                                                : selected.remove(e.sort)),
                                          ))
                                      .toList())),
                          const Text('任务按顺序下载。下载时请保持 App 运行；重启后可继续未完成任务。',
                              style: TextStyle(fontSize: 12)),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                              onPressed: selected.isEmpty
                                  ? null
                                  : () => Navigator.pop(context, true),
                              icon: const Icon(Icons.download),
                              label: Text('开始缓存 ${selected.length} 集')),
                        ])),
              )));
  if (confirmed != true) return;
  var count = 0;
  for (final e in available.where((e) => selected.contains(e.sort))) {
    if (await DownloadManager.instance.enqueue(DownloadTask(
      bangumiId: id,
      episode: e.sort,
      line: line,
      title: data.title ?? '番剧',
      episodeTitle: e.title,
    ))) count++;
  }
  SmartDialog.showToast(count > 0 ? '已添加 $count 集到离线缓存' : '所选剧集已在缓存列表中');
}
