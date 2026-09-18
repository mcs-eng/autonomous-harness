import 'package:flutter/widgets.dart';

/// The Harness Store wears the app icon — the mark the Dock shows — wherever
/// its tab is drawn. The native tab strip and History menu are sent this path
/// and open the same file (`SwarmHistoryIcons` in
/// macos/Runner/SwarmTitlebar.swift, which must name it or it draws an initial).
const String kStoreMarkAsset = 'assets/app_icon.png';

/// [kStoreMarkAsset] at a mark's size: the Flutter tab strip, and the store's
/// row in History. The 256px source is filtered down, so it stays crisp at 2x.
class StoreMark extends StatelessWidget {
  const StoreMark({super.key, this.size = 16, this.enabled = true});

  final double size;

  /// Dimmed like `EngineMark` when its row cannot be chosen.
  final bool enabled;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.45,
    child: Image.asset(
      kStoreMarkAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    ),
  );
}
