/// Turns a path the GUI's native picker produced into a path the CLI can open.
///
/// ## Why this exists
///
/// On macOS and Linux the app and its CLI share one filesystem, so a path from
/// the native folder panel is already the right answer. On Windows that is not
/// true: the CLI usually runs INSIDE a WSL2 distribution (see `wsl_runtime.dart`),
/// and `C:\work\project` names no directory in that distribution at all. A
/// dialog that opened the Windows picker would hand the CLI a cwd it cannot
/// chdir into, and the agent would fail to start in the very folder the user
/// watched themselves select.
///
/// So "this is my computer" (connectivity) and "this machine shares my
/// filesystem" (paths) are two different questions, and only the second one
/// decides whether a native picker is useful. Where they differ, the app browses
/// the backend's own filesystem over the daemon's `fs_list_dir` RPC — and, when
/// a path still arrives in GUI form, converts it here or REFUSES it. A refusal
/// with a sentence is better than a path the CLI will fail on later.
///
/// The conversion is deliberately bounded and explicit:
///
/// * a POSIX path is already backend-native and passes through;
/// * `C:\…` / `C:/…` maps to `/mnt/c/…` (the WSL mount of that drive);
/// * `\\wsl.localhost\<distro>\…` and `\\wsl$\<distro>\…` map into that
///   distribution's root, and only when it is the distribution in use;
/// * anything else — a network share, a drive-relative or UNC path naming a
///   machine that is not this one, a relative path — is **null**: there is no
///   honest conversion, so the caller must ask the user for a backend path.
class BackendPath {
  const BackendPath._();

  static const List<String> _wslUncRoots = ['wsl.localhost', r'wsl$'];

  /// The backend-native form of [path], or null when there is none.
  ///
  /// [distro] is the WSL distribution the CLI runs in; it is only consulted for
  /// `\\wsl…` paths, where naming a different distribution means the path is not
  /// on this backend.
  static String? toBackend(
    String path, {
    required bool backendIsWsl,
    String? distro,
  }) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    if (!backendIsWsl) return trimmed;
    // Windows also accepts forward slashes in UNC paths. Do not mistake a
    // network share for a directory in the distribution's root filesystem.
    if (trimmed.startsWith('//')) return null;

    // Already a Linux path: nothing to do. `~` is left for the CLI's own shell.
    if (trimmed.startsWith('/') || trimmed == '~' || trimmed.startsWith('~/')) {
      return trimmed;
    }

    if (trimmed.startsWith(r'\\')) {
      return _fromWslUnc(trimmed, distro: distro);
    }

    return _fromDrivePath(trimmed);
  }

  /// `\\wsl.localhost\Ubuntu\home\ana\project` -> `/home/ana/project`.
  static String? _fromWslUnc(String path, {required String? distro}) {
    final parts = path
        .substring(2)
        .split(RegExp(r'\\+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 2) return null;
    final root = parts.first.toLowerCase();
    if (!_wslUncRoots.contains(root)) return null;
    final namedDistro = parts[1];
    if (distro == null || namedDistro.toLowerCase() != distro.toLowerCase()) {
      // A different distribution's filesystem: not where this CLI runs.
      return null;
    }
    final rest = parts.skip(2).join('/');
    return rest.isEmpty ? '/' : '/$rest';
  }

  /// `C:\work\project` -> `/mnt/c/work/project`.
  static String? _fromDrivePath(String path) {
    final match = RegExp(r'^([A-Za-z]):[\\/](.*)$').firstMatch(path);
    if (match == null) return null;
    final drive = match.group(1)!.toLowerCase();
    final rest = match.group(2)!.replaceAll('\\', '/');
    return rest.isEmpty ? '/mnt/$drive' : '/mnt/$drive/$rest';
  }
}
