import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';
import 'package:test/test.dart';

void main() {
  group('configureServerDio', () {
    late HttpServer server;
    StreamSubscription<HttpRequest>? requests;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });

    tearDown(() async {
      await requests?.cancel();
      await server.close(force: true);
      // The version is process-wide, so clear it to keep tests independent.
      setServerUserAgentVersion('');
    });

    // Answers one request and reports the user agent it arrived with.
    Future<String?> userAgentOfNextRequest() async {
      final received = Completer<String?>();
      requests = server.listen((request) async {
        if (!received.isCompleted) {
          received.complete(request.headers.value(HttpHeaders.userAgentHeader));
        }
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });

      final dio = Dio();
      configureServerDio(dio);

      try {
        await dio.get<void>('http://127.0.0.1:${server.port}/');
        return await received.future;
      } finally {
        dio.close(force: true);
      }
    }

    test('uses a browser-compatible Moonfin user agent', () async {
      expect(
        await userAgentOfNextRequest(),
        'Mozilla/5.0 (compatible; Moonfin/Flutter)',
      );
    });

    test('includes the app version once startup records it', () async {
      setServerUserAgentVersion('2.3.2');

      expect(
        await userAgentOfNextRequest(),
        'Mozilla/5.0 (compatible; Moonfin/2.3.2)',
      );
    });

    test('truncates at anything that would break the header', () async {
      setServerUserAgentVersion('2.3.2 (beta)\r\nX-Injected: 1');

      expect(
        await userAgentOfNextRequest(),
        'Mozilla/5.0 (compatible; Moonfin/2.3.2)',
      );
    });

    test('falls back to an unversioned agent for a blank version', () async {
      setServerUserAgentVersion('   ');

      expect(
        await userAgentOfNextRequest(),
        'Mozilla/5.0 (compatible; Moonfin/Flutter)',
      );
    });
  });

  // A screen that asks for more at once than the slots hold has to queue, and
  // none of that wait may count against the connect timeout.
  group('slot limited requests', () {
    late HttpServer server;
    const slowResponse = Duration(milliseconds: 300);
    const moreRequestsThanSlots = 60;
    var inFlight = 0;
    var mostInFlight = 0;
    var failEveryRequest = false;

    setUp(() async {
      inFlight = 0;
      mostInFlight = 0;
      failEveryRequest = false;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        inFlight++;
        if (inFlight > mostInFlight) mostInFlight = inFlight;
        await Future<void>.delayed(slowResponse);
        inFlight--;
        request.response.statusCode = failEveryRequest
            ? HttpStatus.internalServerError
            : HttpStatus.ok;
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Dio dioWith(Duration connectTimeout) {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'http://${server.address.address}:${server.port}',
          connectTimeout: connectTimeout,
        ),
      );
      configureServerDio(dio);
      return dio;
    }

    Future<List<Object?>> fireConcurrently(Dio dio) => Future.wait(
      List.generate(
        moreRequestsThanSlots,
        (i) => dio
            .get<void>('/$i')
            .then<Object?>((r) => r)
            .catchError((Object e) => e),
      ),
    );

    test('queueing is never billed to the connect timeout', () async {
      final results = await fireConcurrently(
        dioWith(const Duration(milliseconds: 400)),
      );
      expect(results.whereType<DioException>(), isEmpty);
    });

    test('holds the rest back once the slots are taken', () async {
      await fireConcurrently(dioWith(const Duration(seconds: 30)));
      // A browser allows itself six per host without multiplexing, and going
      // past that is what a proxy reads as a flood.
      expect(mostInFlight, lessThanOrEqualTo(6));
      expect(mostInFlight, greaterThan(1));
    });

    test('hands a slot back when the request fails', () async {
      final dio = dioWith(const Duration(seconds: 30));
      failEveryRequest = true;
      final failed = await fireConcurrently(dio);
      expect(
        failed.whereType<DioException>(),
        hasLength(moreRequestsThanSlots),
      );

      failEveryRequest = false;
      final response = await dio
          .get<void>('/after')
          .timeout(const Duration(seconds: 5));
      expect(response.statusCode, HttpStatus.ok);
    });
  });

  group('the pool idle timeout', () {
    late HttpServer server;
    late Set<int> connections;

    setUp(() async {
      connections = <int>{};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        // One remote port is one connection, so counting them counts reuse.
        connections.add(request.connectionInfo!.remotePort);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Future<void> twoRequests(Duration idleTimeout, Duration apart) async {
      final dio = Dio(
        BaseOptions(baseUrl: 'http://${server.address.address}:${server.port}'),
      );
      configureServerDio(dio, idleTimeout: idleTimeout);
      addTearDown(() => dio.close(force: true));

      await dio.get<void>('/one');
      await Future<void>.delayed(apart);
      await dio.get<void>('/two');
    }

    test('keeps a connection for a caller that comes straight back', () async {
      await twoRequests(
        const Duration(seconds: 10),
        const Duration(milliseconds: 50),
      );

      expect(connections, hasLength(1));
    });

    test('drops it once the caller has been away for longer', () async {
      await twoRequests(
        const Duration(milliseconds: 100),
        const Duration(milliseconds: 400),
      );

      expect(connections, hasLength(2));
    });
  });

  // A slot frees when the headers land, but dart:io keeps the connection until
  // the body has drained, so the pool has to be roomier than the slots.
  group('a body still draining', () {
    late HttpServer server;
    const bodyDelay = Duration(milliseconds: 1500);

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        // Headers straight away, body much later, which is the shape that
        // leaves a connection busy long after its slot went back.
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write(
          'HTTP/1.1 200 OK\r\n'
          'Content-Type: application/json\r\n'
          'Content-Length: 8\r\n'
          '\r\n',
        );
        await socket.flush();
        await Future<void>.delayed(bodyDelay);
        socket.write('{"ok":1}');
        await socket.flush();
        socket.destroy();
      });
    });

    tearDown(() => server.close(force: true));

    test('does not park the next request in the dart:io queue', () async {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'http://${server.address.address}:${server.port}',
          // Short on purpose. Anything parked in the queue inside dart:io is
          // billed to this, which is what made a busy screen read as a
          // connection timeout.
          connectTimeout: const Duration(milliseconds: 400),
        ),
      );
      configureServerDio(dio);
      addTearDown(() => dio.close(force: true));

      final results = await Future.wait(
        List.generate(
          12,
          (i) => dio
              .get<dynamic>('/$i')
              .then<Object?>((r) => r)
              .catchError((Object e) => e),
        ),
      );

      expect(results.whereType<DioException>(), isEmpty);
    });
  });

  // dart:io hands out a pooled connection without checking it is still open,
  // and one the peer already dropped only fails once TCP gives up.
  group('a pooled connection that died', () {
    final retries = <String>[];
    var handled = 0;

    setUp(() {
      retries.clear();
      handled = 0;
      ServerLog.sink = (category, level, message, {error}) {
        if (message.startsWith('Connection died')) retries.add(message);
      };
    });

    tearDown(() => ServerLog.sink = null);

    // Reads the request and drops the socket without writing anything back,
    // which is what a connection the peer let go of looks like.
    Future<HttpServer> serverKilling(int firstRequests) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        handled++;
        if (handled <= firstRequests) {
          final socket = await request.response.detachSocket();
          socket.destroy();
          return;
        }
        request.response.write('{"ok":true}');
        await request.response.close();
      });
      return server;
    }

    Dio dioFor(HttpServer server) {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'http://${server.address.address}:${server.port}',
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      configureServerDio(dio);
      return dio;
    }

    test('a GET is asked for again and the caller never sees it', () async {
      final dio = dioFor(await serverKilling(1));
      addTearDown(() => dio.close(force: true));

      final response = await dio.get<dynamic>('/Users/Me');

      expect(response.statusCode, HttpStatus.ok);
      expect(handled, 2);
      expect(retries, hasLength(1));
    });

    test('a POST is left alone so the server never runs it twice', () async {
      final dio = dioFor(await serverKilling(1));
      addTearDown(() => dio.close(force: true));

      await expectLater(
        dio.post<dynamic>('/Sessions/Capabilities/Full', data: {'a': 1}),
        throwsA(isA<DioException>()),
      );
      expect(handled, 1);
    });

    test('a second death in a row gives up instead of looping', () async {
      final dio = dioFor(await serverKilling(9));
      addTearDown(() => dio.close(force: true));

      await expectLater(
        dio.get<dynamic>('/Users/Me'),
        throwsA(isA<DioException>()),
      );
      expect(handled, 2);
    });

    test('a host that refuses is not asked twice', () async {
      // Nothing answered, so there is no dead connection to shake off and a
      // second attempt only doubles the wait in front of the offline banner.
      final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close(force: true);

      final dio = Dio(
        BaseOptions(
          baseUrl: 'http://127.0.0.1:$port',
          connectTimeout: const Duration(seconds: 5),
        ),
      );
      configureServerDio(dio);
      addTearDown(() => dio.close(force: true));

      await expectLater(
        dio.get<dynamic>('/Users/Me'),
        throwsA(isA<DioException>()),
      );
      expect(retries, isEmpty);
    });

    test('a body that already started is never asked for again', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        handled++;
        // Written by hand because detachSocket refuses once the headers have
        // gone out, and this needs them out before the socket dies.
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write(
          'HTTP/1.1 200 OK\r\n'
          'Content-Type: application/json\r\n'
          'Content-Length: 4096\r\n'
          '\r\n'
          'only a little',
        );
        await socket.flush();
        socket.destroy();
      });

      final dio = dioFor(server);
      addTearDown(() => dio.close(force: true));

      await expectLater(dio.get<dynamic>('/big'), throwsA(isA<DioException>()));
      // Headers were out, so the server did work the retry must not repeat.
      expect(handled, 1);
    });
  });
}
