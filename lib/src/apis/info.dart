import 'dart:io';

import 'package:dio/dio.dart';
import 'package:xs/src/config.dart';

final api = Dio(BaseOptions(
    // baseUrl: AppConfig.baseUrl,
    headers: {HttpHeaders.userAgentHeader: AppConfig.ua}));

class InfoApi {
  // 最新
  static Future<Response> checkUpdate() async {
    const url = 'https://api.github.com/repos/upwon/AniCh/releases/latest';
    final response =
        await api.get(url, options: Options(responseType: ResponseType.json));
    // Release titles are descriptive; tag_name is the version used for updates.
    final tag = response.data['tag_name'];
    if (tag is String) {
      response.data['name'] = tag.replaceFirst(RegExp(r'^v'), '');
    }
    return response;
  }
}
