// GlazeCodec — encode/decode glaze binary payloads for flatpak types.

import 'dart:convert';
import 'dart:typed_data';

import '../application.dart';
import '../remote.dart';
import 'types.dart' as ffi_types;

abstract final class GlazeCodec {
  /// Decode a TransactionProgress from a glaze binary payload starting at
  /// [offset] within [data].
  static TransactionProgressData decodeTransactionProgress(
      Uint8List data, int offset) {
    final json = _decodeJson(data, offset);
    return TransactionProgressData(
      op: json['op'] as String? ?? '',
      ref: json['ref'] as String? ?? '',
      progressPercent: json['progress'] as int? ?? 0,
      bytesTransferred: json['bytesTransferred'] as int? ?? 0,
      bytesTotal: json['bytesTotal'] as int? ?? 0,
      status: json['status'] as String? ?? '',
    );
  }

  /// Decode an error string from a 0x02 payload.
  static String decodeError(Uint8List data, int offset) {
    if (data.length < offset + 4) return 'unknown error';
    final lenBytes = data.buffer.asByteData();
    final len = lenBytes.getUint32(offset, Endian.little);
    final start = offset + 4;
    if (data.length < start + len) return 'truncated error';
    return utf8.decode(data.sublist(start, start + len));
  }

  /// Decode a FlatpakRef from a glaze binary payload.
  static FlatpakRef decodeFlatpakRef(Uint8List data, int offset) {
    final json = _decodeJson(data, offset);
    return ffi_types.decodeFlatpakRef(json);
  }

  /// Decode an InstalledApp from a glaze binary payload.
  static FlatpakApplication decodeInstalledApp(Uint8List data, int offset) {
    final json = _decodeJson(data, offset);
    return ffi_types.decodeInstalledApp(json);
  }

  /// Decode a FlatpakRemote from a glaze binary payload.
  static FlatpakRemote decodeFlatpakRemote(Uint8List data, int offset) {
    final json = _decodeJson(data, offset);
    return ffi_types.decodeFlatpakRemote(json);
  }

  /// Encode a FlatpakRemoteConfig to glaze binary for the C bridge.
  static Uint8List encodeRemoteConfig(FlatpakRemoteConfig config) {
    final map = <String, dynamic>{};
    if (config.url != null) map['url'] = config.url;
    if (config.title != null) map['title'] = config.title;
    if (config.comment != null) map['comment'] = config.comment;
    if (config.homepage != null) map['homepage'] = config.homepage;
    if (config.defaultBranch != null) {
      map['defaultBranch'] = config.defaultBranch;
    }
    if (config.subset != null) map['subset'] = config.subset!.apiValue;
    if (config.collectionId != null) map['collectionId'] = config.collectionId;
    if (config.filter != null) map['filter'] = config.filter;
    if (config.gpgKeyData != null) {
      map['gpgKeyData'] = config.gpgKeyData!.toList();
    }
    map['priority'] = config.priority ?? -1;
    map['gpgVerify'] = config.gpgVerify == null
        ? -1
        : config.gpgVerify!
            ? 1
            : 0;
    map['disabled'] = config.disabled == null
        ? -1
        : config.disabled!
            ? 1
            : 0;
    map['noDeps'] = config.noDeps == null
        ? -1
        : config.noDeps!
            ? 1
            : 0;
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  static Map<String, dynamic> _decodeJson(Uint8List data, int offset) {
    final payload = data.sublist(offset);
    final str = utf8.decode(payload);
    return jsonDecode(str) as Map<String, dynamic>;
  }
}

/// Decoded transaction progress data (used internally before constructing
/// the public TransactionProgress).
class TransactionProgressData {
  final String op;
  final String ref;
  final int progressPercent;
  final int bytesTransferred;
  final int bytesTotal;
  final String status;

  const TransactionProgressData({
    required this.op,
    required this.ref,
    required this.progressPercent,
    required this.bytesTransferred,
    required this.bytesTotal,
    required this.status,
  });
}
