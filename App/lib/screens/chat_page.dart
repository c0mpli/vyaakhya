import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:get/get.dart';
import 'package:iotascamapp/api.dart';
import 'package:iotascamapp/common/loaders.dart';
import 'package:just_audio/just_audio.dart';
import 'package:speech_to_text/speech_to_text.dart';

class ChatPage extends StatefulWidget {
  final String description;
  final String url;

  const ChatPage({
    super.key,
    required this.description,
    required this.url,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<types.Message> _messages = [];
  final List<String> _backendMessages = [];
  final RxBool isAnswerLoading = false.obs;

  late AudioPlayer sendPlayer, recceivePlayer;
  Duration? sendDuration, receiveDuration;

  final _user = const types.User(id: 'user');

  final TextEditingController mText = TextEditingController();
  final RxBool isMicOn = false.obs;

  @override
  void initState() {
    super.initState();
    sendPlayer = AudioPlayer();
    recceivePlayer = AudioPlayer();
    //_initializeAudioPlayer();
    //loading screen dalna hai bas abhi
  }

  Future<void> _initializeAudioPlayer() async {
    sendDuration = await sendPlayer.setAsset('assets/send_chime.mp3');
    receiveDuration = await recceivePlayer.setAsset('assets/recieve_chime.mp3');
  }

  @override
  void dispose() {
    sendPlayer.dispose();
    recceivePlayer.dispose();
    mText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SpeechToText speech = SpeechToText();

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Chat'),
          ),
          body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Description of image:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: SizedBox(
                  height: MediaQuery.of(context).size.width * 0.5,
                  child: SingleChildScrollView(
                    child: Text(
                      widget.description,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Ask any question',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Chat(
                  messages: _messages,
                  onSendPressed: handleSendPressed,
                  user: _user,
                  customBottomWidget: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Container(
                      //ye talkback ka focus send pe tha fir bhi input khula
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 37, 35, 46),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.5),
                            spreadRadius: 1,
                            blurRadius: 5,
                            offset: const Offset(0, 3),
                          ),
                        ],
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Focus(
                        autofocus: false,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: mText,
                                decoration: const InputDecoration(
                                  hintText: 'Type a message',
                                  hintStyle: TextStyle(color: Colors.white),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(0),
                                ),
                                style: const TextStyle(color: Colors.white),
                                onSubmitted: (value) async {
                                  if (value.isNotEmpty) {
                                    final String text = mText.text;
                                    mText.clear();
                                    await handleSendPressed(
                                        types.PartialText(text: text));
                                  }
                                },
                              ),
                            ),
                            Obx(() {
                              return IconButton(
                                icon: Icon(
                                  Icons.mic,
                                  semanticLabel: 'Microphone',
                                  color:
                                      isMicOn.value ? Colors.red : Colors.white,
                                ),
                                onPressed: () async {
                                  if (!isMicOn.value &&
                                      await speech.initialize()) {
                                    isMicOn.value = true;
                                    await speech.listen(
                                      onResult: (result) {
                                        mText.text = result.recognizedWords;
                                        isMicOn.value = false;
                                      },
                                    );
                                  } else {
                                    isMicOn.value = false;
                                    speech.stop();
                                  }
                                },
                              );
                            }),
                            IconButton(
                              icon: const Icon(
                                Icons.send,
                                semanticLabel: "Send",
                                color: Colors.white,
                              ),
                              onPressed: () async {
                                final String text = mText.text;
                                if (text.isNotEmpty) {
                                  mText.clear();
                                  await handleSendPressed(
                                      types.PartialText(text: text));
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Obx(() => isAnswerLoading.value
        //     ? PopScope(
        //         canPop: false,
        //         child: Material(
        //           color: Colors.black.withOpacity(0.5),
        //           child: Container(
        //             color: Colors.black.withOpacity(0.5),
        //             child: const Center(
        //               child: Row(
        //                 mainAxisAlignment: MainAxisAlignment.center,
        //                 crossAxisAlignment: CrossAxisAlignment.center,
        //                 children: [
        //                   CircularProgressIndicator(),
        //                   SizedBox(width: 20),
        //                   Text(
        //                     'Loading answer',
        //                     style: TextStyle(
        //                       fontSize: 16,
        //                       fontWeight: FontWeight.bold,
        //                       color: Colors.white,
        //                       // background: Paint()..color = Colors.black,
        //                     ),
        //                   )
        //                 ],
        //               ),
        //             ),
        //           ),
        //         ),
        //       )
        //     : const SizedBox.shrink()),
      ],
    );
  }

  String randomString() {
  final random = Random.secure();
  final values = List<int>.generate(16, (i) => random.nextInt(255));
  return base64UrlEncode(values);
}

  Future<void> handleSendPressed(types.PartialText message) async {
    final textMessage = types.TextMessage(
      author: _user,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: randomString(),
      text: message.text,
    );

    final loadingMessage = types.TextMessage(
      author: const types.User(id: 'bot'),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: randomString(),
      text: 'Loading...',
    );

    setState(() {
      isAnswerLoading.value = true;
      _messages.insert(0, textMessage);
      _messages.insert(0, loadingMessage);
      _backendMessages.add(message.text);
    });

    customLoadingOverlay("Loading answer");

    final response = await Api()
        .getAnswer(message.text, widget.url, jsonEncode(_backendMessages));

    Get.back();
    if (response != '') {
      final botMessage = types.TextMessage(
        author: const types.User(id: 'bot'),
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: randomString(),
        text: response,
        repliedMessage: textMessage,
      );
      setState(() {
        isAnswerLoading.value = false;
        _messages.removeAt(0);
        _messages.insert(0, botMessage);
      });
      //hide keyboard
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }
}