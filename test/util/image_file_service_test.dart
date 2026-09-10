import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:moonfin/util/image_file_service.dart';
import 'package:moonfin/util/tv_image_cache_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;

  setUp(() async {
    // The test binding answers every request itself, and these need loopback.
    HttpOverrides.global = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() => server.close(force: true));

  String base() => 'http://127.0.0.1:${server.port}';

  const slots = 4;
  BoundedImageFileService boundedService() => BoundedImageFileService(
    http.Client(),
    concurrentFetches: slots,
    headerTimeout: const Duration(milliseconds: 400),
    stallTimeout: const Duration(milliseconds: 400),
  );

  void answerNormally(HttpRequest request) {
    request.response.headers.contentType = ContentType('image', 'jpeg');
    request.response.add(List<int>.filled(32, 0x41));
    request.response.close();
  }

  group('a request that never answers', () {
    test('gives up instead of waiting forever', () async {
      server.listen((request) {});

      await expectLater(
        boundedService().get('${base()}/never'),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('is not asked for a second time', () async {
      var seen = 0;
      server.listen((request) => seen++);

      await expectLater(
        boundedService().get('${base()}/never'),
        throwsA(isA<TimeoutException>()),
      );
      // Waiting the whole budget twice is worse than reporting it once.
      expect(seen, 1);
    });
  });

  group('a connection that died before answering', () {
    test('is asked for again on a fresh one', () async {
      var seen = 0;
      server.listen((request) async {
        seen++;
        if (seen == 1) {
          // No bytes at all, which is what a connection the peer let go of
          // looks like. Letting the headers out first would be a live server
          // that failed mid transfer instead.
          (await request.response.detachSocket(writeHeaders: false)).destroy();
          return;
        }
        answerNormally(request);
      });

      final response = await boundedService().get('${base()}/poster');

      expect(response.statusCode, HttpStatus.ok);
      expect(seen, 2);
    });

    test('gives up after the second death rather than looping', () async {
      var seen = 0;
      server.listen((request) async {
        seen++;
        (await request.response.detachSocket(writeHeaders: false)).destroy();
      });

      // Not a timeout, or the second attempt never went out.
      await expectLater(
        boundedService().get('${base()}/poster'),
        throwsA(isNot(isA<TimeoutException>())),
      );
      expect(seen, 2);
    });
  });

  test('a transfer that stops part way through is reported', () async {
    server.listen((request) async {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.write(
        'HTTP/1.1 200 OK\r\n'
        'Content-Type: image/jpeg\r\n'
        'Content-Length: 4096\r\n'
        '\r\n'
        'only a little',
      );
      await socket.flush();
      // Headers and part of the body are out, then it stops delivering.
    });

    final response = await boundedService().get('${base()}/big');

    await expectLater(response.content, emitsThrough(emitsError(anything)));
  });

  // Artwork that never arrived used to hold its slot for the life of the
  // process, so every later image queued behind it and nothing short of
  // restarting the app brought pictures back.
  test(
    'a full set of stuck fetches still lets a later image through',
    () async {
      var seen = 0;
      server.listen((request) {
        seen++;
        // The first batch takes every slot and never answers.
        if (seen <= slots) return;
        answerNormally(request);
      });

      final manager = CacheManager(
        Config(
          'wedge-probe',
          stalePeriod: const Duration(days: 1),
          repo: NonStoringObjectProvider(),
          fileSystem: MemoryCacheSystem(),
          fileService: boundedService(),
        ),
      );

      for (var i = 0; i < slots; i++) {
        manager
            .getFileStream('${base()}/stuck$i')
            .listen((_) {}, onError: (_) {});
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final arrived = Completer<bool>();
      manager
          .getFileStream('${base()}/wanted')
          .listen(
            (_) {
              if (!arrived.isCompleted) arrived.complete(true);
            },
            onError: (_) {
              if (!arrived.isCompleted) arrived.complete(false);
            },
          );

      expect(
        await arrived.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        ),
        isTrue,
      );
    },
  );

  // Anything admitted past the connections the client will open waits in a
  // queue inside dart:io that nothing times out, which is the wedge this whole
  // service exists to avoid.
  test('never admits more artwork at once than it will connect', () {
    expect(
      buildImageFileService().concurrentFetches,
      lessThanOrEqualTo(buildImageHttpClient().maxConnectionsPerHost!),
    );
  });
}
