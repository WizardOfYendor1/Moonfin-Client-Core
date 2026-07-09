import 'package:flutter/material.dart';

/// The small tinted label shown above a group of settings. Lives here as a
/// public widget so both the settings side-panel part files and the
/// standalone settings screens can render the same header.
class SettingsSectionHeader extends StatelessWidget {
  final String text;

  const SettingsSectionHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
