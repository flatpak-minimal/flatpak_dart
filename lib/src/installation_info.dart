/// A configured Flatpak installation (`flatpak_get_system_installations()`).
class FlatpakInstallationInfo {
  final String id;
  final String displayName;
  final String path;
  final bool isUser;
  final int priority;

  const FlatpakInstallationInfo({
    required this.id,
    this.displayName = '',
    this.path = '',
    this.isUser = false,
    this.priority = 0,
  });

  @override
  String toString() =>
      'FlatpakInstallationInfo($id, path=$path, isUser=$isUser, priority=$priority)';
}
