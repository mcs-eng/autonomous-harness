import '../core/models.dart';
import 'app_state.dart';
import 'swarm_catalog.dart';

/// A repository may span hosts and checkouts. Creation always names one exact
/// working folder; the aggregate project's title is never a launch target.
typedef ProjectLocation = ({String machineId, String folder});

List<ProjectLocation> projectLocations(SwarmProjectGroup group) => {
  if (group.saved case final saved?)
    (machineId: saved.machineId, folder: projectFolderPath(saved.path)),
  for (final row in group.agents)
    if (row.project case final project?)
      (machineId: row.machineId, folder: projectFolderPath(project.cwd)),
}.toList();

String projectAgentStatus(AppNotifier app, SwarmAgentRef row) {
  if (row.machine.nodeOnline == false || row.machine.needsLink) {
    return 'Offline';
  }
  if (row.machine.connectionStatus != ConnectionStatus.connected) {
    return 'Connecting';
  }
  if (row.agent.launchState == 'failed') return 'Start failed';
  if (row.agent.launchState == 'starting') return 'Starting';
  if (!row.agent.terminalAvailable) return 'Unavailable';
  if (app.questionFor(row.machineId, row.agent.id) != null) {
    return 'Needs input';
  }
  if (app.agentIsProcessing(row.machineId, row.agent.id)) return 'Working';
  return 'Ready';
}

/// Opening is navigation, never agent creation. Reuse a view across all tabs,
/// including its companion viewer, or attach the existing agent in a new tab.
Future<void> openProjectAgent(AppNotifier app, SwarmAgentRef row) async {
  final current = app
      .stateOf(row.machineId)
      ?.agents
      .where((agent) => agent.id == row.agent.id)
      .firstOrNull;
  if (current == null) return;
  if (app.revealAgentView(row.machineId, row.agent.id)) return;
  if (!current.terminalAvailable) return;
  app.newSwarm();
  await app.addAgentToSwarm(
    row.machineId,
    row.agent.id,
    swarmId: app.activeSwarmId,
  );
}
