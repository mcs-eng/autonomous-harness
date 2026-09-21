import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'harness_file_store.dart';
import 'local_key_value_store.dart';

/// An app-specific Linux account. This never changes WSL's global defaults.
@immutable
class WslSelection {
  final String distro;
  final String username;

  const WslSelection({required this.distro, required this.username});

  static bool isDockerDistro(String name) {
    final normalized = name.trim().toLowerCase();
    return normalized == 'docker-desktop' ||
        normalized.startsWith('docker-desktop-');
  }

  static String? validationError({
    required String distro,
    required String username,
  }) {
    if (distro.isEmpty ||
        distro.length > 128 ||
        distro != distro.trim() ||
        distro.startsWith('-') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(distro) ||
        isDockerDistro(distro)) {
      return 'Choose a valid Linux distribution outside Docker Desktop.';
    }
    if (username.length > 32 ||
        !RegExp(r'^[a-z_][a-z0-9_-]*\$?$').hasMatch(username)) {
      return 'Enter a Linux username using lowercase letters, numbers, underscores or hyphens.';
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is WslSelection &&
      other.distro == distro &&
      other.username == username;

  @override
  int get hashCode => Object.hash(distro, username);
}

/// Active account state is immutable after loading: identity, authentication,
/// and daemon caches must all change together on the next application launch.
class WslPreferencesStore extends ChangeNotifier {
  WslPreferencesStore({LocalKeyValueStore? storage})
    : _storage =
          storage ??
          HarnessFileStore(
            directory: Directory(
              HarnessFileStore.defaultDirectoryPath(
                name: 'desktop-wsl-account',
              ),
            ),
            recoverCorruption: false,
          );

  static const key = 'harness_wsl_account';
  final LocalKeyValueStore _storage;
  Future<void>? _loading;
  WslSelection? _value;
  WslSelection? _savedSelection;
  String? _loadError;
  bool _repaired = false;

  WslSelection? get value => _value;
  WslSelection? get savedSelection => _savedSelection;
  String? get loadError => _loadError;
  bool get restartRequired => _repaired || _savedSelection != _value;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final raw = await _storage.read(key);
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is! Map<String, dynamic> ||
            data['version'] != 1 ||
            data['distro'] is! String ||
            data['username'] is! String) {
          throw const FormatException('Invalid WSL account setting');
        }
        final selection = WslSelection(
          distro: data['distro'] as String,
          username: data['username'] as String,
        );
        if (WslSelection.validationError(
              distro: selection.distro,
              username: selection.username,
            ) !=
            null) {
          throw const FormatException('Invalid WSL account setting');
        }
        _value = selection;
      }
      _savedSelection = _value;
    } catch (_) {
      // Never let an unreadable explicit choice become the default account.
      _loadError =
          'The saved Linux account could not be read. Choose an '
          'account or the WSL default, then close and reopen Harness.';
    }
    notifyListeners();
  }

  Future<void> save(WslSelection? selection) async {
    await load();
    if (selection != null) {
      final error = WslSelection.validationError(
        distro: selection.distro,
        username: selection.username,
      );
      if (error != null) throw ArgumentError(error);
    }
    // Only an explicit Save may recover the dedicated account document. The
    // normal quarantine path retains the corrupt bytes; ordinary loads keep
    // refusing the same file on every application launch.
    final storage = _storage;
    final writer =
        _loadError != null &&
            storage is HarnessFileStore &&
            !storage.recoverCorruption
        ? HarnessFileStore(directory: storage.directory)
        : storage;
    if (selection == null) {
      await writer.delete(key);
    } else {
      await writer.write(
        key,
        jsonEncode({
          'version': 1,
          'distro': selection.distro,
          'username': selection.username,
        }),
      );
    }
    // Publish only after persistence succeeds. Active state and load errors
    // remain unchanged until restart, including after repairing bad settings.
    _savedSelection = selection;
    _repaired = _loadError != null;
    notifyListeners();
  }
}

final wslPreferencesStore = WslPreferencesStore();
