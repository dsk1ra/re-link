import 'package:flutter/material.dart';
import 'kv_row.dart';

class HandshakeCard extends StatelessWidget {
  final bool connected;
  final int? ttlRemaining;
  final String? createdRoomId;
  final String? createdRoomPassword;
  final String? createdInitiatorToken;
  final String? joinedInitiatorToken;
  final String? joinedReceiverToken;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;
  final TextEditingController roomIdController;
  final TextEditingController roomPasswordController;
  final VoidCallback onReset;

  const HandshakeCard({
    super.key,
    required this.connected,
    required this.ttlRemaining,
    required this.createdRoomId,
    required this.createdRoomPassword,
    required this.createdInitiatorToken,
    required this.joinedInitiatorToken,
    required this.joinedReceiverToken,
    required this.onCreateRoom,
    required this.onJoinRoom,
    required this.roomIdController,
    required this.roomPasswordController,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.vpn_key, size: 18),
                const SizedBox(width: 8),
                const Text('Private pairing', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                const SizedBox(width: 8),
                TextButton(onPressed: onReset, child: const Text('Reset')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('1) Create Room (initiator)'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: connected ? onCreateRoom : null,
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('Create Room'),
                          ),
                        ],
                      ),
                      if (createdRoomId != null) ...[
                        const SizedBox(height: 8),
                        KvRow('Room ID', createdRoomId!, copyable: true),
                      ],
                      if (createdRoomPassword != null)
                        KvRow('Password', createdRoomPassword!, copyable: true),
                      if (createdInitiatorToken != null)
                        KvRow('Your Token (initiator)', createdInitiatorToken!),
                      const SizedBox(height: 8),
                      const Text(
                        'Share Room ID and Password with receiver. Keep your token private.',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('2) Join Room (receiver)'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: roomIdController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Room ID',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: roomPasswordController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Password',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ElevatedButton.icon(
                          onPressed: connected ? onJoinRoom : null,
                          icon: const Icon(Icons.login),
                          label: const Text('Join Room'),
                        ),
                      ),
                      if (joinedInitiatorToken != null)
                        KvRow('Initiator Token', joinedInitiatorToken!),
                      if (joinedReceiverToken != null)
                        KvRow('Your Token (receiver)', joinedReceiverToken!),
                      if (joinedInitiatorToken != null || joinedReceiverToken != null) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Use the tokens to mutually verify during P2P connection. The server is now out of the loop.',
                          style: TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
