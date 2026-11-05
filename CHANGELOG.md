# CHANGELOG — Reach

## 2026-11-05, 14:20 — Third run: the grant was bound to the wrong certificate

Device Control listed Reach, switched on, and a fresh launch of the Developer ID build
still read untrusted. The log names showed a launch at 13:49:04, inside the two minutes
when the app carried the Apple Development signature. A grant given then is pinned to
that certificate's name; the Developer ID build that followed at 13:50 no longer matched.
`codesign -d -r-` confirms the installed build's requirement is now team-based, so this
cannot recur once Reach is added one more time. Entry reset, no code change.

The hand data from this run was the best yet: open hand at 0.83 to 0.98 with 0.9
confidence (palm to the camera this time), pinches down to 0.04. Thresholds stand. The
stillness gate parked the hand during the three-second hold, as designed.

## 2026-11-05, late — Real signature, and a parked hand stops driving the pointer

Second run read. Device Control and Data Access showed Reach switched on and the app
still read as untrusted, before and after a relaunch of the same binary. The ad-hoc
signature was the cause: TCC had nothing stable to bind the grant to. `make-app.sh` now
signs with the Developer ID certificate in the keychain (Apple Development as fallback,
ad-hoc only when neither exists), which gives the grant a team-based requirement that
survives rebuilds. The stale entry was reset with `tccutil`, so Reach has to be added once
more.

Also from the logs: the pose model held a motionless "hand" at 30 fps for over two
minutes across two launches, at a steady pinch ratio near 1.1. With the grant on, that
would have pinned the pointer. A hand that has not moved for two seconds is now parked:
it stops driving the pointer and cannot click until it moves again. The panel says
"parked" and the status reads "Still. Move to wake".

## 2026-11-05, evening — Launch hang when tracking was saved on

Found by sampling the process after a relaunch produced no log and no icon. With
`trackingEnabled` persisted as true, the engine's Combine sinks fired inside its
initializer and started the microphone listener on the main thread before the app had
finished launching; `AVAudioEngine` blocked there and the status item never appeared.
Every sink now drops its initial value, `activate()` runs from
`applicationDidFinishLaunching`, and the microphone engine is only touched once the grant
is already held. Verified by relaunching: the main thread sits in the run loop and the
start note is written within a second.

## 2026-11-05, evening — Thresholds from the first real run

Ivan ran the 60-second protocol. 862 hand frames at 30 fps, six taps, fifty audio onsets.

- **Nothing clicked because Accessibility was never granted.** Every pinch and every
  raised-hand tap was rejected at the same guard. The log now records the grant state at
  start and the reason for every rejected tap, so this is never a mystery again.
- **Pinch thresholds moved up to 0.40 / 0.52.** Pinched frames sat at 0.11 to 0.33; every
  open or resting frame was 0.59 or higher. The old 0.28 sat on top of the pinch cluster
  and would have missed half of them. Open hands read as high as 2.5 because the pointing
  posture foreshortens the palm; the ratio still separates cleanly.
- **The camera loses the hand at the glass.** The five screen taps arrived with no hand in
  frame; the last raised sighting was twelve seconds earlier. A tap now counts if a raised
  hand was seen within the last second, at the last known point. `handRaised` is also
  reset when the hand is lost, which it was not.
- **Tap sensitivity left alone.** Glass taps ran 6.2x to 43x, desk knocks 5.5x, typing 2x
  to 3.5x. The default (6x) sits just above the knocks; the hand gate is the real filter.

## 2026-11-05, later — Measure before tuning

Ivan said "tune it" before the app had ever been switched on, so there was no signal to
tune from. Instead of guessing new numbers, the app now writes every signal the
thresholds judge to `~/Library/Logs/Reach/signals <date>.csv` (pinch ratio, confidence,
raised, audio onset, tap decisions), and the panel shows the live pinch ratio and last tap
strength. Thresholds get set from that file after a real run.

Two false-trigger traps closed on sight. A typing hand reads as a pinch to the pose model
and a keystroke sounds like a screen tap, so: the pointer only follows a hand whose index
tip is above its wrist in the frame (raised, not resting on the keyboard), and neither a
pinch nor a tap counts within 0.3 s of a physical keystroke. The keystroke clock comes
from `CGEventSource.secondsSinceLastEventType`, which needs no permission.

Hand size for the pinch ratio is now the longest of three palm edges rather than one,
because a palm turned edge-on foreshortens any single edge and inflated the ratio.

## 2026-11-05 — First build

Built from nothing in one session on Ivan's ask for a camera-based "touchscreen". The
first decision was the honest one: the camera cannot see the glass, so this is a pointer
driven by hand pose plus a click driven by the sound of a tap, not contact detection.
Prior art checked on GitHub: every hand-mouse project is Python, OpenCV, and MediaPipe;
Project Sistine (3.4k stars) is the only one that detects real contact, and it needs a
mirror. Nothing native, nothing menu bar, so this is new.

Why Vision over MediaPipe: it ships with macOS, runs on the Neural Engine, and the app
has zero dependencies to break. Why One Euro over a moving average: it is the standard
for pointer smoothing because it adapts, calm when still and responsive when moving.

Why the microphone: Ivan asked for every available input. There is no public IMU on
Apple Silicon Macs, so the mics are the only other sensor that can say anything about a
touch. A tap on glass is a sharp broadband transient, easy to hear against speech.
