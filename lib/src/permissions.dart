/// A single permission override for a Flatpak application.
class FlatpakPermission {
  final String section;
  final String key;
  final String value;

  const FlatpakPermission({
    required this.section,
    required this.key,
    required this.value,
  });

  @override
  String toString() => 'FlatpakPermission($section.$key=$value)';
}
