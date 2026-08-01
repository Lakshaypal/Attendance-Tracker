import 'package:flutter/material.dart';

import '../store.dart';
import '../sync.dart';
import 'design.dart';

class SyncPage extends StatefulWidget {
  const SyncPage({super.key, required this.store});

  final AttendanceStore store;

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final TextEditingController _address = TextEditingController();
  final TextEditingController _code = TextEditingController();

  List<String> _hostAddresses = const [];
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  void _report(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = isError;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      _report(_friendly(error), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _friendly(Object error) => switch (error) {
    FormatException(:final message) => message,
    _ => '$error',
  };

  Future<void> _startHost() => _run(() async {
    final addresses = await LocalSyncHost.start(widget.store);
    if (!mounted) return;
    setState(() => _hostAddresses = addresses);
    _report(
      addresses.isEmpty
          ? 'Pairing is on, but no Wi-Fi address was found. Check the network.'
          : 'Pairing is on. Keep this screen open while you transfer.',
    );
  });

  Future<void> _stopHost() async {
    await LocalSyncHost.stop();
    if (!mounted) return;
    setState(() => _hostAddresses = const []);
    _report('Pairing stopped.');
  }

  Future<void> _receive() async {
    final ok = await confirm(
      context,
      title: 'Replace this device\'s data?',
      message:
          'Everything on this device is overwritten with the data from the '
          'paired device.',
      confirmLabel: 'Get data',
    );
    if (!ok || !mounted) return;
    await _run(() async {
      final data = await LocalSyncClient.receive(
        address: _address.text,
        code: _code.text,
      );
      widget.store.applySnapshot(data);
      await widget.store.flush();
      _report('Attendance data received.');
    });
  }

  Future<void> _send() async {
    final ok = await confirm(
      context,
      title: 'Replace the other device\'s data?',
      message:
          'Everything on the paired device is overwritten with the data from '
          'this device.',
      confirmLabel: 'Send data',
    );
    if (!ok || !mounted) return;
    await _run(() async {
      await LocalSyncClient.send(
        address: _address.text,
        code: _code.text,
        data: widget.store.snapshot,
      );
      _report('Attendance data sent.');
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sync devices')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1 · Host on one device',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Start pairing here, then type the address and code on the '
                  'other device.',
                ),
                const SizedBox(height: 14),
                if (!LocalSyncHost.isRunning)
                  FilledButton.icon(
                    onPressed: _busy ? null : _startHost,
                    icon: const Icon(Icons.wifi_tethering_rounded),
                    label: const Text('Start pairing'),
                  )
                else ...[
                  SelectableText(
                    'Code  ${LocalSyncHost.pairCode}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    _hostAddresses.isEmpty
                        ? 'Looking for a local address…'
                        : _hostAddresses
                              .map((item) => '$item:${LocalSyncHost.port}')
                              .join('   or   '),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _stopHost,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop pairing'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '2 · Connect from the other device',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _address,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Device address',
                    hintText: '192.168.1.24:45454',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Six-digit pairing code',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _receive,
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Get data'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _send,
                        icon: const Icon(Icons.upload_rounded, size: 18),
                        label: const Text('Send data'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_message != null) ...[
          const SizedBox(height: 14),
          InfoNote(
            text: _message!,
            icon: _messageIsError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            tone: _messageIsError
                ? Theme.of(context).colorScheme.error
                : const Color(0xFF18865A),
          ),
        ],
        const SizedBox(height: 14),
        const InfoNote(
          text:
              'Both devices must be on the same Wi-Fi. A transfer replaces the '
              'receiving device entirely, so start from whichever device has '
              'the newer records.',
        ),
      ],
    ),
  );
}
