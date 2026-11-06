# PLAN — Reach

## Built (0.1, 2026-11-05)

- Menu bar app, no Dock icon, one popover.
- Vision hand pose at 30 fps on the built-in or Desk View camera, all 21 joints kept; the
  knuckles drive the pointer.
- One Euro smoothing with a single user-facing slider, plus a 5 px dead zone, an aim pin
  while the thumb closes, and a 14 px drag slop (added 2026-11-05 after the first day's use).
- Finger extension per finger, two-finger scroll, middle-pinch right-click, fist hold.
- Two-point calibration (top-left, bottom-right) with a stillness check.
- Pinch to click and drag, hysteresis plus three frames of evidence.
- Microphone onset detector for tap-on-glass clicks, gated on a visible hand.
- Permission rows that live-refresh while System Settings is open.
- Launch at login.

## The 60-second tuning protocol

Turn Reach on with the panel open, then, with a hand up to the camera:

1. Point at one spot and hold the hand as still as you can, ten seconds.
2. Pinch and release, five times, a second apart, without moving the hand.
3. Pinch, move the hand across the screen, release. Twice.
4. Thumb to middle finger with the index out, release. Three times.
5. Index and middle up, others curled, move the hand up and down for five seconds.
6. Make a fist and move the hand around for five seconds.
7. Type one sentence on the keyboard.
8. Quit Reach from the panel.

Then: `open ~/Library/Logs/Reach` and hand the newest csv over. Thresholds are set from it.

## Next, in order

1. **Decided 2026-11-05: pinch is the click.** Proven in the fourth run (five pinches, 188
   mouse-down frames). Tap-to-click stays in the panel as an opt-in, off by default,
   because the front camera never sees the hand between pointing and touching the screen.
   Ivan chose not to spend a run on Desk View. If anyone does, the protocol is above.
3. **Knocks and taps sound alike.** Desk knocks hit 5.5x, soft glass taps 6.2x, hard ones
   up to 43x. The microphone alone cannot separate them; the raised-hand gate is what does.
7. **Tap localisation.** The mic array has several capsules; a tap on the left of the
   glass reaches them in a different order than one on the right. Cross-correlating
   channels could give a coarse x position and confirm the camera's estimate. Needs a
   multichannel input format, which `AVAudioEngine` exposes on this hardware.
4. **Done 2026-11-05: right-click and scroll.** Thumb-to-middle pinch for secondary click,
   index-and-middle-up for scroll, fist to hold. Built from the extension test (tip farther
   from the wrist than the middle joint), not yet tuned from a log: the `pose` rows carry
   the finger digits and the hand-to-cursor gap, so the next run can tune them.
5. **Multi-display.** The engine maps to `NSScreen.main` only.
6. **Hover intent.** Ignore the pointer when the hand is resting (very low velocity for
   several seconds) so it does not drift across the screen while you read. Partly covered
   by the stillness gate and the fist hold.
8. **Steadiness from data.** The 17:02 run set the click (on release, at the point aimed
   a quarter second before the pinch) and the pinch gate (0.22 / 0.30). Still open: the
   dead zone. It absorbed only 18% of pointing frames; the `pose` row now logs the
   per-frame step, and the ten-second hold in the protocol is what sizes it.

## Open questions

- Should pinch and tap both be on by default, or is a single click method less confusing
  for a first run?
- Is the Desk View camera actually better for this? It sees hands over the keyboard, but
  the pose model was trained on front-facing hands.
