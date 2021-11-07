import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as RTC;
import 'package:get_boilerplate/src/pages/home/widgets/remote_view_card.dart';
import 'package:get_boilerplate/src/services/socket_emit.dart';
import 'package:sdp_transform/sdp_transform.dart';
import 'package:socket_io_client/socket_io_client.dart';

Map<String, dynamic> configuration = {
  'iceServers': [
    {"urls": "stun:stun.jacknathan.tk:3478"},
    {
      "urls": "turn:turn.jacknathan.tk:3478",
      "username": "ducanhzed",
      "credential": "1507200a",
    },
  ],
  'sdpSemantics': "unified-plan",
};

Socket socket;

class HomePage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> socketIdRemotes = [];
  RTC.RTCPeerConnection _peerConnection;
  RTC.MediaStream _localStream;
  RTC.RTCVideoRenderer _localRenderer = RTC.RTCVideoRenderer();
  bool _isSend = false;
  bool _isFrontCamera = true;

  @override
  void initState() {
    super.initState();
    initRenderers();
    _createPeerConnection().then(
      (pc) async {
        _peerConnection = pc;
        _localStream = await _getUserMedia();
        _localStream.getTracks().forEach((track) {
          _peerConnection.addTrack(track, _localStream);
        });
      },
    );
    connectAndListen();
  }

  @override
  void dispose() {
    _peerConnection.close();
    _localStream.dispose();
    _localRenderer.dispose();
    super.dispose();
  }

  _switchCamera() async {
    if (_localStream != null) {
      bool value = await _localStream.getVideoTracks()[0].switchCamera();
      while (value == _isFrontCamera) value = await _localStream.getVideoTracks()[0].switchCamera();
      _isFrontCamera = value;
    }
  }

  _createPeerConnectionAnswer(socketId) async {
    RTC.RTCPeerConnection pc = await RTC.createPeerConnection(configuration);

    pc.onTrack = (track) {
      int index = socketIdRemotes.indexWhere((item) => item['socketId'] == socketId);
      socketIdRemotes[index]['stream'].srcObject = track.streams[0];
    };

    pc.onRenegotiationNeeded = () {
      _createOfferForReceive(socketId);
    };

    return pc;
  }

  void connectAndListen() async {
    var urlConnectSocket = 'https://tugomu.tk';
    socket =
        io(urlConnectSocket, OptionBuilder().enableForceNew().setTransports(['websocket']).build());
    socket.connect();
    socket.onConnect((_) {
      print('connected');

      socket.on('NEW-PEER-SSC', (data) async {
        String newUser = data['socketId'];
        RTC.RTCVideoRenderer stream = new RTC.RTCVideoRenderer();
        await stream.initialize();
        socketIdRemotes.add({
          'socketId': newUser,
          'pc': null,
          'stream': stream,
        });
        _createPeerConnectionAnswer(newUser).then((pcRemote) {
          socketIdRemotes[socketIdRemotes.length - 1]['pc'] = pcRemote;
          socketIdRemotes[socketIdRemotes.length - 1]['pc'].addTransceiver(
            kind: RTC.RTCRtpMediaType.RTCRtpMediaTypeVideo,
            init: RTC.RTCRtpTransceiverInit(
              direction: RTC.TransceiverDirection.RecvOnly,
            ),
          );
        });
      });

      socket.on('SEND-SSC', (data) {
        List<String> listSocketId =
            (data['sockets'] as List<dynamic>).map((e) => e.toString()).toList();
        listSocketId.asMap().forEach((index, user) async {
          RTC.RTCVideoRenderer stream = new RTC.RTCVideoRenderer();
          await stream.initialize();
          setState(() {
            socketIdRemotes.add({
              'socketId': user,
              'pc': null,
              'stream': stream,
            });
          });
          _createPeerConnectionAnswer(user).then((pcRemote) {
            socketIdRemotes[index]['pc'] = pcRemote;
            socketIdRemotes[index]['pc'].addTransceiver(
              kind: RTC.RTCRtpMediaType.RTCRtpMediaTypeVideo,
              init: RTC.RTCRtpTransceiverInit(
                direction: RTC.TransceiverDirection.RecvOnly,
              ),
            );
          });
        });

        _setRemoteDescription(data['sdp']);
      });

      socket.on('RECEIVE-SSC', (data) {
        int index = socketIdRemotes.indexWhere(
          (element) => element['socketId'] == data['socketId'],
        );
        if (index != -1) {
          _setRemoteDescriptionForReceive(index, data['sdp']);
        }
      });
    });

    socket.onDisconnect((_) => print('disconnect'));
  }

  initRenderers() async {
    await _localRenderer.initialize();
  }

  void _setRemoteDescription(sdp) async {
    RTC.RTCSessionDescription description = new RTC.RTCSessionDescription(sdp, 'answer');
    await _peerConnection.setRemoteDescription(description);
  }

  void _setRemoteDescriptionForReceive(indexSocket, sdp) async {
    RTC.RTCSessionDescription description = new RTC.RTCSessionDescription(sdp, 'answer');
    await socketIdRemotes[indexSocket]['pc'].setRemoteDescription(description);
  }

  _createOffer() async {
    RTC.RTCSessionDescription description = await _peerConnection.createOffer({
      'offerToReceiveVideo': 1,
      'offerToReceiveAudio': 1,
    });
    _peerConnection.setLocalDescription(description);
    var session = parse(description.sdp.toString());
    String sdp = write(session, null);
    await sendSdpForBroadcast(sdp);
  }

  _createOfferForReceive(String socketId) async {
    int index = socketIdRemotes.indexWhere((item) => item['socketId'] == socketId);
    if (index != -1) {
      RTC.RTCSessionDescription description = await socketIdRemotes[index]['pc'].createOffer({
        'offerToReceiveVideo': 1,
        'offerToReceiveAudio': 1,
      });
      socketIdRemotes[index]['pc'].setLocalDescription(description);
      var session = parse(description.sdp.toString());
      String sdp = write(session, null);
      await sendSdpOnlyReceive(sdp, socketId);
    }
  }

  _createPeerConnection() async {
    final Map<String, dynamic> offerSdpConstraints = {
      "mandatory": {
        "OfferToReceiveAudio": true,
        "OfferToReceiveVideo": true,
      },
      "optional": [],
    };

    RTC.RTCPeerConnection pc = await RTC.createPeerConnection(configuration, offerSdpConstraints);

    pc.onRenegotiationNeeded = () {
      if (!_isSend) {
        _isSend = true;
        _createOffer();
      }
    };
    return pc;
  }

  Future sendSdpForBroadcast(
    String sdp,
  ) async {
    SocketEmit().sendSdpForBroadcase(sdp);
  }

  Future sendSdpOnlyReceive(
    String sdp,
    String socketId,
  ) async {
    SocketEmit().sendSdpForReceive(sdp, socketId);
  }

  _getUserMedia() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'facingMode': 'user',
      },
    };

    RTC.MediaStream stream = await RTC.navigator.getUserMedia(mediaConstraints);

    setState(() {
      _localRenderer.srcObject = stream;
    });

    return stream;
  }

  endCall() {
    _peerConnection.close();
    _localStream.dispose();
    _localRenderer.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Size size = MediaQuery.of(context).size;
    return Scaffold(
      body: Container(
        height: size.height,
        width: size.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Stack(
              children: [
                Container(
                  color: Colors.black,
                  width: size.width,
                  height: size.height,
                  child: socketIdRemotes.isEmpty
                      ? Container()
                      : RemoteViewCard(
                          remoteRenderer: socketIdRemotes[0]['stream'],
                        ),
                ),
                Positioned(
                  bottom: 20.0,
                  left: 12.0,
                  right: 0,
                  child: Container(
                    color: Colors.transparent,
                    width: size.width,
                    height: size.width * .25,
                    child: socketIdRemotes.length < 2
                        ? Container()
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: socketIdRemotes.length - 1,
                            itemBuilder: (context, index) {
                              return Container(
                                margin: EdgeInsets.only(right: 6.0),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4.0),
                                  border: Border.all(
                                    color: Colors.blueAccent,
                                    width: 2.0,
                                  ),
                                ),
                                child: RemoteViewCard(
                                  remoteRenderer: socketIdRemotes[index + 1]['stream'],
                                ),
                              );
                            },
                          ),
                  ),
                ),
                Positioned(
                  top: 45.0,
                  left: 15.0,
                  child: Column(
                    children: [
                      _localRenderer.textureId == null
                          ? Container(
                              height: size.width * .50,
                              width: size.width * .32,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.all(Radius.circular(6.0)),
                                border: Border.all(color: Colors.blueAccent, width: 2.0),
                              ),
                            )
                          : FittedBox(
                              fit: BoxFit.cover,
                              child: Container(
                                height: size.width * .50,
                                width: size.width * .32,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.all(Radius.circular(6.0)),
                                  border: Border.all(color: Colors.blueAccent, width: 2.0),
                                ),
                                child: Transform(
                                  transform: Matrix4.identity()..rotateY(0.0),
                                  alignment: FractionalOffset.center,
                                  child: Texture(textureId: _localRenderer.textureId),
                                ),
                              ),
                            ),
                      SizedBox(
                        height: 8.0,
                      ),
                      GestureDetector(
                        onTap: () => _switchCamera(),
                        child: Container(
                          height: size.width * .125,
                          width: size.width * .125,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.blueAccent, width: 2.0),
                            color: Colors.blueAccent,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.switch_camera,
                            color: Colors.white,
                            size: size.width / 18.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              children: [
                // Expanded(
                //   flex: 1,
                //   child: GestureDetector(
                //     onTap: () async {
                //       endCall();
                //     },
                //     child: Container(
                //       height: size.width * .15,
                //       decoration: BoxDecoration(
                //         color: Colors.transparent,
                //       ),
                //       // child: Icon(
                //       //   Icons.phone_missed,
                //       //   color: Colors.white,
                //       //   size: size.width / 14.0,
                //       // ),
                //     ),
                //   ),
                // ),
                // Expanded(
                //   flex: 1,
                //   child: GestureDetector(
                //     onTap: () async {},
                //     child: Container(
                //       height: size.width * .15,
                //       decoration: BoxDecoration(
                //         color: Colors.transparent,
                //       ),
                //       // child: Icon(
                //       //   Icons.phone,
                //       //   color: Colors.white,
                //       //   size: size.width / 14.0,
                //       // ),
                //     ),
                //   ),
                // ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
