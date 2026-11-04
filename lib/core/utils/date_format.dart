import 'package:intl/intl.dart';

abstract final class DateFmt {
  static final _time = DateFormat.jm();
  static final _day = DateFormat.MMMd();
  static final _full = DateFormat.yMMMd();
  static final _file = DateFormat('yyyyMMdd_HHmmss');

  /// "2:31 PM" today, "Oct 3" this year, "Oct 3, 2025" otherwise.
  static String relative(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return _time.format(d);
    }
    if (d.year == now.year) return _day.format(d);
    return _full.format(d);
  }

  static String forFile(DateTime d) => _file.format(d);
}
