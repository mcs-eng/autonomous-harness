import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One setting: a title and a line of detail on the left, its control on the
/// right.
///
/// The shape every preference in this app is stated in. It began private inside
/// Appearance ▸ Typography and moved here the moment Settings ▸ Terminal needed
/// the same row — two panes inventing their own answer to "what does a setting
/// look like" is exactly how the Terminal pane ended up wearing raw Material
/// while the one beside it wore the design system.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    this.detail,
    required this.control,
    this.footer,
    this.alignTop = false,
  });

  final String title;
  final String? detail;
  final Widget control;

  /// Guidance or feedback that belongs inside this setting's block.
  final Widget? footer;

  /// Align taller controls with the title; compact controls stay centered.
  final bool alignTop;

  /// Fixed, so every control on this screen lines up on one right edge.
  static const double controlWidth = 188;

  /// Below this the control drops under the text and takes the full width.
  /// Squeezing it instead is what used to push it out past the row's own edge.
  static const double _stackBelow = controlWidth + 20 + 130;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        if (detail case final detail?) ...[
          const SizedBox(height: 2),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );

    return Container(
      // A raised block: fill plus a soft lift, no rim. The same recipe the rest
      // of the app gives a row you can act on, so a setting here sits at the
      // same height as a row anywhere else.
      decoration: detail == null
          ? null
          : BoxDecoration(
              color: AppGlass.surfaceFill,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppGlass.cardShadow,
            ),
      padding: detail == null
          ? const EdgeInsets.symmetric(vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth <
                    MediaQuery.textScalerOf(context).scale(_stackBelow)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [text, const SizedBox(height: 10), control],
                  )
                : Row(
                    crossAxisAlignment: alignTop
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      Expanded(child: text),
                      const SizedBox(width: 20),
                      control,
                    ],
                  ),
          ),
          if (footer case final footer?) ...[const SizedBox(height: 8), footer],
        ],
      ),
    );
  }
}
