import 'dart:convert';

import 'package:attendance_tracker/src/update/app_version.dart';
import 'package:attendance_tracker/src/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Client replyWith(int status, Object? body) => MockClient(
  (request) async => http.Response(
    body is String ? body : jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  ),
);

Map<String, dynamic> release(
  String tag, {
  List<Map<String, dynamic>> assets = const [],
  String notes = 'Notes',
  bool draft = false,
}) => {
  'tag_name': tag,
  'name': tag,
  'body': notes,
  'draft': draft,
  'html_url': 'https://github.com/o/r/releases/tag/$tag',
  'assets': assets,
};

void main() {
  group('version parsing', () {
    test('reads the shapes release tags actually take', () {
      expect(AppVersion.tryParse('v1.2.3').toString(), '1.2.3');
      expect(AppVersion.tryParse('1.2.3').toString(), '1.2.3');
      expect(AppVersion.tryParse('1.2').toString(), '1.2.0');
      expect(AppVersion.tryParse('2').toString(), '2.0.0');
      expect(AppVersion.tryParse('1.2.3+45').toString(), '1.2.3');
      expect(AppVersion.tryParse('v1.2.3-beta.1').toString(), '1.2.3-beta.1');
    });

    test('returns null for junk rather than throwing', () {
      expect(AppVersion.tryParse('nightly'), isNull);
      expect(AppVersion.tryParse(''), isNull);
      expect(AppVersion.tryParse(null), isNull);
    });

    test('orders versions the way a human would', () {
      expect(
        AppVersion.tryParse('1.2.10')! > AppVersion.tryParse('1.2.9')!,
        isTrue,
      );
      expect(
        AppVersion.tryParse('1.10.0')! > AppVersion.tryParse('1.9.9')!,
        isTrue,
      );
      expect(
        AppVersion.tryParse('2.0.0')! > AppVersion.tryParse('1.99.99')!,
        isTrue,
      );
      expect(
        AppVersion.tryParse('1.0.0')! == AppVersion.tryParse('v1.0.0')!,
        isTrue,
      );
    });

    test('a pre-release is older than the release it leads to', () {
      expect(
        AppVersion.tryParse('1.2.0-beta.1')! < AppVersion.tryParse('1.2.0')!,
        isTrue,
      );
    });
  });

  group('checking for updates', () {
    test('reports a newer release', () async {
      final service = UpdateService(
        currentVersion: AppVersion.tryParse('1.0.0')!,
        client: replyWith(200, release('v1.1.0', notes: 'Adds a thing')),
      );
      await service.check();

      expect(service.state, UpdateState.available);
      expect(service.hasUpdate, isTrue);
      expect(service.available!.version.toString(), '1.1.0');
      expect(service.available!.notes, 'Adds a thing');
    });

    test('stays quiet when the release is the running version', () async {
      final service = UpdateService(
        currentVersion: AppVersion.tryParse('1.1.0')!,
        client: replyWith(200, release('v1.1.0')),
      );
      await service.check();
      expect(service.state, UpdateState.upToDate);
      expect(service.hasUpdate, isFalse);
    });

    test('never offers a downgrade', () async {
      final service = UpdateService(
        currentVersion: AppVersion.tryParse('2.0.0')!,
        client: replyWith(200, release('v1.9.0')),
      );
      await service.check();
      expect(service.state, UpdateState.upToDate);
    });

    test('picks the asset for this platform', () async {
      final suffix = UpdateService.assetSuffixForPlatform();
      final service = UpdateService(
        currentVersion: AppVersion.tryParse('1.0.0')!,
        client: replyWith(
          200,
          release(
            'v1.1.0',
            assets: [
              {
                'name': 'AttendanceTracker-android.apk',
                'browser_download_url': 'https://example.test/app.apk',
              },
              {
                'name': 'AttendanceTracker-macos.zip',
                'browser_download_url': 'https://example.test/app-macos.zip',
              },
            ],
          ),
        ),
      );
      await service.check();

      if (suffix == null) {
        expect(service.available!.downloadUrl, isNull);
      } else {
        expect(service.available!.assetName, endsWith(suffix));
      }
      // The release page is always available as a fallback.
      expect(service.available!.pageUrl, contains('releases'));
    });

    test('a release with no matching asset still offers the page', () async {
      final service = UpdateService(
        currentVersion: AppVersion.tryParse('1.0.0')!,
        client: replyWith(200, release('v1.1.0')),
      );
      await service.check();
      expect(service.available!.downloadUrl, isNull);
      expect(service.available!.pageUrl, isNotEmpty);
    });

    test('a skipped version stops nagging', () async {
      final service = UpdateService(
        currentVersion: AppVersion.tryParse('1.0.0')!,
        client: replyWith(200, release('v1.1.0')),
      );
      await service.check();
      expect(service.hasUpdate, isTrue);
      service.skip(service.available!.version);
      expect(service.hasUpdate, isFalse);
    });
  });

  group('failure is never fatal', () {
    test('no release published yet reads as up to date', () async {
      final service = UpdateService(
        currentVersion: AppVersion.tryParse('1.0.0')!,
        client: replyWith(404, {'message': 'Not Found'}),
      );
      await service.check();
      expect(service.state, UpdateState.upToDate);
      expect(service.hasUpdate, isFalse);
    });

    test('a rate limit explains itself', () async {
      final service = UpdateService(
        currentVersion: AppVersion.tryParse('1.0.0')!,
        client: replyWith(403, {'message': 'rate limited'}),
      );
      await service.check();
      expect(service.state, UpdateState.failed);
      expect(service.message, contains('rate limit'));
    });

    test('malformed json does not throw into the app', () async {
      final service = UpdateService(
        currentVersion: AppVersion.tryParse('1.0.0')!,
        client: replyWith(200, 'not json at all'),
      );
      await service.check();
      expect(service.state, UpdateState.failed);
      expect(service.message, isNotNull);
    });

    test('a release tagged with something unparseable is ignored', () async {
      final service = UpdateService(
        currentVersion: AppVersion.tryParse('1.0.0')!,
        client: replyWith(200, release('nightly-build')),
      );
      await service.check();
      expect(service.state, UpdateState.failed);
      expect(service.hasUpdate, isFalse);
    });

    test('a draft release is not offered', () async {
      final service = UpdateService(
        currentVersion: AppVersion.tryParse('1.0.0')!,
        client: replyWith(200, release('v9.9.9', draft: true)),
      );
      await service.check();
      expect(service.hasUpdate, isFalse);
    });

    test('a network error is reported, not thrown', () async {
      final service = UpdateService(
        currentVersion: AppVersion.tryParse('1.0.0')!,
        client: MockClient((_) async => throw const SocketExceptionStub()),
      );
      await service.check();
      expect(service.state, UpdateState.failed);
      expect(service.message, isNotNull);
    });
  });
}

/// Stands in for a real SocketException without needing dart:io in the test.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
