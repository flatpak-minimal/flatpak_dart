// manage_remotes.dart — demonstrates the FlatpakRemoteManager API.
// Run as: dart run example/manage_remotes.dart

import 'package:flatpak_dart/flatpak_dart.dart';

Future<void> main() async {
  final client = FlatpakClient.user(); // user install, no polkit
  final remotes = client.remotes;

  // ── Step 1: list current remotes ─────────────────────────────────────
  print('\n=== Configured remotes ===');
  for (final r in await remotes.list()) {
    final subset = r.subset != RemoteSubset.none
        ? '  [${r.subset.apiValue}]'
        : '';
    final disabled = r.disabled ? '  [disabled]' : '';
    final static_ = r.isStatic ? '  [static]' : '';
    print('${r.name.padRight(28)} ${r.url}$subset$disabled$static_');
  }

  // ── Step 2: add Flathub if missing ────────────────────────────────────
  print('\n=== Adding flathub (--if-not-exists) ===');
  await remotes.add('flathub', KnownRemotes.flathub);
  print('flathub: OK');

  // ── Step 3: add FLOSS and beta subsets ────────────────────────────────
  print('\n=== Adding Flathub subsets ===');
  await remotes.add('flathub-floss', KnownRemotes.flathubFloss);
  await remotes.add('flathub-verified', KnownRemotes.flathubVerified);
  await remotes.add(
    'flathub-verified_floss',
    KnownRemotes.flathubVerifiedFloss,
  );
  await remotes.add('flathub-beta', KnownRemotes.flathubBeta);
  print('Added four Flathub variants.');

  // ── Step 4: tighten main flathub to verified ──────────────────────────
  print('\n=== Applying verified subset to flathub ===');
  await remotes.modifySubset('flathub', RemoteSubset.verified);
  final info = await remotes.info('flathub');
  print('flathub subset is now: ${info.subset.apiValue}');

  // ── Step 5: revert (uses delete+re-add workaround) ────────────────────
  print(
    '\n=== Removing subset (none / workaround for missing --subset=all) ===',
  );
  await remotes.modifySubset('flathub', RemoteSubset.none);
  print('flathub subset cleared.');

  // ── Step 6: OCI remote (Fedora) ───────────────────────────────────────
  print('\n=== Adding Fedora OCI remote ===');
  await remotes.add('fedora', KnownRemotes.fedora);
  print('fedora: OK  (oci+https:// scheme)');

  // ── Step 7: add GNOME nightly ─────────────────────────────────────────
  print('\n=== Adding GNOME nightly ===');
  await remotes.add('gnome-nightly', KnownRemotes.gnomeNightly);
  print('gnome-nightly: OK');

  // ── Step 8: browse first 10 apps in flathub ───────────────────────────
  print('\n=== First 10 app refs in flathub ===');
  var n = 0;
  await for (final ref in remotes.listApps('flathub')) {
    if (n++ >= 10) break;
    print('  ${ref.name}/${ref.arch}/${ref.branch}');
  }

  // ── Step 9: update remote summary ─────────────────────────────────────
  print('\n=== Updating flathub summary ===');
  await remotes.update('flathub');
  print('flathub summary: refreshed.');

  // ── Step 10: clean up beta and nightly ───────────────────────────────
  print('\n=== Removing beta and nightly remotes ===');
  await remotes.remove('flathub-beta', force: true);
  await remotes.remove('gnome-nightly', force: true);
  print('Removed.');

  await client.close();
}
