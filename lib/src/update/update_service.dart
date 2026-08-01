import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_version.dart';

/// Where releases are published. Anonymous reads of a public repository need no
/// token, which is exactly why the repository is public — shipping a GitHub
/// credential inside the app would be worse than not having updates at all.
const String kGitHubOwner = 'Lakshaypal';
const String kGitHubRepo = 'attendance-tracker';

Uri get kLatestReleaseApi => Uri.https(
  'api.github.com',
  '/repos/$kGitHubOwner/$kGitHubRepo/releases/latest',
);

Uri get kReleasesPage =>
    Uri.https('github.com', '/$kGitHubOwner/$kGitHubRepo/releases/latest');

/// What the app found when it asked GitHub.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.downloadUrl,
    required this.pageUrl,
    required this.assetName,
  });

  final AppVersion version;
  final String notes;

  /// Direct link to the artifact for this platform, when one was published.
  final String? downloadUrl;

  /// The human release page, always usable as a fallback.
  final String pageUrl;
  final String? assetName;
}

enum UpdateState { idle, checking, upToDate, available, failed }

/// Checks GitHub Releases for a newer build and reports what it finds.
///
/// Deliberately conservative: any network, parsing or rate-limit problem
/// resolves to [UpdateState.failed] with a readable message and never throws
/// into the UI. A failed check is a non-event — the app keeps working.
class UpdateService extends ChangeNotifier {
  UpdateService({
    required this.currentVersion,
    http.Client? client,
    this.now = DateTime.now,
  }) : _client = client ?? http.Client();

  final AppVersion currentVersion;
  final http.Client _client;
  final DateTime Function() now;

  UpdateState state = UpdateState.idle;
  UpdateInfo? available;
  String? message;
  DateTime? lastChecked;

  /// Versions the user has explicitly dismissed.
  final Set<String> _skipped = {};

  bool get hasUpdate =>
      state == UpdateState.available &&
      available != null &&
      !_skipped.contains(available!.version.toString());

  void skip(AppVersion version) {
    _skipped.add(version.toString());
    notifyListeners();
  }

  /// The file name pattern the release workflow publishes for this platform.
  static String? assetSuffixForPlatform() {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return '.apk';
    if (Platform.isMacOS) return '-macos.zip';
    return null;
  }

  Future<void> check({bool silent = false}) async {
    if (state == UpdateState.checking) return;
    state = UpdateState.checking;
    message = null;
    if (!silent) notifyListeners();

    try {
      final response = await _client
          .get(
            kLatestReleaseApi,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 404) {
        // No release published yet: not an error worth shouting about.
        state = UpdateState.upToDate;
        lastChecked = now();
        notifyListeners();
        return;
      }
      if (response.statusCode == 403) {
        throw const HttpException(
          'GitHub rate limit reached. Try again later.',
        );
      }
      if (response.statusCode != 200) {
        throw HttpException('GitHub replied ${response.statusCode}.');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException('Unexpected reply.');
      final info = _parseRelease(Map<String, dynamic>.from(decoded));
      if (info == null) throw const FormatException('No usable release found.');

      lastChecked = now();
      if (info.version > currentVersion) {
        available = info;
        state = UpdateState.available;
      } else {
        available = null;
        state = UpdateState.upToDate;
      }
    } catch (error) {
      state = UpdateState.failed;
      message = switch (error) {
        SocketException() => 'No connection, so updates could not be checked.',
        HttpException(:final message) => message,
        FormatException(:final message) => message,
        _ => 'Could not check for updates.',
      };
    }
    notifyListeners();
  }

  UpdateInfo? _parseRelease(Map<String, dynamic> json) {
    if (json['draft'] == true) return null;
    final version =
        AppVersion.tryParse(json['tag_name'] as String?) ??
        AppVersion.tryParse(json['name'] as String?);
    if (version == null) return null;

    final suffix = assetSuffixForPlatform();
    String? downloadUrl;
    String? assetName;
    final assets = json['assets'];
    if (suffix != null && assets is List) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name'] as String?;
        if (name == null || !name.endsWith(suffix)) continue;
        downloadUrl = asset['browser_download_url'] as String?;
        assetName = name;
        break;
      }
    }

    return UpdateInfo(
      version: version,
      notes: ((json['body'] as String?) ?? '').trim(),
      downloadUrl: downloadUrl,
      pageUrl: (json['html_url'] as String?) ?? kReleasesPage.toString(),
      assetName: assetName,
    );
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
