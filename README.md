# Reach

Point at your Mac's screen and the pointer goes there. Pinch to click. Tap the glass to click.

Reach is a small menu bar app for Apple Silicon Macs. It uses the built-in camera and
Apple's Vision framework to track your hand, and the microphone array to hear a fingertip
tap the screen. Nothing is recorded, nothing leaves the machine, and there are no
dependencies beyond macOS.

## Install

```bash
cd ~/Code && git clone https://github.com/mrivanlizarde/reach.git && cd reach && ./make-app.sh release --install && open ~/Applications/Reach.app
```

Requires macOS 15 or later and Xcode's command line tools.

## Use

1. Click the hand in the menu bar and turn the switch on.
2. Allow **Camera** when asked. Then allow **Device Control and Data Access** (called Accessibility
   before macOS 27; the panel opens System Settings for you, press + and add Reach from
   `~/Applications`). That grant is what lets the app move the pointer and click.
3. Hold a hand up to the camera. The pointer follows your index finger.
4. **Calibrate** once: point at the top-left corner of the screen and hold still, then the
   bottom-right. From then on the space between those two points is the whole screen, so
   small movements reach every edge.

**Clicking.** Pinch is the click. Tap is there if you want it, off by default.

- **Pinch** thumb and index together. Hold the pinch to drag.
- **Tap the glass.** Allow the Microphone. Point first, so the pointer is on the target,
  then reach in and tap within a few seconds. The mics hear the tap and a click lands
  where the pointer is. The camera does not see your hand once it is at the screen, so
  the point has to come first. The sensitivity slider sets how hard a tap has to be.

**Cameras.** The picker lists every camera, including Desk View on Macs that have it.
Desk View looks down at the desk, which is useful if you would rather gesture above the
keyboard than in front of the screen.

**Smoothing.** Left is quick and a little jittery; right is calm and a little slow.

## Why it is not a real touchscreen

The camera cannot see its own screen; it points at you. So Reach cannot know that a
finger has touched the glass by looking. It tracks where the finger is and listens for the
tap. It feels like touch for pointing and clicking, and it will not do multitouch, pressure,
or precise taps on small targets the way glass does. For that, see
[Project Sistine](https://github.com/bijection/sistine), which clips a small mirror over
the camera.

## Privacy

Camera and microphone are processed in memory on the device, frame by frame, and dropped.
There is no network code in the app.

## License

MIT.
