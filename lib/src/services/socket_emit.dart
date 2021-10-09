import 'package:get_boilerplate/src/pages/home/home_page.dart';

class SocketEmit {
  sendSdpForBroadcase(String sdp) {
    socket.emit('SEND-CSS', {'sdp': sdp});
  }

  sendSdpForReceive(String sdp, String socketId) {
    socket.emit('RECEIVE-CSS', {
      'sdp': sdp,
      'socketId': socketId,
    });
  }
}
