import 'package:flutter/material.dart';
import 'kv_row.dart';

class RoomInfo extends StatelessWidget {
  final bool roleIsInitiator;
  final String? roomId;
  final int? ttlRemaining;
  final String? initiatorToken;
  final String? receiverToken;
  final String? password;
  final bool connected;
  final VoidCallback onReset;

  const RoomInfo({
    super.key,
    required this.roleIsInitiator,
    required this.roomId,
    required this.ttlRemaining,
    required this.initiatorToken,
    required this.receiverToken,
    required this.password,
    required this.connected,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link, size: 18),
                const SizedBox(width: 8),
                Text('Connected as ${roleIsInitiator ? 'Initiator' : 'Receiver'}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (connected || (roleIsInitiator && ttlRemaining != null))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      connected
                          ? 'Connected'
                          : (ttlRemaining! <= 0
                              ? 'Expired'
                              : 'Expires in ${ttlRemaining!.clamp(0, 999)}s'),
                      style: TextStyle(
                        color: connected
                            ? Colors.green
                            : (ttlRemaining! <= 0 ? Colors.red : null),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                TextButton(onPressed: onReset, child: const Text('Start over')),
              ],
            ),
            const SizedBox(height: 8),
            if (roomId != null) KvRow('Room ID', roomId!, copyable: true),
            if (roleIsInitiator && password != null) KvRow('Password', password!, copyable: true),
            if (initiatorToken != null)
              KvRow(roleIsInitiator ? 'Your Token (initiator)' : 'Initiator Token', initiatorToken!),
            if (!roleIsInitiator && receiverToken != null)
              KvRow('Your Token (receiver)', receiverToken!),
            const SizedBox(height: 8),
            const Text(
              'Use these tokens to verify each other over your P2P channel. The server is out of the loop after pairing.',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            )
          ],
        ),
      ),
    );
  }
}
