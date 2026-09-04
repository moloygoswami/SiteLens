import 'package:intl/intl.dart';

enum TimezoneMode {
  utc('UTC'),
  local('Local');

  final String label;
  const TimezoneMode(this.label);
}

enum TimeFormatStyle {
  twentyFourHour('24-Hour (14:30:00)'),
  twelveHour('12-Hour (02:30:00 PM)'),
  iso8601('ISO-8601 (T14:30:00Z)');

  final String label;
  const TimeFormatStyle(this.label);
}

class TimestampDisplaySettings {
  final TimezoneMode timezoneMode;
  final TimeFormatStyle formatStyle;

  const TimestampDisplaySettings({
    this.timezoneMode = TimezoneMode.utc,
    this.formatStyle = TimeFormatStyle.twentyFourHour,
  });

  String format(DateTime? utcDateTime) {
    if (utcDateTime == null) return '—';

    final targetDateTime = timezoneMode == TimezoneMode.local
        ? utcDateTime.toLocal()
        : utcDateTime.toUtc();

    final tzSuffix = timezoneMode == TimezoneMode.local
        ? targetDateTime.timeZoneName
        : 'UTC';

    switch (formatStyle) {
      case TimeFormatStyle.twentyFourHour:
        final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(targetDateTime);
        return '$dateStr $tzSuffix';
      case TimeFormatStyle.twelveHour:
        final dateStr = DateFormat('yyyy-MM-dd hh:mm:ss a').format(targetDateTime);
        return '$dateStr $tzSuffix';
      case TimeFormatStyle.iso8601:
        if (timezoneMode == TimezoneMode.utc) {
          return targetDateTime.toIso8601String();
        } else {
          return targetDateTime.toIso8601String();
        }
    }
  }

  TimestampDisplaySettings copyWith({
    TimezoneMode? timezoneMode,
    TimeFormatStyle? formatStyle,
  }) {
    return TimestampDisplaySettings(
      timezoneMode: timezoneMode ?? this.timezoneMode,
      formatStyle: formatStyle ?? this.formatStyle,
    );
  }
}
