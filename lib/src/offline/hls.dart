/// A frozen VOD playlist: every URI is replaced by a local relative file.
class HlsResource {
  final String url;
  final String name;
  const HlsResource(this.url, this.name);
  Map<String, dynamic> toJson() => {'url': url, 'name': name};
}

class HlsPlan {
  final String playlist;
  final List<HlsResource> resources;
  const HlsPlan(this.playlist, this.resources);
}

String? hlsVariant(String text, Uri base) {
  final lines = text.split('\n').map((e) => e.trim()).toList();
  if (!lines.any((e) => e.startsWith('#EXT-X-STREAM-INF:'))) return null;
  if (lines.any((e) =>
      e.startsWith('#EXT-X-MEDIA:') &&
      e.contains('TYPE=AUDIO') &&
      e.contains('URI='))) {
    throw const FormatException('该线路使用独立音轨，请切换其他线路缓存');
  }
  int bandwidth = -1;
  String? selected;
  for (var i = 0; i < lines.length - 1; i++) {
    if (!lines[i].startsWith('#EXT-X-STREAM-INF:')) continue;
    final b = int.tryParse(RegExp(r'(?:^|,)BANDWIDTH=(\d+)')
                .firstMatch(lines[i].split(':').skip(1).join(':'))
                ?.group(1) ??
            '') ??
        0;
    final next = lines.skip(i + 1).firstWhere(
        (e) => e.isNotEmpty && !e.startsWith('#'),
        orElse: () => '');
    if (next.isNotEmpty && b > bandwidth) {
      bandwidth = b;
      selected = base.resolve(next).toString();
    }
  }
  if (selected == null) throw const FormatException('播放列表没有可下载的画质');
  return selected;
}

HlsPlan localizeHls(String text, Uri base) {
  if (!text.trimLeft().startsWith('#EXTM3U')) {
    throw const FormatException('无效的 M3U8 播放列表');
  }
  if (!text.contains('#EXT-X-ENDLIST')) {
    throw const FormatException('直播或未结束的播放列表暂不支持离线缓存');
  }
  final resources = <HlsResource>[];
  final names = <String, String>{};
  String local(String reference, {bool key = false, bool init = false}) {
    final uri = base.resolve(reference);
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException('不支持该资源地址');
    }
    return names.putIfAbsent(uri.toString(), () {
      final originalExt = RegExp(r'\.[a-zA-Z0-9]{1,5}$')
          .firstMatch(uri.path)
          ?.group(0)
          ?.toLowerCase();
      const mediaExtensions = {'.ts', '.mp4', '.m4s', '.aac', '.m4a', '.mp3'};
      // Local HLS readers apply their media extension allowlist to keys too.
      // Use accepted suffixes without relaxing the decoder security allowlist.
      final ext = key
          ? '.ts'
          : init
              ? '.mp4'
              : mediaExtensions.contains(originalExt)
                  ? originalExt!
                  : '.ts';
      final name = 'part_${resources.length}$ext';
      resources.add(HlsResource(uri.toString(), name));
      return name;
    });
  }

  final output = <String>[];
  for (final raw in text.split('\n')) {
    var line = raw.trim();
    if (line.startsWith('#EXT-X-KEY:') ||
        line.startsWith('#EXT-X-SESSION-KEY:')) {
      final method = RegExp(r'METHOD=([^,]+)').firstMatch(line)?.group(1);
      if (method != 'NONE' && method != 'AES-128') {
        throw const FormatException('该加密格式暂不支持离线缓存，请换线路');
      }
      if (line.contains('KEYFORMAT=') &&
          !line.contains('KEYFORMAT="identity"')) {
        throw const FormatException('该线路使用 DRM，无法缓存');
      }
    }
    if (line.startsWith('#')) {
      if (line.contains('URI=')) {
        if (!line.startsWith('#EXT-X-KEY:') &&
            !line.startsWith('#EXT-X-MAP:')) {
          throw const FormatException('该播放列表格式暂不支持缓存，请换线路');
        }
        line = line.replaceAllMapped(
            RegExp(r'URI="([^"]+)"'),
            (m) =>
                'URI="${local(m.group(1)!, key: line.startsWith('#EXT-X-KEY:'), init: line.startsWith('#EXT-X-MAP:'))}"');
        if (RegExp(r'URI="https?://').hasMatch(line)) {
          throw const FormatException('存在无法本地化的资源');
        }
      }
    } else if (line.isNotEmpty) {
      line = local(line);
    }
    output.add(line);
  }
  if (resources.isEmpty) throw const FormatException('播放列表没有视频分片');
  return HlsPlan(output.join('\n'), resources);
}
