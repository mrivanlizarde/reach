# PLAN — Reach

## Built (0.1, 2026-11-05)

- Menu bar app, no Dock icon, one popover.
- Vision hand pose at 30 fps on the built-in or Desk View camera, index tip drives the pointer.
- One Euro smoothing with a single user-facing slider.
- Two-point calibration (top-left, bottom-right) with a stillness check.
- Pinch to click and drag, hysteresis plus three frames of evidence.
- Microphone onset detector for tap-on-glass clicks, gated on a visible hand.
- Permission rows that live-refresh while System Settings is open.
- Launch at login.

## The 60-second tuning protocol

Turn Reach on with the panel open, then, with a hand up to the camera:

1. Open hand, still, three seconds.
2. Pinch and release, five times, a second apart.
3. Tap the screen glass five times, a second apart.
4. Knock the desk twice. Type one sentence on the keyboard.
5. Quit Reach from the panel.

Then: `open ~/Library/Logs/Reach` and hand the newest csv over. Thresholds are set from it.

## Next, in order

1. **Run tap-to-click on the Desk View camera.** Pinch clicks and drags are proven (fourth
   run, 2026-11-05 14:32: five pinches, 188 mouse-down frames). Glass taps are not: the
   front camera never sees the hand between pointing and touching the screen, so every tap
   arrived 3 to 20 s after the last sighting. The five-second grace window makes "point,
   then reach and tap" work; Desk View looks down over the approach and may keep the hand
   in frame the whole way. Same protocol, camera set to Desk View.
2. **Decide whether tap-to-click earns its place.** If Desk View does not hold the hand, the
   honest default is pinch only, with tap as an opt-in.
3. **Knocks and taps sound alike.** Desk knocks hit 5.5x, soft glass taps 6.2x, hard ones
   up to 43x. The microphone alone cannot separate them; the raised-hand gate is what does.
7. **Tap localisation.** The mic array has several capsules; a tap on the left of the
   glass reaches them in a different order than one on the right. Cross-correlating
   channels could give a coarse x position and confirm the camera's estimate. Needs a
   multichannel input format, which `AVAudioEngine` exposes on this hardware.
4. **Right-click and scroll.** A two-finger pinch for secondary click; an open palm moving
   vertically for scroll.
5. **Multi-display.** The engine maps to `NSScreen.main` only.
6. **Hover intent.** Ignore the pointer when the hand is resting (very low velocity for
   several seconds) so it does not drift across the screen while you read.

## Open questions

- Should pinch and tap both be on by default, or is a single click method less confusing
  for a first run?
- Is the Desk View camera actually better for this? It sees hands over the keyboard, but
  the pose model was trained on front-facing hands.
