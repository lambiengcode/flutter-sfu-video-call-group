## Video Call Flutter App 📱

### Description:
- This is sandbox video call application using Flutter and WebRTC.

### SFUs – Selective Forwarding Units
<img src="https://lh4.googleusercontent.com/puUKv2ve5bkx88wUhb_OG7ydimoSi74_hXT1akU7YUzmrSg29arhlhwWdg5e6x03KhBwnt_7OD0qVOYNfq-U3tpjVgDAwGMkzklVuUWp-jcNXUzPXFWJgD9oowQHWSVu5NxZtwB4" width="600px"/>

- In this case, each participant still sends just one set of video and audio up to the SFU, like our MCU. However, the SFU doesn’t make any composite streams. Rather, it sends a different stream down for each user. In this example, 4 streams are received by each participant, since there are 5 people in the call.
- The good thing about this is it’s still less work on each participant than a mesh peer-to-peer model. This is because each participant is only establishing one connection (to the SFU) instead of to all other participants to upload their own video/audio. But, it can be more bandwidth intensive than the MCU because the participants each receive multiple streams downloaded.
- The nice thing for participants about receiving separate streams is that they can do whatever they want with them. They are not bound to layout or UI decisions of the MCU. If you have been in a conference call where the conferencing tool allowed you to choose a different layout (ie, which speaker’s video will be most prominent, or how you want to arrange the videos on the screen), then that was using an SFU.
- Media servers which implement an SFU architecture include Jitsi and Janus.

### Quick start
- Update Later