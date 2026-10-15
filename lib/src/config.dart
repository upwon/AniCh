import 'dart:io';

import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';

late PackageInfo packageInfo;

class AppConfig {
  static RxString version = ''.obs;
  static RxString ua = ''.obs;
  // This host is shipped as a working API endpoint in the official AniCh app.
  // The old api.emmmm.eu.org endpoint currently fails TLS for API requests.
  static const baseUrl = 'https://anich.sends.eu.org';
  static const bilibiliApiProxyUrl = 'https://bili-dm.emmmm.eu.org';
  static const qqVideoApiUrl = 'https://dm.video.qq.com';

  static init() async {
    packageInfo = await PackageInfo.fromPlatform();
    version(packageInfo.version);
    String platform = '';
    if (Platform.isAndroid) {
      platform = 'Android';
    } else if (Platform.isIOS) {
      platform = 'IOS';
    } else if (Platform.isFuchsia) {
      platform = 'Fuchsia';
    } else if (Platform.isLinux) {
      platform = 'Linux';
    } else if (Platform.isMacOS) {
      platform = 'MacOS';
    } else if (Platform.isWindows) {
      platform = 'Windows';
    }

    ua('${packageInfo.packageName} $platform ${packageInfo.version}');
  }
}
