import 'package:material_ui/material_ui.dart';
import 'security.dart';

class DriveSetup extends StatefulWidget {
  const DriveSetup(this.cloud, {super.key});
  final Backups cloud;
  @override
  State<DriveSetup> createState() => _DriveSetupState();
}

class _DriveSetupState extends State<DriveSetup> {
  final password = TextEditingController(), repeat = TextEditingController();
  bool busy = false, checked = false;
  String? error, latestId, latestName;
  Backups get cloud => widget.cloud;
  @override
  void dispose() {
    password.dispose();
    repeat.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'Could not connect or read Drive. Check internet, Google permissions, and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> check() async {
    final files = await cloud.list();
    if (!mounted) return;
    setState(() {
      checked = true;
      latestId = files.firstOrNull?.id;
      latestName = files.firstOrNull?.name;
    });
  }

  Future<void> finish({required bool restore}) async {
    if (password.text.length < 10) {
      throw const FormatException(
        'Use a passphrase of at least 10 characters.',
      );
    }
    if (password.text != repeat.text) {
      throw const FormatException('Passphrases do not match.');
    }
    if (restore) {
      final data = await cloud.read(latestId!, password.text);
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore your Drive backup?'),
          content: const Text(
            'This replaces financial records currently on this device. The backup has been authenticated with your passphrase.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (yes != true) return;
      await cloud.store.restore(data);
    } else if (latestId != null) {
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Continue with this device’s data?'),
          content: const Text(
            'Your existing Drive backups will be kept. New changes from this device will create new backups. Records from other devices will not be merged.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    await cloud.configure(password.text);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.cloud_done_outlined,
                  size: 60,
                  color: Color(0xFF26755D),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Your money, safely backed up.',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Connect Google to get started. SpendNote saves encrypted backups to your private app storage in Google Drive. After setup, you can track offline; pending changes upload while the app is open and connected.',
                ),
                const SizedBox(height: 24),
                if (!cloud.connected)
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            await cloud.connect();
                            await check();
                          }),
                    icon: const Icon(Icons.account_circle_outlined),
                    label: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Continue with Google'),
                    ),
                  )
                else ...[
                  Text(
                    cloud.email!,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  if (!checked)
                    OutlinedButton(
                      onPressed: busy ? null : () => run(check),
                      child: const Text('Check for existing backups'),
                    )
                  else ...[
                    Text(
                      latestId == null
                          ? 'Set a recovery passphrase'
                          : 'Existing backup found: $latestName',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Keep this passphrase somewhere safe. It is saved securely on this device for automatic backups, and required to restore after reinstalling or on a new phone.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Recovery passphrase (10+ characters)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: repeat,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm passphrase',
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (latestId != null)
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => run(() => finish(restore: true)),
                        child: const Text('Restore latest backup & continue'),
                      ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => run(() => finish(restore: false)),
                      child: Text(
                        latestId == null
                            ? 'Enable automatic backup'
                            : 'Continue with local data',
                      ),
                    ),
                  ],
                ],
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
