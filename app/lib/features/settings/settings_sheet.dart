import 'package:flutter/material.dart';

import '../../app/design/pressable_scale.dart';
import '../../app/design/sheets.dart';
import '../../app/design/tokens.dart';
import '../../app/services.dart';
import '../../data/library.dart';
import '../library/library_screen.dart';
import '../pro/pro.dart';

/// Settings, as a sheet from the Record screen.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key, required this.services});

  final Services services;

  @override
  Widget build(BuildContext context) {
    final lib = services.library;
    final pro = services.pro;
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([lib, pro]),
      builder: (context, _) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Settings', style: text.headlineSmall),
            const SizedBox(height: Space.xl),
            Text('Playback starts before a mark', style: text.labelLarge),
            const SizedBox(height: Space.s),
            Wrap(runSpacing: Space.s, children: [ // wraps at large text sizes
              _Choice(label: 'Off', selected: !lib.preRoll, onTap: () => lib.setPreRoll(false)),
              for (final s in LibraryStore.preRollChoices)
                _Choice(
                  label: '$s s',
                  semantic: '$s seconds',
                  selected: lib.preRoll && lib.preRollSeconds == s,
                  onTap: () async {
                    await lib.setPreRollSeconds(s);
                    await lib.setPreRoll(true);
                  },
                ),
            ]),
            const SizedBox(height: Space.l),
            MergeSemantics(
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Calm screen while recording', style: text.labelLarge),
                    Text('Dims to black after 20 s without a touch. Bookmark still works.',
                        style: text.bodySmall),
                  ]),
                ),
                Switch(value: lib.calmMode, onChanged: lib.setCalmMode),
              ]),
            ),
            const SizedBox(height: Space.l),
            _Row(
              title: 'Quick labels',
              detail: pro.owned ? lib.quickLabels.where((l) => l.isNotEmpty).join(' · ') : 'Pro',
              onTap: () async {
                if (await requirePro(context, pro) && context.mounted) await _editLabels(context, lib);
              },
            ),
            _Row(
              title: 'Recently deleted',
              detail: '${lib.recentlyDeleted.length}',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RecentlyDeletedScreen(library: lib))),
            ),
            _Row(
              title: 'Earmark Pro',
              detail: pro.owned ? 'On' : 'One-time',
              onTap: () => showAppSheet<void>(context, (_) => ProSheet(pro: pro)),
            ),
            _Row(title: 'Privacy', detail: '', onTap: () => showAppSheet<void>(context, (_) => const _Privacy())),
            _Row(
              title: 'Licences',
              detail: '',
              onTap: () => showLicensePage(context: context, applicationName: 'Earmark'),
            ),
            const SizedBox(height: Space.s),
            Text('Earmark has no account and no servers.', style: text.bodySmall!.copyWith(color: c.text2)),
          ],
        ),
      ),
    );
  }

  static Future<void> _editLabels(BuildContext context, LibraryStore lib) async {
    await showAppSheet<void>(
      context,
      (ctx) => ListenableBuilder(
        listenable: lib,
        builder: (ctx, _) {
          final labels = [...lib.quickLabels, '', '', '', ''].take(4).toList();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Quick labels', style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: Space.xs),
              Text('Hold Bookmark while recording, slide to a label and let go.', style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: Space.l),
              for (var i = 0; i < 4; i++)
                _Row(
                  title: labels[i].isEmpty ? 'Empty' : labels[i],
                  detail: 'Edit',
                  onTap: () async {
                    final t = await askText(ctx, title: 'Quick label ${i + 1}', initial: labels[i], hint: 'Idea');
                    if (t == null) return;
                    final next = [...labels]..[i] = t.trim();
                    await lib.setQuickLabels(next);
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap, this.semantic});

  final String label;
  final String? semantic;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: Space.s),
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: PressableScale(
          semanticLabel: semantic ?? label,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 56, minHeight: kMinTarget),
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            decoration: BoxDecoration(
              color: selected ? c.text : c.raised,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: selected ? c.text : c.border),
            ),
            // Sized to the text (a Wrap hands out the full width).
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(label, style: Theme.of(context).textTheme.labelLarge!.copyWith(color: selected ? c.bg : c.text)),
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.detail, required this.onTap});

  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return PressableScale(
      semanticLabel: detail.isEmpty ? title : '$title, $detail',
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(children: [
          Expanded(child: Text(title, style: text.bodyLarge)),
          if (detail.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(detail, style: text.bodyLarge!.copyWith(color: c.text2), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          const SizedBox(width: Space.xs),
          Icon(Icons.chevron_right_rounded, color: c.text2),
        ]),
      ),
    );
  }
}

class _Privacy extends StatelessWidget {
  const _Privacy();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Privacy', style: text.headlineSmall),
        const SizedBox(height: Space.l),
        Text(
          'Earmark has no account, no servers and no analytics. Recordings, marks and labels stay on this '
          'device. Audio leaves it only when you share a clip yourself.\n\n'
          'On iPhone, recordings are part of your own device backup.\n\n'
          'Earmark Pro is bought through Google Play or the App Store; Earmark only learns whether Pro is owned.',
          style: text.bodyLarge,
        ),
      ],
    );
  }
}
