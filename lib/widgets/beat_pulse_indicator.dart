import 'package:flutter/material.dart';

import '../ui/brand.dart';

/// Visual beat/pulse indicator: a row of neon lights, one per beat in the
/// tala's cycle, with the current beat lit and pulsing at the current tempo
/// (the first beat of the cycle — sam — in [samColor]). Presentational only
/// — give it bpm, beat count and whether audio is playing, and it animates
/// while [isPlaying] is true.
class BeatPulseIndicator extends StatefulWidget {
  final int bpm;
  final int beatsCount;
  final bool isPlaying;
  final Color activeColor;
  final Color samColor;
  final Color inactiveColor;

  const BeatPulseIndicator({
    super.key,
    required this.bpm,
    required this.beatsCount,
    required this.isPlaying,
    this.activeColor = Brand.cyan,
    this.samColor = Brand.pink,
    this.inactiveColor = Brand.borderStrong,
  });

  @override
  State<BeatPulseIndicator> createState() => _BeatPulseIndicatorState();
}

class _BeatPulseIndicatorState extends State<BeatPulseIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _currentBeat = 0;

  int get _beats => widget.beatsCount.clamp(1, 32);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _beatDuration())
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _currentBeat = (_currentBeat + 1) % _beats);
          if (widget.isPlaying) {
            _controller
              ..reset()
              ..forward();
          }
        }
      });
    if (widget.isPlaying) _controller.forward();
  }

  Duration _beatDuration() {
    final bpm = widget.bpm <= 0 ? 60 : widget.bpm;
    return Duration(milliseconds: (60000 / bpm).round());
  }

  @override
  void didUpdateWidget(covariant BeatPulseIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bpm != widget.bpm) _controller.duration = _beatDuration();
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.forward();
    } else if (!widget.isPlaying) {
      _controller.stop();
      _currentBeat = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.isPlaying ? 'Beat indicator, playing at ${widget.bpm} BPM' : 'Beat indicator, stopped',
      child: SizedBox(
        height: 28,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => LayoutBuilder(builder: (context, c) {
            // Shrink the lights so a long cycle (e.g. 16 beats) still fits
            // on one row on a narrow phone.
            final size = ((c.maxWidth / _beats) - 8).clamp(6.0, 12.0);
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_beats, (index) {
                final active = widget.isPlaying && index == _currentBeat;
                final color = index == 0 ? widget.samColor : widget.activeColor;
                final fade = 1 - _controller.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Transform.scale(
                    scale: active ? 1.0 + 0.5 * fade : 1.0,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active ? color : widget.inactiveColor,
                        border: index == 0 && !active
                            ? Border.all(color: widget.samColor.withValues(alpha: 0.6))
                            : null,
                        boxShadow: active ? Brand.glow(color, 0.5 + 0.5 * fade) : null,
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
        ),
      ),
    );
  }
}
