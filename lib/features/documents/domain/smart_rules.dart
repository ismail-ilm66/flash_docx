import 'dart:convert';

import 'package:flash_dox/features/documents/domain/entities/entities.dart';

/// Smart names (round 4, feature 3): matches page-1 text against the keyword
/// table in `assets/smart_rules.json` and suggests a title and folder.
/// Pure and synchronous; runs only on text already recognised on the phone.
class SmartRules {
  SmartRules._(this._rules, this._cnic, this._ids);

  factory SmartRules.fromJson(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final ids = json['ids'] as Map<String, dynamic>;
    return SmartRules._(
      [for (final r in json['rules'] as List<dynamic>) _Rule.fromJson(r as Map<String, dynamic>)],
      RegExp(ids['cnicPattern'] as String),
      ids,
    );
  }

  final List<_Rule> _rules;
  final RegExp _cnic;
  final Map<String, dynamic> _ids;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// The suggestion for a document, or null when nothing matches (it keeps
  /// its "Flash Scan - …" name). [scannedAt] stands in when the text has no
  /// date; [pages] picks "front & back" vs a single side for cards.
  NameSuggestion? match(String text, ScanMode mode, DateTime scannedAt, {int pages = 1}) {
    final lower = text.toLowerCase();

    // IDs: the scan mode decides, or a CNIC number on a document scan.
    final hasCnic = _cnic.hasMatch(text);
    if (mode == ScanMode.photo) return _id('photo', pages);
    if (mode == ScanMode.passport) return _id('passport', pages);
    if (mode == ScanMode.idCard) return _id(hasCnic ? 'cnic' : 'idCard', pages);
    if (hasCnic) return _id('cnic', pages);

    _Rule? best;
    var bestScore = 1;
    for (final r in _rules) {
      final score = r.score(lower);
      if (score > bestScore) {
        best = r;
        bestScore = score;
      }
    }
    if (best == null) return null;

    final found = _firstDate(text, prefer: best.folder == DocFolder.bills ? 'bill month' : null);
    final date = found ?? scannedAt;
    // A result card or certificate often shows only a year.
    final year = found?.year ?? _bareYear(text) ?? scannedAt.year;
    final chapter = RegExp(r'chapter\s*[:#-]?\s*(\d{1,3}|[ivxlc]{1,6})\b', caseSensitive: false).firstMatch(text)?.group(1);
    final template = best.title.contains('{chapter}') && chapter == null ? best.fallbackTitle ?? best.title : best.title;
    final title = template
        .replaceAll('{name}', best.name)
        .replaceAll('{chapter}', chapter?.toUpperCase() ?? '')
        .replaceAll('{monthYear}', '${_months[date.month - 1]} ${date.year}')
        .replaceAll('{year}', '$year')
        .replaceAll('{date}', '${date.day.toString().padLeft(2, '0')} ${_months[date.month - 1]} ${date.year}');
    return NameSuggestion(title: title, folder: best.folder, kind: best.kind);
  }

  NameSuggestion _id(String key, int pages) {
    final m = _ids[key] as Map<String, dynamic>;
    final title = pages < 2 && m['singleTitle'] != null ? m['singleTitle'] as String : m['title'] as String;
    return NameSuggestion(title: title, folder: DocFolder.ids, kind: m['kind'] as String);
  }

  /// The first plausible date in [text] (after [prefer], when that phrase
  /// is present: a bill's "Bill month OCT 26" beats its due date).
  static DateTime? _firstDate(String text, {String? prefer}) {
    if (prefer != null) {
      final i = text.toLowerCase().indexOf(prefer);
      if (i >= 0) {
        final near = _firstDate(text.substring(i + prefer.length, (i + prefer.length + 40).clamp(0, text.length)));
        if (near != null) return near;
      }
    }
    const mon = r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?';
    final patterns = <(RegExp, DateTime? Function(RegExpMatch))>[
      // 2026-11-05
      (RegExp(r'\b(20\d{2})-(\d{1,2})-(\d{1,2})\b'), (m) => _date(m[1], m[2], m[3])),
      // 05-11-2026, 05/11/2026, 05.11.2026 (day first, as in Pakistan)
      (RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2})\b'), (m) => _date(m[3], m[2], m[1])),
      // 05 Nov 2026, 5-Nov-26
      (RegExp('\\b(\\d{1,2})[- ]$mon[-, ]+(\\d{4}|\\d{2})\\b', caseSensitive: false), (m) => _date(m[3], _mon(m[2]), m[1])),
      // Nov 2026, OCT-26, Oct '26
      (RegExp("\\b$mon[-,' ]+(\\d{4}|\\d{2})\\b", caseSensitive: false), (m) => _date(m[2], _mon(m[1]), '1')),
    ];
    (int, DateTime)? first;
    for (final (re, build) in patterns) {
      for (final m in re.allMatches(text)) {
        final d = build(m);
        if (d != null && (first == null || m.start < first.$1)) first = (m.start, d);
        if (d != null) break;
      }
    }
    return first?.$2;
  }

  static int? _bareYear(String text) {
    final m = RegExp(r'(?<![\d-/.])(20\d{2})(?![\d-/.])').firstMatch(text);
    return m == null ? null : int.parse(m[1]!);
  }

  static String _mon(String? s) => '${_months.indexWhere((m) => m.toLowerCase() == s!.toLowerCase().substring(0, 3)) + 1}';

  static DateTime? _date(String? y, String? m, String? d) {
    var year = int.tryParse(y ?? '');
    final month = int.tryParse(m ?? '');
    final day = int.tryParse(d ?? '');
    if (year == null || month == null || day == null) return null;
    if (year < 100) year += 2000;
    if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }
}

class _Rule {
  _Rule({
    required this.folder,
    required this.name,
    required this.kind,
    required this.title,
    required this.keywords,
    required this.hints,
    this.fallbackTitle,
  });

  factory _Rule.fromJson(Map<String, dynamic> j) => _Rule(
        folder: DocFolder.values.byName(j['folder'] as String),
        name: j['name'] as String,
        kind: j['kind'] as String,
        title: j['title'] as String,
        fallbackTitle: j['fallbackTitle'] as String?,
        keywords: [for (final k in j['keywords'] as List<dynamic>) _word(k as String)],
        hints: [for (final k in (j['hints'] as List<dynamic>?) ?? const []) _word(k as String)],
      );

  final DocFolder folder;
  final String name;
  final String kind;
  final String title;
  final String? fallbackTitle;
  final List<RegExp> keywords;
  final List<RegExp> hints;

  /// Whole words / phrases only: "total" mustn't match "totally".
  static RegExp _word(String k) => RegExp('(?<![a-z0-9])${RegExp.escape(k.toLowerCase())}(?![a-z0-9])');

  int score(String lower) =>
      keywords.where((k) => k.hasMatch(lower)).length * 2 + hints.where((h) => h.hasMatch(lower)).length;
}
