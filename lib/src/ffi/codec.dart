// GlazeCodec — encode/decode BEVE-Lite binary payloads for flatpak types.
//
// Wire format (matches glaze_meta.h Writer/Reader):
//   Strings:    uint64 LE length + UTF-8 bytes
//   Arithmetic: raw LE bytes (sized by type)
//   Bool:       single byte (0 or 1)
//   Vector<T>:  uint64 LE count + N × element
//   Structs:    fields in glz::meta declaration order

import 'dart:convert';
import 'dart:typed_data';

import '../application.dart';
import '../remote.dart';

// ── Binary reader ──────────────────────────────────────────────────────────

class _BinaryReader {
  final ByteData _data;
  int _pos;

  _BinaryReader(Uint8List bytes, int offset)
      : _data = bytes.buffer.asByteData(bytes.offsetInBytes),
        _pos = offset;

  String readString() {
    final len = _data.getUint64(_pos, Endian.little);
    _pos += 8;
    final bytes = Uint8List.view(_data.buffer, _data.offsetInBytes + _pos, len);
    _pos += len;
    return utf8.decode(bytes);
  }

  int readUint32() {
    final v = _data.getUint32(_pos, Endian.little);
    _pos += 4;
    return v;
  }

  int readInt32() {
    final v = _data.getInt32(_pos, Endian.little);
    _pos += 4;
    return v;
  }

  int readInt8() {
    final v = _data.getInt8(_pos);
    _pos += 1;
    return v;
  }

  int readUint64() {
    final v = _data.getUint64(_pos, Endian.little);
    _pos += 8;
    return v;
  }

  bool readBool() {
    final v = _data.getUint8(_pos);
    _pos += 1;
    return v != 0;
  }

  Uint8List readByteVector() {
    final len = _data.getUint64(_pos, Endian.little);
    _pos += 8;
    final bytes = Uint8List.view(_data.buffer, _data.offsetInBytes + _pos, len);
    _pos += len;
    return Uint8List.fromList(bytes);
  }
}

// ── Binary writer ──────────────────────────────────────────────────────────

class _BinaryWriter {
  final _buf = BytesBuilder(copy: false);

  void writeString(String s) {
    final bytes = utf8.encode(s);
    final lenBuf = ByteData(8)..setUint64(0, bytes.length, Endian.little);
    _buf.add(lenBuf.buffer.asUint8List());
    _buf.add(bytes);
  }

  void writeInt32(int v) {
    final buf = ByteData(4)..setInt32(0, v, Endian.little);
    _buf.add(buf.buffer.asUint8List());
  }

  void writeInt8(int v) {
    _buf.addByte(v & 0xFF);
  }

  void writeByteVector(List<int> bytes) {
    final lenBuf = ByteData(8)..setUint64(0, bytes.length, Endian.little);
    _buf.add(lenBuf.buffer.asUint8List());
    _buf.add(bytes);
  }

  Uint8List toBytes() => _buf.toBytes();
}

// ── GlazeCodec ─────────────────────────────────────────────────────────────

abstract final class GlazeCodec {
  // ── FpRef (C++ field order): kind, name, arch, branch, commit, collectionId
  static FlatpakRef decodeFlatpakRef(Uint8List data, int offset) {
    final r = _BinaryReader(data, offset);
    return FlatpakRef(
      kind: r.readString(),
      name: r.readString(),
      arch: r.readString(),
      branch: r.readString(),
      commit: r.readString(),
      collectionId: r.readString(),
    );
  }

  // ── InstalledApp field order: ref(FpRef), origin, latestCommit,
  //    installedPath, installedSize(u64), isCurrentArch(bool),
  //    endOfLife(bool), endOfLifeRebase, appDataName, appDataSummary,
  //    appDataVersion, appDataIcon
  static FlatpakApplication decodeInstalledApp(Uint8List data, int offset) {
    final r = _BinaryReader(data, offset);
    // Inline FpRef fields (nested struct = fields in order)
    final ref = FlatpakRef(
      kind: r.readString(),
      name: r.readString(),
      arch: r.readString(),
      branch: r.readString(),
      commit: r.readString(),
      collectionId: r.readString(),
    );
    return FlatpakApplication(
      ref: ref,
      origin: r.readString(),
      latestCommit: r.readString(),
      installedPath: r.readString(),
      installedSize: r.readUint64(),
      isCurrentArch: r.readBool(),
      endOfLife: r.readBool(),
      endOfLifeRebase: r.readString(),
      appDataName: r.readString(),
      appDataSummary: r.readString(),
      appDataVersion: r.readString(),
      appDataIcon: r.readString(),
    );
  }

  // ── FlatpakRemoteInfo field order: name, url, title, comment, description,
  //    homepage, defaultBranch, subset, collectionId, filter,
  //    remoteType(i32), disabled(bool), gpgVerify(bool), noDeps(bool),
  //    priority(i32)
  static FlatpakRemote decodeFlatpakRemote(Uint8List data, int offset) {
    final r = _BinaryReader(data, offset);
    return FlatpakRemote(
      name: r.readString(),
      url: r.readString(),
      title: r.readString(),
      comment: r.readString(),
      description: r.readString(),
      homepage: r.readString(),
      defaultBranch: r.readString(),
      subset: RemoteSubset.fromApiValue(r.readString()),
      collectionId: r.readString(),
      filter: r.readString(),
      remoteType: _decodeRemoteType(r.readInt32()),
      disabled: r.readBool(),
      gpgVerify: r.readBool(),
      noDeps: r.readBool(),
      priority: r.readInt32(),
    );
  }

  // ── TransactionProgress field order: op, ref, progress(u32),
  //    bytesTransferred(u64), bytesTotal(u64), status
  static TransactionProgressData decodeTransactionProgress(
    Uint8List data,
    int offset,
  ) {
    final r = _BinaryReader(data, offset);
    return TransactionProgressData(
      op: r.readString(),
      ref: r.readString(),
      progressPercent: r.readUint32(),
      bytesTransferred: r.readUint64(),
      bytesTotal: r.readUint64(),
      status: r.readString(),
    );
  }

  /// Decode an error string from a 0x02 payload.
  /// Format: [0x02] [uint32 LE length] [UTF-8 bytes]
  static String decodeError(Uint8List data, int offset) {
    if (data.length < offset + 4) return 'unknown error';
    final lenBytes = data.buffer.asByteData(data.offsetInBytes);
    final len = lenBytes.getUint32(offset, Endian.little);
    final start = offset + 4;
    if (data.length < start + len) return 'truncated error';
    return utf8.decode(data.sublist(start, start + len));
  }

  // ── Remote metadata (permissions) — decoded from glaze Writer format:
  //    uint64 count, then count × (string section, string key, string value)
  static List<MetadataEntry> decodeRemoteMetadata(Uint8List data, int offset) {
    final r = _BinaryReader(data, offset);
    final count = r.readUint64();
    final entries = <MetadataEntry>[];
    for (var i = 0; i < count; i++) {
      entries.add(
        MetadataEntry(
          section: r.readString(),
          key: r.readString(),
          value: r.readString(),
        ),
      );
    }
    return entries;
  }

  // ── RemoteConfig encode (field order): url, title, comment, homepage,
  //    defaultBranch, gpgKeyData(vec<u8>), subset, collectionId, filter,
  //    priority(i32), gpgVerify(i8), disabled(i8), noDeps(i8)
  static Uint8List encodeRemoteConfig(FlatpakRemoteConfig config) {
    final w = _BinaryWriter();
    w.writeString(config.url ?? '');
    w.writeString(config.title ?? '');
    w.writeString(config.comment ?? '');
    w.writeString(config.homepage ?? '');
    w.writeString(config.defaultBranch ?? '');
    w.writeByteVector(config.gpgKeyData?.toList() ?? []);
    w.writeString(config.subset?.apiValue ?? '');
    w.writeString(config.collectionId ?? '');
    w.writeString(config.filter ?? '');
    w.writeInt32(config.priority ?? -1);
    w.writeInt8(config.gpgVerify == null ? -1 : (config.gpgVerify! ? 1 : 0));
    w.writeInt8(config.disabled == null ? -1 : (config.disabled! ? 1 : 0));
    w.writeInt8(config.noDeps == null ? -1 : (config.noDeps! ? 1 : 0));
    return w.toBytes();
  }

  static RemoteType _decodeRemoteType(int v) => switch (v) {
        1 => RemoteType.system,
        2 => RemoteType.static_,
        _ => RemoteType.user,
      };
}

/// Decoded transaction progress data.
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

/// A single entry from a Flatpak metadata keyfile.
class MetadataEntry {
  final String section;
  final String key;
  final String value;

  const MetadataEntry({
    required this.section,
    required this.key,
    required this.value,
  });

  @override
  String toString() => '[$section] $key=$value';
}
