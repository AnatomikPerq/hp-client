import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/core/tools/platform.dart';

final class NotificationService {
  static final NotificationService _singleton = NotificationService._internal();

  factory NotificationService() => _singleton;

  NotificationService._internal();

  //==========================
  final _localNotification = FlutterLocalNotificationsPlugin();

  Future<void> asyncInit() async {
    const initializationSettingsAndroid = AndroidInitializationSettings(
      'ic_launcher',
    );
    const initializationSettingsDarwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
    );
    final initializationSettingsLinux = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );
    final WindowsInitializationSettings initializationSettingsWindows =
        WindowsInitializationSettings(
          appName: 'HYPER CLIENT',
          appUserModelId: 'AnatomikPerq.HyperClient',
          // The installer's AppId, so toasts belong to this App and not to
          // an upstream installation on the same machine.
          guid: '346eafc3-85a2-4bbe-9f2b-5ee624666817',
        );
    final initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
      linux: initializationSettingsLinux,
      windows: initializationSettingsWindows,
    );
    await _localNotification.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onReceiveNotification,
    );

    if (AppPlatform.isAndroid) {
      await _localNotification
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
  }

  Future<void> _onReceiveNotification(
    NotificationResponse notificationResponse,
  ) async {
    final payload = notificationResponse.payload;
    if (payload != null) {
      ygLogger(payload);
    }
  }

  Future<void> pushNotification(String message) async {
    if (AppPlatform.isIOS) {
      await _localNotification
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true);
    } else if (AppPlatform.isMacOS) {
      await _localNotification
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true);
    }

    if (AppPlatform.isAndroid) {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'net.yuandev.onexray',
          'HYPER CLIENT',
          channelDescription: 'HYPER CLIENT',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          ticker: 'HYPER CLIENT',
        ),
      );
      await _localNotification.show(
        id: 0,
        title: message,
        notificationDetails: details,
      );
      return;
    }
    await _localNotification.show(id: 0, title: message);
  }
}
