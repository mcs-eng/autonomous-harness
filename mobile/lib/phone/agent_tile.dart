import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/core/models.dart';
import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/state/app_state.dart';
import 'package:harness_mobile/widgets/engine_identity.dart';

import 'phone_card.dart';
import 'phone_status.dart';
import 'status_pill.dart';

/// One agent on a machine's page: its engine, its name, and what it is doing. An agent with no
/// terminal to attach is drawn dimmed and does not open — but it can still be held for [onLongPress],
/// which is the only way to reach an agent whose terminal has gone.
class AgentTile extends StatelessWidget {
  const AgentTile({
    super.key,
    required this.machine,
    required this.agent,
    required this.onTap,
    this.onLongPress,
  });

  final MachineState machine;
  final Agent agent;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return PhoneCard(
      onTap: agent.terminalAvailable ? onTap : null,
      onLongPress: onLongPress,
      child: Row(
        children: [
          PhoneCardGlyph(
            child: EngineMark(
              engine: agent.engine,
              displayName: agent.engineDisplayName,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agent.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppPalette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                StatusPill(summary: phoneAgentSummary(machine, agent)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            LucideIcons.chevronRight300,
            size: 22,
            color: AppPalette.textFaint,
          ),
        ],
      ),
    );
  }
}
