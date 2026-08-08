/// Disk usage of the filesystem backing a Flatpak installation.
class StorageInfo {
  final int totalBytes;
  final int availableBytes;

  const StorageInfo({required this.totalBytes, required this.availableBytes});

  int get usedBytes => totalBytes - availableBytes;

  @override
  String toString() =>
      'StorageInfo(total=$totalBytes, available=$availableBytes)';
}
