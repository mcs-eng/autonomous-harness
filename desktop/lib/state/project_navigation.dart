import '../core/models.dart';
import '../widgets/engine_identity.dart';
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

/// The last part of [folder], for a line whose tooltip shows all of it.
String folderBase(String folder) {
  final parts = folder.split(RegExp(r'[/\\]')).where((part) => part.isNotEmpty);
  return parts.isEmpty ? folder : parts.last;
}

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
  // The harness's engine exited and the daemon kept the pane as a shell.
  if (isTerminalEngine(row.agent.engine) && row.agent.dsh != null) {
    return 'Stopped';
  }
  if (app.questionFor(row.machineId, row.agent.id) != null) {
    return 'Needs input';
  }
  if (app.agentIsProcessing(row.machineId, row.agent.id)) return 'Working';
  return 'Ready';
}

/// What the sidebar and Continue working call a session: a name or title
/// somebody gave it, otherwise the harness or engine it runs ("Grid", "Codex").
/// Tabs and dialogs keep [Agent.displayName], so a rename still starts from
/// the real name.
String sessionLabel(Agent agent) {
  if (!isAutomaticHarnessName(agent.name)) return agent.name;
  final title = agent.title?.trim();
  if (title != null && title.isNotEmpty && !isAutomaticHarnessName(title)) {
    return title;
  }
  return agentIdentity(agent).label;
}

final _automaticStamp = RegExp(
  r' harness (\d{1,2}-\d{1,2}) (\d{1,2}:\d{2}(?::\d{2})?)$',
);

/// [labels] with repeats told apart, in order. A repeat takes the clock from
/// its generated name in [names] ("Codex · 16:20"), then the date and clock,
/// then its position among the repeats ("Codex · 2").
List<String> distinctLabels(List<String> labels, List<String> names) {
  String? stamp(int i, {required bool dated}) {
    final match = _automaticStamp.firstMatch(names[i]);
    if (match == null) return null;
    return dated ? '${match[1]} ${match[2]}' : match[2];
  }

  String distinct(int i) {
    final same = [
      for (var j = 0; j < labels.length; j++)
        if (labels[j] == labels[i]) j,
    ];
    if (same.length == 1) return labels[i];
    for (final dated in [false, true]) {
      final own = stamp(i, dated: dated);
      if (own != null &&
          same.where((j) => stamp(j, dated: dated) == own).length == 1) {
        return '${labels[i]} · $own';
      }
    }
    return '${labels[i]} · ${same.indexOf(i) + 1}';
  }

  return [for (var i = 0; i < labels.length; i++) distinct(i)];
}

/// [sessionLabel] for each row, with repeats told apart ([distinctLabels]).
List<String> sessionLabels(List<SwarmAgentRef> rows) => distinctLabels(
  [for (final row in rows) sessionLabel(row.agent)],
  [for (final row in rows) row.agent.name],
);

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
