import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 国产 ROM 后台引导是否已弹过（SharedPreferences 键）。
const kAlarmVendorGuideKey = 'alarm_vendor_guide_shown';

/// 闹钟所需权限申请 + 国产 ROM 后台弹窗引导。
class AlarmPermissions {
  AlarmPermissions._();

  /// 申请通知、音频读取与精确闹钟权限；被永久拒绝时引导去设置。
  ///
  /// 权限通道不可用（如测试环境）时静默返回，不阻塞闹钟功能。
  static Future<void> ensure(BuildContext context) async {
    try {
      await Permission.notification.request();
      await Permission.audio.request();
      final exact = await Permission.scheduleExactAlarm.request();
      if (!context.mounted) return;
      if (exact.isPermanentlyDenied) {
        final go = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('需要「闹钟和提醒」权限'),
            content: const Text('系统限制了精确闹钟，闹钟可能延迟甚至不响。请在设置里允许「闹钟和提醒」。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('以后再说'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('去设置'),
              ),
            ],
          ),
        );
        if (go == true) await openAppSettings();
      }
    } on MissingPluginException {
      // 测试环境 / 插件缺失：忽略
    } on PlatformException {
      // ROM 定制通道异常：忽略
    }
  }

  /// 首次进入闹钟页时的国产 ROM 后台引导（只弹一次）。
  ///
  /// 小米/Redmi（HyperOS）、OPPO、vivo 等默认限制后台，不放开
  /// 自启动与后台弹出界面时，闹钟到点可能拉不起响铃页。
  static Future<void> showVendorGuideOnce(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(kAlarmVendorGuideKey) ?? false) return;
      await prefs.setBool(kAlarmVendorGuideKey, true);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('让闹钟准点响的小提示'),
          content: const Text(
            '国产系统（小米/Redmi、OPPO、vivo 等）默认限制后台。'
            '请到系统设置里为「XNL 工具箱」打开：\n\n'
            '· 自启动\n'
            '· 后台弹出界面\n'
            '· 省电策略选「无限制」\n\n'
            '这样闹钟才能在锁屏下准时响起。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (_) {
      // 持久化或弹窗失败不影响闹钟功能
    }
  }
}
