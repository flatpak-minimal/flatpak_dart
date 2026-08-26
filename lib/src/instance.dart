class FlatpakInstance {
  /// The application id, e.g. `org.gnome.Calculator`.
  final String appId;

  /// The unique instance id assigned by flatpak for this run.
  final String instanceId;

  final String arch;
  final String branch;
  final String commit;

  /// Full runtime ref this instance runs against, as libflatpak reports it —
  /// `runtime/org.freedesktop.Platform/x86_64/25.08`. Empty when unknown.
  ///
  /// For an instance with no [appId] this is the only thing that identifies
  /// it: `flatpak run` on a runtime rather than an app — a `--command=sh`
  /// shell, `flatpak-builder --run` — produces an instance whose application
  /// id is genuinely empty, and its runtime ref is what it actually is.
  final String runtime;

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
    this.runtime = '',
    this.pid = 0,
    this.childPid = 0,
    this.isRunning = false,
  });

  /// Whether this is a runtime instance rather than an application — `flatpak
  /// run` on a runtime produces one, and it has no application id.
  bool get isRuntimeOnly => appId.isEmpty && runtime.isNotEmpty;

  @override
  String toString() =>
      'FlatpakInstance(${appId.isEmpty ? runtime : appId}, '
      'instance=$instanceId, pid=$pid, running=$isRunning)';
}
