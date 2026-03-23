// lib/features/camera/widgets/flash_toggle.dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class FlashToggle extends StatefulWidget {
  const FlashToggle({super.key, required this.controller});
  final CameraController controller;

  @override
  State<FlashToggle> createState() => _FlashToggleState();
}

class _FlashToggleState extends State<FlashToggle> {
  FlashMode _mode = FlashMode.auto;

  static const _modes = [
    FlashMode.auto,
    FlashMode.always,
    FlashMode.off,
    FlashMode.torch,
  ];

  static IconData _icon(FlashMode mode) => switch (mode) {
        FlashMode.auto   => Icons.flash_auto,
        FlashMode.always => Icons.flash_on,
        FlashMode.off    => Icons.flash_off,
        FlashMode.torch  => Icons.highlight,
        _                => Icons.flash_auto,
      };

  void _cycle() {
    final next = _modes[(_modes.indexOf(_mode) + 1) % _modes.length];
    setState(() => _mode = next);
    widget.controller.setFlashMode(next);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(_icon(_mode), color: Colors.white),
      onPressed: _cycle,
      tooltip: 'Flash: ${_mode.name}',
    );
  }
}
