/// Explicit, opt-in admission guard for disposable WSL smoke fixtures.
/// This is not a sandbox and does not supervise processes after admission.
class WslSmokeIsolation {
  const WslSmokeIsolation._(this.guard, this.home, this.identity, this.sha256);

  static const keys = [
    'HARNESS_SMOKE_GUARD',
    'HARNESS_SMOKE_HOME',
    'HARNESS_SMOKE_ID',
    'HARNESS_SMOKE_GUARD_SHA256',
  ];
  final String guard;
  final String home;
  final String identity;
  final String sha256;

  static WslSmokeIsolation? fromEnvironment(Map<String, String> environment) {
    if (!keys.any(environment.containsKey)) return null;
    final values = keys.map((key) => environment[key] ?? '').toList();
    bool path(String value) =>
        value.startsWith('/') &&
        !value.contains('\x00') &&
        !value.split('/').any((part) => part == '.' || part == '..');
    if (!path(values[0]) ||
        !values[0].startsWith('/mnt/c/') ||
        !path(values[1]) ||
        !RegExp(r'/hwp-gui-[^/]+/home$').hasMatch(values[1]) ||
        values[0].startsWith('${values[1]}/') ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(values[2]) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(values[3])) {
      throw StateError('Incomplete or invalid disposable WSL smoke contract.');
    }
    return WslSmokeIsolation._(values[0], values[1], values[2], values[3]);
  }

  List<String> wrap(List<String> command) => [
    '/usr/bin/env',
    '-u',
    'BASH_ENV',
    '-u',
    'ENV',
    '/bin/bash',
    '--noprofile',
    '--norc',
    '-c',
    admissionScript,
    'harness-smoke-admission',
    guard,
    home,
    identity,
    sha256,
    ...command,
  ];

  // The check is explicit shell source, not optional BASH_ENV startup behavior.
  // Values and the original argv remain positional data, never interpolated.
  static const admissionScript = r'''
_hws_refuse() { trap - EXIT; printf '%s\n' 'Disposable WSL smoke contract unavailable; refusing command.' >&2; exit 125; }
_hws_guard=$1; _hws_home=$2; _hws_id=$3; _hws_sha=$4; shift 4
[ -f "$_hws_guard" ] && [ ! -L "$_hws_guard" ] || _hws_refuse
[ -d "$_hws_home" ] && [ ! -L "$_hws_home" ] || _hws_refuse
[ "$(/usr/bin/readlink -e -- "$_hws_home")" = "$_hws_home" ] || _hws_refuse
_hws_marker="$_hws_home/.smoke-fixture-id"
[ -f "$_hws_marker" ] && [ ! -L "$_hws_marker" ] || _hws_refuse
IFS= read -r _hws_actual < "$_hws_marker" || _hws_refuse
[ "$_hws_actual" = "$_hws_id" ] || _hws_refuse
_hws_sum=$(/usr/bin/sha256sum < "$_hws_guard") || _hws_refuse
[ "${_hws_sum%% *}" = "$_hws_sha" ] || _hws_refuse
unset HARNESS_SMOKE_VALIDATED_ID
# A guard that exits while it is sourced refuses; it never reports success.
trap _hws_refuse EXIT
. "$_hws_guard" || _hws_refuse
trap - EXIT
[ "$HOME" = "$_hws_home" ] && [ "${HARNESS_SMOKE_VALIDATED_ID-}" = "$_hws_id" ] || _hws_refuse
[ -d "$_hws_home" ] && [ -f "$_hws_guard" ] || _hws_refuse
unset _hws_guard _hws_home _hws_id _hws_sha _hws_marker _hws_actual _hws_sum
unset -f _hws_refuse
exec "$@"
''';
}
