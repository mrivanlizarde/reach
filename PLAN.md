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

## Next, in order

1. **Live test on the M5 Pro with Ivan's hand.** Thresholds (pinch 0.28/0.40, tap onset
   6x) were set from Apple's sample and first principles, not from this room. Expect to
   tune both.
2. **Tap localisation.** The mic array has several capsules; a tap on the left of the
   glass reaches them in a different order than one on the right. Cross-correlating
   channels could give a coarse x position and confirm the camera's estimate. Needs a
   multichannel input format, which `AVAudioEngine` exposes on this hardware.
3. **Right-click and scroll.** A two-finger pinch for secondary click; an open palm moving
   vertically for scroll.
4. **Multi-display.** The engine maps to `NSScreen.main` only.
5. **Hover intent.** Ignore the pointer when the hand is resting (very low velocity for
   several seconds) so it does not drift across the screen while you read.

## Open questions

- Should pinch and tap both be on by default, or is a single click method less confusing
  for a first run?
- Is the Desk View camera actually better for this? It sees hands over the keyboard, but
  the pose model was trained on front-facing hands.
