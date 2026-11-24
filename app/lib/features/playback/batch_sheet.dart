import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/design/pressable_scale.dart';
import '../../app/design/sheets.dart';
import '../../app/design/tokens.dart';
import '../../app/format.dart';
import '../../app/services.dart';
import '../../data/library.dart';
import 'waveform.dart';

/// Pro: pick marks, export each one's clip (the same 20 s window as Share clip), share them together.
class BatchClipSheet extends StatefulWidget {
  const BatchClipSheet({super.key, required this.services, required this.recording});

  final Services services;
  final Recording recording;

  @override
  State<BatchClipSheet> createState() => _BatchClipSheetState();
}

class _BatchClipSheetState extends State<BatchClipSheet> {
  late final Set<String> _picked = {for (final m in widget.recording.userMarks) m.id};
  int? _making; // 1-based clip in progress
  String? _error;

  Future<void> _share() async {
    final r = widget.recording;
    final marks = r.userMarks.where((m) => _picked.contains(m.id)).toList();
    setState(() => _error = null);
    final files = <XFile>[];
    try {
      for (final (i, m) in marks.indexed) {
        setState(() => _making = i + 1);
        final w = clipWindow(m.posMs, r.durationMs);
        final path = await widget.services.engine.exportClip(r.folder, w.start, w.end, clipFileName(r, m, w.start, w.end));
        files.add(XFile(path, mimeType: 'audio/mp4'));
      }
      await SharePlus.instance.share(ShareParams(files: files, title: '${r.title} — ${files.length} clips'));
    } on PlatformException catch (e) {
      _error = e.message ?? 'A clip could not be made.';
    } finally {
      if (mounted) setState(() => _making = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final marks = widget.recording.userMarks;
    final n = _picked.length;
    final busy = _making != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Share clips', style: text.headlineSmall),
        const SizedBox(height: Space.xs),
        Text('20 s around each mark, as separate files.', style: text.bodySmall),
        const SizedBox(height: Space.l),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final m in marks)
                Semantics(
                  checked: _picked.contains(m.id),
                  child: PressableScale(
                    semanticLabel: '${m.name} at ${spokenTime(m.posMs)}',
                    onTap: busy
                        ? null
                        : () => setState(() => _picked.contains(m.id) ? _picked.remove(m.id) : _picked.add(m.id)),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Row(children: [
                        RibbonFlag(n: m.n),
                        const SizedBox(width: Space.m),
                        Text(clock(m.posMs), style: text.labelLarge!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                        const SizedBox(width: Space.m),
                        Expanded(child: Text(m.name, style: text.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Icon(
                          _picked.contains(m.id) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          color: _picked.contains(m.id) ? c.accentInk : c.text2,
                        ),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.l),
        SheetButton(
          label: busy ? 'Making clip $_making of $n…' : (n == 1 ? 'Share 1 clip' : 'Share $n clips'),
          fill: n == 0 || busy ? null : c.accent,
          ink: c.onAccent,
          onTap: n == 0 || busy ? null : _share,
        ),
        if (_error != null) ...[
          const SizedBox(height: Space.s),
          Semantics(liveRegion: true, child: Text(_error!, style: text.bodyMedium!.copyWith(color: c.rec))),
        ],
      ],
    );
  }
}
