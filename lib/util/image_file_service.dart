import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

/// How long one artwork request may take to produce headers.
///
/// Covers the connect and the wait for the first byte, not the transfer, so a
/// slow link still finishes a large backdrop.
const _headerTimeout = Duration(seconds: 20);

/// How long a transfer already under way may go without delivering anything.
const _stallTimeout = Duration(seconds: 20);

/// Fetches artwork in a way that always gives its slot back.
///
/// The cache manager counts a fetch as running until this returns or throws,
/// and only then starts the next one. The stock service bounds neither the
/// request nor the transfer, so artwork that never arrives holds its slot for
/// the life of the process and every later image queues behind it.
class BoundedImageFileService extends FileService {
  BoundedImageFileService(
    this._client, {
    int? concurrentFetches,
    this.headerTimeout = _headerTimeout,
    this.stallTimeout = _stallTimeout,
  }) {
    if (concurrentFetches != null) this.concurrentFetches = concurrentFetches;
  }

  final http.Client _client;
  final Duration headerTimeout;
  final Duration stallTimeout;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      return await _send(url, headers);
    } on TimeoutException {
      // Already waited the full budget once, so asking again only doubles it.
      rethrow;
    } catch (_) {
      // A pooled connection the peer let go of fails here, and the failure
      // takes it out of the pool, so this one opens a fresh connection.
      // Artwork is only ever read, so asking twice changes nothing.
      return await _send(url, headers);
    }
  }

  Future<FileServiceResponse> _send(
    String url,
    Map<String, String>? headers,
  ) async {
    final request = http.Request('GET', Uri.parse(url));
    if (headers != null) request.headers.addAll(headers);
    final response = await _client.send(request).timeout(headerTimeout);
    return _StallBoundedResponse(HttpGetResponse(response), stallTimeout);
  }
}

/// Reports a transfer that has stopped delivering as an error rather than
/// leaving the read waiting on bytes that are not coming.
class _StallBoundedResponse implements FileServiceResponse {
  _StallBoundedResponse(this._inner, this._stall);

  final FileServiceResponse _inner;
  final Duration _stall;

  @override
  Stream<List<int>> get content => _inner.content.timeout(_stall);

  @override
  int? get contentLength => _inner.contentLength;

  @override
  int get statusCode => _inner.statusCode;

  @override
  DateTime get validTill => _inner.validTill;

  @override
  String? get eTag => _inner.eTag;

  @override
  String get fileExtension => _inner.fileExtension;
}
