# START HERE — Reach

**What this is.** A macOS menu bar app that turns the MacBook's built-in camera into a
pointing device. Vision's hand pose detector finds your index fingertip in every frame,
a One Euro filter steadies it, and the pointer follows. A pinch clicks (hold it to drag),
and the microphone array listens for the sound of a fingertip tapping the glass so a real
tap on the screen clicks too. The camera says where; the mics say when. No Dock icon, no
window: one status item, one popover.

Swift Package, AppKit + SwiftUI, Apple Silicon, macOS 15+. No dependencies.

## The honest limit, before anything else

A built-in camera cannot see the surface of its own screen. The lens sits in the bezel,
looking out at you; a fingertip on the glass is at ninety degrees to its axis, outside
every field of view it has, Desk View included (Desk View is a downward crop of the
ultra-wide sensor and sees the desk and keyboard, not the display). Project Sistine
proved contact detection in 2018 with a $1 mirror clipped over the camera so the lens
could see the screen and the finger's reflection. Without a mirror there is no contact
signal in the image. That is why Reach fuses two sensors: the hand's position from the
camera, and the tap transient from the microphones. It feels like touch; it is not
reading touch.

There is no gyroscope or accelerometer API on Apple Silicon Macs. Nothing to fuse there.

## Run it and see it

```bash
cd ~/Code/reach && ./make-app.sh release --install && open ~/Applications/Reach.app
```

A hand icon appears in the menu bar. Click it, turn the switch on, grant Camera, then
Device Control and Data Access (Accessibility before macOS 27; System Settings opens, press +, add Reach). Show a hand to the camera. The icon
fills in when a hand is tracked.

## Verify a change — reading the code is not verification

| Change | Proof |
|---|---|
| Anything in the tracker or engine | Build, install, launch, turn it on, move your hand. The preview shows a dot on your index tip; the pointer must follow it with no visible stutter. |
| Pinch | Pinch and hold over a Finder icon; it must drag. Release; it must drop. |
| Tap-to-click | Tap the glass once with a hand in view; the counter in the panel increments and a click lands. Knock the desk: nothing should happen. |
| Calibration | Calibrate, then point at each screen corner: the pointer must reach every edge without the hand leaving the frame. |
| Thresholds | Run the 60-second protocol in PLAN.md, then read `~/Library/Logs/Reach/signals <date>.csv`. Pinched frames must sit well under 0.28 and open frames well over 0.40; screen taps must show onset above the sensitivity's ratio and desk knocks and keystrokes must be dropped (tap rows with d=0). |
| Panel layout | Open the popover in light and dark mode and look. 300pt wide, nothing clipped. |
| Permissions | Revoke one in System Settings; the panel row must go orange within a second and the Allow… button must open the right pane. |

## Rules of engagement

- **Sign with a real identity.** `make-app.sh` signs with the Developer ID (or Apple
  Development) certificate in the keychain, falling back to ad-hoc only when none exists.
  Ad-hoc ties every privacy grant to one exact build: on 2026-11-05 the Device Control
  switch was on in System Settings and `AXIsProcessTrusted` still returned false. If a
  grant ever stops being seen after a rebuild, `codesign -d -r-` the installed app: the
  designated requirement must end in `subject.OU = LD587PB2H8` (team-based). An Apple
  Development signature pins the certificate's name instead, so a grant given to that
  build dies the moment the app is signed with anything else. That is exactly what
  happened on 2026-11-05: Reach was added to Device Control during a two-minute window
  when it carried the Apple Development signature, and the Developer ID build that
  followed read as untrusted with the switch on. Fix: `tccutil reset Accessibility
  com.ivanlizarde.reach`, then add it again. Never change the signing identity after the
  app has been granted anything.
- **LSUIElement stays true.** The app is a menu bar extra by design. There is no window
  to show, so nothing is lost.
- **Mouse events go through `CGEvent.post(tap: .cghidEventTap)`.** That needs the
  Accessibility grant. Without it the hand tracks and nothing moves, which is the
  confusing failure, so the panel names it loudly and the engine checks before posting.
- **Vision coordinates have their origin at the bottom-left.** Screen coordinates for
  CGEvent have theirs at the top-left. The flip lives in `PointerEngine` and nowhere else.
- **Mirror once.** The camera faces you, so raw x is reversed. The engine mirrors the
  fingertip before calibration and mapping; the preview mirrors the image and the
  overlay; the stored region is in mirrored coordinates. Mirror in a second place and
  calibration will invert.
- **Two gates, keep both.** The pointer follows only a raised hand (index tip above wrist in frame), and no pinch or tap counts within 0.3 s of a keystroke. Without them, typing clicks.
- **Nothing starts a sensor from inside an initializer.** `PointerEngine.activate()` runs
  from `applicationDidFinishLaunching`, and every settings sink drops its first value.
  Starting the microphone engine inside `init` hung the app at launch with no icon on
  2026-11-05. If a relaunch shows no icon, `sample Reach 2` and look at the main thread.
- **Tap detection is gated on a visible hand.** A knock on the desk or a dropped pen
  with no hand in view does nothing. Keep that gate.

## Where things are

- `Sources/Reach/HandTracker.swift` — camera session and Vision request, background queue.
- `Sources/Reach/TapListener.swift` — microphone onset detector.
- `Sources/Reach/PointerEngine.swift` — mapping, smoothing, pinch state machine, calibration, CGEvents.
- `Sources/Reach/PanelView.swift` — the popover.
- `Sources/Reach/AppDelegate.swift` — status item, popover, launch at login.
- `Sources/make-icon/main.swift` — draws the icon; `make-app.sh` assembles the bundle.
