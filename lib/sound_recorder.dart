import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:vrecorder/message.dart';
import 'package:vrecorder/message_list.dart';
import 'package:vrecorder/util-functions.dart';
import "audiowaveform_response.dart";

/*
 * This is an example showing how to record to a Dart Stream.
 * It writes all the recorded data from a Stream to a File, which is completely stupid:
 * if an App wants to record something to a File, it must not use Streams.
 *
 * The real interest of recording to a Stream is for example to feed a
 * Speech-to-Text engine, or for processing the Live data in Dart in real time.
 *
 */

///'
enum QuestionType { item, quantity, other }

const int tSampleRate = 16000;
typedef _Fn = void Function();

/// Example app.
class RecordToStreamExample extends StatefulWidget {
  final ScrollController scrollController;
  const RecordToStreamExample({
    super.key,
    required this.scrollController,
  });

  @override
  _RecordToStreamExampleState createState() => _RecordToStreamExampleState();
}

class _RecordToStreamExampleState extends State<RecordToStreamExample> {
  final QuestionType _qMode = QuestionType.quantity;
  FlutterSoundPlayer? _mPlayer = FlutterSoundPlayer();
  FlutterSoundRecorder? _mRecorder = FlutterSoundRecorder();
  bool _mPlayerIsInited = false;
  bool _mRecorderIsInited = false;
  bool _mplaybackReady = false;
  String? _mPath;
  String? filename;
  StreamSubscription? _mRecordingDataSubscription;
  List<Map<String, String>> questions = [
    {
      "question": "Which item do you prefer?",
      "type": "item",
    },
    {
      "question": "How many items do you want?",
      "type": "quantity",
    },
    {
      "question": "What else do you want?",
      "type": "other",
    },
  ];

  int questionIndex = 0;

  scrollToBottom(ScrollController scrollController, {double value = 0.0}) {
    scrollController.animateTo(
      scrollController.position.maxScrollExtent + 70 + value,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openRecorder() async {
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw RecordingPermissionException('Microphone permission not granted');
    }
    await _mRecorder!.openRecorder();

    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));

    setState(() {
      _mRecorderIsInited = true;
    });
  }

  @override
  void initState() {
    super.initState();
    // Be careful : openAudioSession return a Future.
    // Do not access your FlutterSoundPlayer or FlutterSoundRecorder before the completion of the Future
    _mPlayer!.openPlayer().then((value) {
      setState(() {
        _mPlayerIsInited = true;
      });
    });
    _openRecorder();
  }

  @override
  void dispose() {
    _mPlayer!.closePlayer();
    _mPlayer = null;

    stopRecorder();
    _mRecorder!.closeRecorder();
    _mRecorder = null;
    super.dispose();
  }

  Future<String> createFile() async {
    var tempDir = await getExternalStorageDirectory();
    var timestamp = '${DateTime.now().millisecondsSinceEpoch}.wav';
    setState(() {
      filename = timestamp;
      _mPath = '${tempDir!.path}/$timestamp';
    });
    return _mPath!;
  }

  Future<void> record() async {
    assert(_mRecorderIsInited && _mPlayer!.isStopped);
    var fileName = await createFile();

    await _mRecorder!.startRecorder(
      toFile: fileName,
      codec: Codec.pcm16WAV,
      numChannels: 1,
      sampleRate: tSampleRate,
    );
    setState(() {});
  }

  void addBotMessage(int index) {
    Provider.of<MessageList>(context, listen: false).addMessage(
      Message(
        message: questions[index]["question"]!,
        sender: "bot",
      ),
    );
    scrollToBottom(widget.scrollController);

    return;
  }

  sendRequest(String audioPath) async {
    var postUri = Uri.parse("https://9695-14-139-207-163.ngrok.io/audiowave");
    var request = http.MultipartRequest("POST", postUri);
    try {
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        audioPath,
        contentType: MediaType('audio', 'mp3'),
      ));

      print('Porcessing!');
      final response = await request.send();

      if (response.statusCode == 201) {
        print("Request Sent!");
        final respStr = await response.stream.bytesToString();
        AudiowaveFormResponse audiowaveFormResponse =
            audiowaveFormResponseFromJson(respStr);

        var res = calculateResult(audiowaveFormResponse.data);
        var item = findAns(res, questionIndex);
        final provider = Provider.of<MessageList>(context, listen: false);
        if (questionIndex == 1) {
          var lastItem = provider.posts[provider.posts.length - 4];
          debugPrint(lastItem.toString());
          provider.addOrder(lastItem.message, int.parse(item));
        }

        provider.addMessage(Message(message: item, sender: 'Bot'));
        scrollToBottom(widget.scrollController);

        if (questionIndex == 2) {
          provider.addMessage(
            Message(
              message: 'Thank you for your order!',
              sender: 'bot',
            ),
          );
          scrollToBottom(widget.scrollController);
          var orders = provider.order;
          double total = 0;
          orders.forEach((key, value) {
            if (value.quantity != 0) {
              total += value.price * value.quantity;
              String itemString =
                  '$key - ${value.quantity} - ${value.quantity * value.price}';

              provider.addMessage(
                Message(
                  message: itemString,
                  sender: 'bot',
                ),
              );
            }
            scrollToBottom(widget.scrollController);
          });
          provider.addMessage(
            Message(
              message: 'Total: $total',
              sender: 'bot',
            ),
          );
          scrollToBottom(widget.scrollController, value: 400);
        }

        debugPrint(audiowaveFormResponse.data.toString());
        questionIndex = (questionIndex + 1) % 3;
        addBotMessage(questionIndex);
      } else {
        debugPrint("Request Failed!");
        Provider.of<MessageList>(context, listen: false).addMessage(
            Message(message: 'Request failed. Try again!', sender: 'Bot'));
        scrollToBottom(widget.scrollController);
        // widget.scrollController
        //     .jumpTo(widget.scrollController.position.maxScrollExtent);
      }
    } catch (e) {
      Provider.of<MessageList>(context, listen: false).addMessage(
          Message(message: 'Request failed. Try again!', sender: 'Bot'));
      scrollToBottom(widget.scrollController);
      // widget.scrollController
      //     .jumpTo(widget.scrollController.position.maxScrollExtent);
    }
  }

  String checkAnswer(int n) {
    return n == 3 ? "Yes" : "No";
  }

  String findQuantity(int n) {
    return (n - 4).toString();
  }

  String findItem(int n) {
    switch (n) {
      case 0:
        return 'Tea';
      case 1:
        return 'Vada';
      case 2:
        return 'Maggie';
      default:
        return 'Other';
    }
  }

  String findAns(List<double> p, int questionIndex) {
    if (questionIndex == 0) {
      var n = itemTest(p);
      return findItem(n);
    } else if (questionIndex == 1) {
      var n = quantityTest(p);
      return findQuantity(n);
    } else {
      var n = yesnoTest(p);
      return checkAnswer(n);
    }
  }

  List<double> calculateResult(List<double> data) {
    // execute util functions
    var amp = split(data);
    var obs = findObsSeq(amp);
    var prob = test(obs);
    debugPrint(prob.toString());
    return prob;
  }

  Future<void> stopRecorder() async {
    await _mRecorder!.stopRecorder();
    if (_mRecordingDataSubscription != null) {
      await _mRecordingDataSubscription!.cancel();
      _mRecordingDataSubscription = null;
    }
    _mplaybackReady = true;

    Provider.of<MessageList>(context, listen: false)
        .addMessage(Message(message: filename!, sender: 'Me'));

    Future.delayed(const Duration(milliseconds: 500), () {
      Provider.of<MessageList>(context, listen: false).addMessage(Message(
          message: 'Please wait! Processing your request.', sender: 'bot'));
      scrollToBottom(widget.scrollController);
      // widget.scrollController
      //     .jumpTo(widget.scrollController.position.maxScrollExtent);
    });

    sendRequest(_mPath!);
  }

  _Fn? getRecorderFn() {
    if (!_mRecorderIsInited || !_mPlayer!.isStopped) {
      return null;
    }
    return _mRecorder!.isStopped
        ? record
        : () {
            stopRecorder().then((value) => setState(() {}));
          };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(3),
      padding: const EdgeInsets.all(3),
      height: 70,
      width: 70,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade500,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          onPressed: getRecorderFn(),
          color: Colors.white,
          icon: Icon(
            _mRecorder!.isRecording
                ? Icons.stop_circle_rounded
                : Icons.mic_rounded,
            size: 30,
          ),
        ),
      ]),
    );
  }
}
