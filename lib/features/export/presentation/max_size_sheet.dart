import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/utils/bytes.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The preset limits (decimal units, like upload forms).
const maxSizePresets = <int?>[null, 1000000, 500000, 200000];

/// Smallest custom limit; below this even one page is unreadable.
const _minCustomKb = 50;

/// "No limit" / "Under 500 KB".
String maxSizeLabel(BuildContext context, int? bytes) =>
    bytes == null ? context.l10n.maxSizeNoLimit : context.l10n.maxSizeUnder(formatBytes(bytes));

/// Max file size (artboard *Max file size*). Returns the chosen limit
/// (`bytes: null` = no limit), or null when dismissed.
Future<({int? bytes})?> showMaxSizeSheet(BuildContext context, int? current) {
  return AppBottomSheet.show<({int? bytes})>(context, builder: (_) => _MaxSizeSheet(current: current));
}

class _MaxSizeSheet extends StatefulWidget {
  const _MaxSizeSheet({required this.current});
  final int? current;

  @override
  State<_MaxSizeSheet> createState() => _MaxSizeSheetState();
}

class _MaxSizeSheetState extends State<_MaxSizeSheet> {
  late int? _selected = widget.current;
  late final _custom = TextEditingController(
    text: maxSizePresets.contains(widget.current) ? '' : '${widget.current! ~/ 1000}',
  );

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  int? get _customBytes {
    final kb = int.tryParse(_custom.text);
    return kb == null || kb < _minCustomKb ? null : kb * 1000;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final customOn = !maxSizePresets.contains(_selected);
    final canFinish = !customOn || _customBytes != null;
    return AppBottomSheet(
      title: l.shareMaxSize,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.maxSizeBody, style: context.text.bodyMedium?.copyWith(fontSize: 13, height: 1.4, color: c.muted)),
          const SizedBox(height: Space.x4),
          DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  for (final (i, b) in maxSizePresets.indexed)
                    _Option(
                      divider: i > 0,
                      selected: _selected == b,
                      label: maxSizeLabel(context, b),
                      note: switch (b) {
                        null => l.maxSizeNoteOriginal,
                        1000000 => l.maxSizeNote1mb,
                        500000 => l.maxSizeNote500kb,
                        _ => l.maxSizeNote200kb,
                      },
                      tag: _tagFor(context, b),
                      warn: b != null && b < 300000,
                      onTap: () => setState(() => _selected = b),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.x4),
          Row(
            children: [
              Text(l.maxSizeCustom, style: context.text.labelLarge?.copyWith(fontSize: 13, color: c.muted)),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _custom,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  onChanged: (_) => setState(() => _selected = _customBytes ?? -1),
                  decoration: InputDecoration(hintText: l.maxSizeCustomHint),
                ),
              ),
              const SizedBox(width: 10),
              Text(l.maxSizeKb, style: context.text.labelLarge?.copyWith(fontSize: 14, color: c.muted)),
            ],
          ),
          const SizedBox(height: 22),
          PrimaryButton(
            label: l.commonDone,
            onPressed: canFinish ? () => Navigator.of(context).pop((bytes: customOn ? _customBytes : _selected)) : null,
          ),
        ],
      ),
    );
  }

  static String _tagFor(BuildContext context, int? b) {
    final l = context.l10n;
    if (b == null) return l.maxSizeTagBest;
    if (b >= 1000000) return l.maxSizeTagSharp;
    if (b >= 300000) return l.maxSizeTagGood;
    return l.maxSizeTagReadable;
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.divider,
    required this.selected,
    required this.label,
    required this.note,
    required this.tag,
    required this.warn,
    required this.onTap,
  });

  final bool divider;
  final bool selected;
  final String label;
  final String note;
  final String tag;
  final bool warn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = warn ? c.danger : c.success;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.accentSoft : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(border: divider ? Border(top: BorderSide(color: c.border)) : null),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? c.accent : c.border, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: selected
                      ? Container(width: 10, height: 10, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle))
                      : null,
                ),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FitText(label, textAlign: TextAlign.start, style: context.text.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(note, style: context.text.bodySmall?.copyWith(fontSize: 12, color: c.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: Space.x2),
                Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: tone.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Text(tag, style: context.text.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w800, color: tone)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
