const express = require("express");
const app = express();
const bodyParser = require("body-parser");
const webrtc = require("wrtc");
const server = require("http").Server(app);
const io = require("socket.io")(server, {
  cors: {
    origin: "*",
  },
});

const port = 5000;
let senderStreams = [];

app.use(express.static("public"));
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

app.get("/*", (req, res) => res.send("SFUs SERVER"));

function handleTrackEvent(e, socketId) {
  const index = senderStreams.findIndex((item) => socketId === item.socketId);
  if (index != -1) {
    senderStreams[index].stream = e.streams[0];
  } else {
    senderStreams.push({
      socketId: socketId,
      stream: e.streams[0],
    });
  }
}

async function createPeerConnectionSend(sdp, socketId) {
  const peer = new webrtc.RTCPeerConnection({
    iceServers: [
      {
        urls: "stun:stun.stunprotocol.org",
      },
    ],
  });
  peer.ontrack = (e) => handleTrackEvent(e, socketId);
  const sdpDesc = {
    type: "offer",
    sdp: sdp,
  };
  const desc = new webrtc.RTCSessionDescription(sdpDesc);
  await peer.setRemoteDescription(desc);
  const answer = await peer.createAnswer();
  await peer.setLocalDescription(answer);
  const payload = peer.localDescription.sdp;
  return payload;
}

async function createPeerConnectionReceive(sdp, socketId) {
  const peer = new webrtc.RTCPeerConnection({
    iceServers: [
      {
        urls: "stun:stun.stunprotocol.org",
      },
    ],
  });
  const sdpDesc = {
    type: "offer",
    sdp: sdp,
  };
  const desc = new webrtc.RTCSessionDescription(sdpDesc);
  await peer.setRemoteDescription(desc);
  const index = senderStreams.findIndex((e) => e.socketId === socketId);
  if (senderStreams.length > 0) {
    senderStreams[index].stream
      .getTracks()
      .forEach((track) => peer.addTrack(track, senderStreams[index].stream));
  }
  const answer = await peer.createAnswer();
  await peer.setLocalDescription(answer);
  const payload = peer.localDescription.sdp;

  return payload;
}

io.on("connection", function (socket) {
  socket.on("SEND-CSS", async function (data) {
    const payload = await createPeerConnectionSend(data.sdp, socket.id);
    const listSocketId = senderStreams
      .filter((e) => e.socketId != socket.id)
      .map((e) => e.socketId);
    io.to(socket.id).emit("SEND-SSC", {
      socketId: socket.id,
      sdp: payload,
      sockets: listSocketId,
    });
    socket.broadcast.emit("NEW-PEER-SSC", {
      socketId: socket.id,
    });
  });

  socket.on("RECEIVE-CSS", async function (data) {
    console.log(data.socketId);
    const payload = await createPeerConnectionReceive(data.sdp, data.socketId);
    io.to(socket.id).emit("RECEIVE-SSC", {
      socketId: data.socketId,
      sdp: payload,
    });
  });

  socket.on("disconnect", function () {
    senderStreams = senderStreams.filter((e) => e.socketId !== socket.id);
  });
});

app.post("/broadcast", async ({ body }, res) => {
  const peer = new webrtc.RTCPeerConnection({
    iceServers: [
      {
        urls: "stun:stun.stunprotocol.org",
      },
    ],
  });
  peer.ontrack = (e) =>
    handleTrackEvent(e, Math.floor(Math.random() * 1000000000).toString());
  const desc = new webrtc.RTCSessionDescription(body.sdp);
  await peer.setRemoteDescription(desc);
  const answer = await peer.createAnswer();
  await peer.setLocalDescription(answer);
  const payload = {
    sdp: peer.localDescription,
  };

  res.json(payload);
});

app.post("/consumer", async ({ body }, res) => {
  const peer = new webrtc.RTCPeerConnection({
    iceServers: [
      {
        urls: "stun:stun.stunprotocol.org",
      },
    ],
  });
  const desc = new webrtc.RTCSessionDescription(body.sdp);
  await peer.setRemoteDescription(desc);
  if (senderStreams.length > 0) {
    let index = 0;
    senderStreams[index].stream
      .getTracks()
      .forEach((track) => peer.addTrack(track, senderStreams[index].stream));
  }
  const answer = await peer.createAnswer();
  await peer.setLocalDescription(answer);
  const payload = {
    sdp: peer.localDescription,
  };

  res.json(payload);
});

server.listen(port, "0.0.0.0", function () {
  console.log("Server is running on port: " + port);
});
