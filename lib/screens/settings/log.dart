import 'dart:io';

import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:every_door/constants.dart';
import 'package:every_door/providers/osm_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:every_door/helpers/log_store.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class LogDisplayPage extends ConsumerStatefulWidget {
  const LogDisplayPage();

  @override
  ConsumerState<LogDisplayPage> createState() => _LogDisplayPageState();
}

class _LogDisplayPageState extends ConsumerState<LogDisplayPage> {
  static const kMaxLogLinesToSend = 20;

  /// The screen shows only messages this recent. Copy and share take all.
  static const kShownLogAge = Duration(minutes: 10);
  bool sentMessage = true; // TODO: fix sendmail on the server
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  void _copyAllLogsToClipboard() {
    final logText = logStore.lines.join('\n');
    Clipboard.setData(ClipboardData(text: logText));

    // Show a snackbar to provide user feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('All logs copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Saves the whole log to a text file and opens the share sheet, so it can
  /// be saved to Files / Drive or sent to a computer.
  Future<void> _shareLogFile() async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}';
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/everydoor-log-$stamp.txt');
    await file.writeAsString(logStore.lines.join('\n'), flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/plain')],
      subject: '$kAppTitle log $stamp',
    ));
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    final recent = logStore.newerThan(kShownLogAge);
    if (logStore.isEmpty) {
      body = Center(
        child: Text(
          'No system messages',
          style:
              TextStyle(fontStyle: FontStyle.italic, fontSize: kFieldFontSize),
        ),
      );
    } else if (recent.isEmpty) {
      body = Center(
        child: Text(
          'No messages in the last ${kShownLogAge.inMinutes} minutes.\n'
          'Copy or share to get the whole log.',
          textAlign: TextAlign.center,
          style:
              TextStyle(fontStyle: FontStyle.italic, fontSize: kFieldFontSize),
        ),
      );
    } else {
      body = SingleChildScrollView(
        controller: _controller,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: SelectableText(recent.join('\n')),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('System Log'),
        actions: [
          IconButton(
            icon: Icon(Icons.copy),
            tooltip: 'Copy All Logs',
            onPressed: logStore.isEmpty ? null : _copyAllLogsToClipboard,
          ),
          IconButton(
            icon: Icon(Icons.share),
            tooltip: 'Share Log File',
            onPressed: logStore.isEmpty ? null : _shareLogFile,
          ),
        ],
      ),
      body: body,
      floatingActionButton: sentMessage || logStore.isEmpty
          ? null
          : FloatingActionButton(
              child: Icon(Icons.send),
              onPressed: () async {
                final message = await showTextInputDialog(
                  context: context,
                  title: 'Send the report',
                  textFields: [
                    DialogTextField(maxLines: 2, hintText: 'Message to Ilya')
                  ],
                );
                if (message == null || message.isEmpty) return;

                String platform;
                if (Platform.isAndroid)
                  platform = 'Android';
                else if (Platform.isIOS)
                  platform = 'iOS';
                else
                  platform = 'unknown';

                http.post(
                  Uri.https('textual.ru', '/everydoor_send.php'),
                  body: <String, String>{
                    'code': 'rfJ7gnvut4%uHY6',
                    'version': '$kAppTitle $platform $kAppVersion',
                    'who': ref.read(authProvider)?.displayName ?? 'unknown',
                    'message': message.first,
                    'log': logStore.last(kMaxLogLinesToSend).join('\n'),
                  },
                );

                setState(() {
                  sentMessage = true;
                });
              },
            ),
    );
  }
}
