/// Times of the day: a value in the time unit of the scenario (min, h, s) counted from 0:00 - shown as 08:30.
library;

class Clock {
  final String unit; // time unit of the scenario
  const Clock(this.unit);

  /// a minute in the time unit
  double get _perMinute => switch (unit) {
    'h' => 1 / 60,
    's' => 60,
    _ => 1,
  };

  /// e.g. 08:30 - past midnight with the day: 01:15 (+1)
  String format(num? v) {
    if (v == null) return '';
    final minutes = (v / _perMinute).round();
    final day = minutes ~/ 1440, rest = minutes % 1440;
    final hm = '${(rest ~/ 60).toString().padLeft(2, '0')}:${(rest % 60).toString().padLeft(2, '0')}';
    return day > 0 ? '$hm (+$day)' : hm;
  }

  /// "8:30", "08:30", "8" or "24:00" - null if it is no time of the day
  num? parse(String text) {
    final m = RegExp(r'^\s*(\d{1,2})(?:[:.](\d{2}))?\s*$').firstMatch(text);
    if (m == null) return null;
    final h = int.parse(m.group(1)!), min = int.parse(m.group(2) ?? '0');
    if (min > 59 || h > 24 || (h == 24 && min > 0)) return null;
    final v = (h * 60 + min) * _perMinute;
    return v == v.roundToDouble() ? v.round() : v;
  }

  /// a duration in hours and minutes, e.g. 7:56 h
  String duration(num v) {
    final minutes = (v / _perMinute).round();
    return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')} h';
  }
}
