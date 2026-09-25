import 'package:flutter/material.dart';

/// Visual beat/pulse indicator: a row of dots, one per beat in the tala's
/// cycle, with the current beat highlighted and pulsing at the current
/// tempo. Presentational only — give it bpm, beat count and whether audio is
/// playing, and it animates while [isPlaying] is true.
class BeatPulseIndicator extends StatefulWidget {
  final int bpm;
  final int beatsCount;
  final bool isPlaying;
  final Color activeColor;
  final Color inactiveColor;

  const BeatPulseIndicator({
    super.key,
    required this.bpm,
    required this.beatsCount,
    required this.isPlaying,
    this.activeColor = Colors.white,
    this.inactiveColor = const Color(0x55FFFFFF),
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
        height: 40,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_beats, (index) {
              final active = widget.isPlaying && index == _currentBeat;
              final scale = active ? 1.0 + (0.5 * (1 - _controller.value)) : 1.0;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? widget.activeColor : widget.inactiveColor,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
