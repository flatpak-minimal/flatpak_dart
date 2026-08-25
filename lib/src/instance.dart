class FlatpakInstance {
  /// The application id, e.g. `org.gnome.Calculator`.
  final String appId;

  /// The unique instance id assigned by flatpak for this run.
  final String instanceId;

  final String arch;
  final String branch;
  final String commit;

  /// The outermost (bubblewrap) process pid.
  final int pid;

  /// The application process pid inside the sandbox.
  ///
  /// `0` if it could not be determined — libflatpak does not have it yet at
  /// the moment a launch returns, so a launched instance carries it only if
  /// bwrap published it while the native side waited. Instances from a listing
  /// always carry the real value.
  final int childPid;

  /// Whether the instance is still running.
  final bool isRunning;

  const FlatpakInstance({
    required this.appId,
    required this.instanceId,
    this.arch = '',
    this.branch = '',
    this.commit = '',
    this.pid = 0,
    this.childPid = 0,
    this.isRunning = false,
  });

  @override
  String toString() =>
      'FlatpakInstance($appId, instance=$instanceId, pid=$pid, running=$isRunning)';
}
