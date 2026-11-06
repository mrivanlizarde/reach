# START HERE — Reach

**What this is.** A macOS menu bar app that turns the MacBook's built-in camera into a
pointing device. Vision's hand pose detector finds all 21 joints of your hand in every
frame, the pointer is read from the knuckles, a One Euro filter and a short dead zone
steady it, and the pointer follows. A pinch clicks (move while pinched to drag), a thumb to
the middle finger right-clicks, two fingers up scrolls, a fist holds the cursor. The
microphone array can also listen for a fingertip tapping the glass (off by default). No
Dock icon, no window: one status item, one popover.

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
| Anything in the tracker or engine | Build, install, launch, turn it on, move your hand. The preview draws the whole hand with a ring on the knuckles; the pointer must follow the ring with no visible shake, and must not move when you wiggle your fingers. |
| Steadiness | Hold the pointer over a small target (a window's close button) and pinch. The click must land on it. Read the newest csv: `pose` rows carry the gap between hand and cursor in px in column d; while aiming it should sit under 10. |
| Pinch | Pinch over a Finder icon and move while pinched; it must drag once your hand has moved a little. Pinch and release without moving; it must click, not drag. |
| Right-click, scroll, fist | Thumb to middle finger with the index out: a context menu must open. Two fingers up over a long page, move the hand: the page must scroll with the hand. Make a fist and move the hand: the cursor must stay put. The panel's readout shows the five fingers as digits and the mode. |
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
- **The pointer is read at the knuckles, never the fingertip.** `HandSample.anchor` is
  the middle of the index and middle knuckles. The index tip is the one joint that moves
  when you pinch, so a tip-anchored cursor ran off its target at the moment of every click
  (Ivan, 2026-11-05, "it's following my fingers too accurately"). Calibration measures
  the same anchor. The stillness gate still watches the tip, on purpose: a pinch moves
  the tip and so wakes a parked hand, while the phantom hands it guards against never move.
- **Three steadiers, keep all three.** The cursor trails the hand on a 5 px string
  (jitter inside it never posts), it is pinned from the first frame the thumb starts
  closing until the pinch lands or 0.7 s pass, and a pinch stays a click until the hand
  has moved 14 px from the press point. Whenever the cursor is held while the hand keeps
  moving, the gap is pinned as an offset that fades over about half a second, so letting
  go never jumps. Remove any of them and the click-time drift comes back.
- **Mirror once.** The camera faces you, so raw x is reversed. The engine mirrors the
  anchor before calibration and mapping; the preview mirrors the image and the
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

- `Sources/Reach/HandTracker.swift` — camera session and Vision request, background queue; `HandSample` holds all 21 joints and reads finger extension, pinch ratios, and the knuckle anchor off them.
- `Sources/Reach/TapListener.swift` — microphone onset detector.
- `Sources/Reach/PointerEngine.swift` — mapping, smoothing and steadying, pinch and gesture state machines, calibration, CGEvents.
- `Sources/Reach/PanelView.swift` — the popover.
- `Sources/Reach/AppDelegate.swift` — status item, popover, launch at login.
- `Sources/make-icon/main.swift` — draws the icon; `make-app.sh` assembles the bundle.
