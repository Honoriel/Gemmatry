import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

/// Service for managing local notifications, especially for background math solving completion
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    print('Initializing NotificationService...');

    // Android initialization settings
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Combined initialization settings
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // Initialize the plugin
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Request permissions for iOS
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _requestIOSPermissions();
    }

    _isInitialized = true;
    print('NotificationService initialized successfully');
  }

  /// Request iOS notification permissions
  Future<void> _requestIOSPermissions() async {
    await _notifications
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  /// Handle notification tap events
  void _onNotificationTapped(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
    // TODO: Navigate to the solved problem details screen
    // This could be implemented to open the specific problem that was solved
  }

  /// Show notification when math problem solving is completed
  Future<void> showSolvingCompletedNotification({
    required String problemTitle,
    required String answer,
    String? problemId,
  }) async {
    if (!_isInitialized) {
      print('NotificationService not initialized, skipping notification');
      return;
    }

    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'math_solver_channel',
        'Math Solver Notifications',
        channelDescription: 'Notifications for completed math problem solving',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        styleInformation: BigTextStyleInformation(''),
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Create notification content
      final String title = '🎉 Math Problem Solved!';
      final String body = 'Problem: ${_truncateText(problemTitle, 50)}\nAnswer: ${_truncateText(answer, 100)}';

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000), // Unique ID
        title,
        body,
        details,
        payload: problemId, // Can be used to navigate to specific problem
      );

      print('Solving completion notification sent successfully');
    } catch (e) {
      print('Error showing solving completion notification: $e');
    }
  }

  /// Show notification when math problem solving fails
  Future<void> showSolvingFailedNotification({
    required String problemTitle,
    required String errorMessage,
    String? problemId,
  }) async {
    if (!_isInitialized) {
      print('NotificationService not initialized, skipping notification');
      return;
    }

    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'math_solver_channel',
        'Math Solver Notifications',
        channelDescription: 'Notifications for completed math problem solving',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Create notification content
      final String title = '❌ Math Solving Failed';
      final String body = 'Problem: ${_truncateText(problemTitle, 50)}\nError: ${_truncateText(errorMessage, 100)}';

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000), // Unique ID
        title,
        body,
        details,
        payload: problemId,
      );

      print('Solving failure notification sent successfully');
    } catch (e) {
      print('Error showing solving failure notification: $e');
    }
  }

  /// Show progress notification for long-running solving tasks
  Future<void> showSolvingProgressNotification({
    required String problemTitle,
    required String status,
    String? problemId,
  }) async {
    if (!_isInitialized) return;

    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'math_solver_progress_channel',
        'Math Solver Progress',
        channelDescription: 'Progress notifications for math problem solving',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        icon: '@mipmap/ic_launcher',
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: false,
        presentSound: false,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        999, // Fixed ID for progress notifications
        '🧮 Solving Math Problem...',
        '${_truncateText(problemTitle, 50)}\nStatus: $status',
        details,
        payload: problemId,
      );
    } catch (e) {
      print('Error showing progress notification: $e');
    }
  }

  /// Cancel progress notification
  Future<void> cancelProgressNotification() async {
    try {
      await _notifications.cancel(999); // Cancel progress notification
    } catch (e) {
      print('Error canceling progress notification: $e');
    }
  }

  /// Truncate text to specified length with ellipsis
  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }

  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    if (!_isInitialized) return false;
    
    if (defaultTargetPlatform == TargetPlatform.android) {
      final bool? enabled = await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
      return enabled ?? false;
    }
    
    return true; // Assume enabled for other platforms
  }

  /// Request notification permissions (mainly for Android 13+)
  Future<bool> requestNotificationPermissions() async {
    if (!_isInitialized) return false;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      
      final bool? granted = await androidImplementation?.requestNotificationsPermission();
      return granted ?? false;
    }
    
    return true; // Assume granted for other platforms
  }
}
