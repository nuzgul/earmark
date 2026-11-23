import 'package:flutter/material.dart';

import '../../app/design/pressable_scale.dart';
import '../../app/design/tokens.dart';
import '../../engine/engine_client.dart';

/// Home screen. Phase 0: the idle state only; recording UI arrives in Phase 1.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.engine});

  final EngineClient engine;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  @override
  void initState() {
    super.initState();
    widget.engine.refresh();
  }

  Future<void> _record() async {
    final error = await widget.engine.start();
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.screen, Space.xxxl, Space.screen, Space.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The 76 sp timer is already large; it shrinks to fit instead of wrapping at big text sizes.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('00:00', maxLines: 1, style: text.displayLarge!.copyWith(color: c.text2)),
              ),
              const SizedBox(height: Space.s),
              Text('Ready to record', style: text.bodyLarge!.copyWith(color: c.text2)),
              const Spacer(),
              Center(
                child: PressableScale(
                  semanticLabel: 'Start recording',
                  pressedScale: 0.95,
                  onTap: _record,
                  child: _RecordButton(colors: c),
                ),
              ),
              const SizedBox(height: Space.m),
              Center(child: ExcludeSemantics(child: Text('Record', style: text.labelLarge))),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      height: 132,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colors.border, width: 2),
      ),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(shape: BoxShape.circle, color: colors.rec),
      ),
    );
  }
}
