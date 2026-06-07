# VisionBridge Manual Test Scenarios

Each scenario includes setup, expected behavior, and pass/fail.

## 1) Empty hallway
- **Setup:** scanning on, clear hallway, no moving objects.
- **Expected TTS:** after ~10s, one line: "No obstacles detected."
- **Pass:** no repetitive chatter; line repeats no more than once per 10s.

## 2) One person crossing left→right
- **Setup:** one person enters frame left to right at ~2-4m.
- **Expected TTS:** person announcement with directional phrase.
- **Pass:** no rapid duplicate repeats while person remains similar distance.

## 3) Crowded sidewalk
- **Setup:** 6+ mixed objects in frame.
- **Expected TTS:** high-priority speaks first; low-noise mode suppresses floods.
- **Pass:** understandable output; no overlapping speech.

## 4) Vehicle near curb
- **Setup:** parked/moving car or bus in front/side.
- **Expected TTS:** vehicle class and approximate distance phrase.
- **Pass:** class makes sense and does not oscillate every frame.

## 5) Night low-light
- **Setup:** dim environment.
- **Expected TTS:** fewer announcements, no nonsense distances.
- **Pass:** app remains stable; no crash.

## 6) Lens smudge
- **Setup:** partially smear lens.
- **Expected:** lens warning fields update in payload HUD.
- **Pass:** warning appears without speech spam.

## 7) Rapid camera pan
- **Setup:** quickly pan phone left/right.
- **Expected:** stale queue flush; old scene announcements stop quickly.
- **Pass:** no lingering old-object speech after scene change.

## 8) Frame-edge partial objects
- **Setup:** object mostly outside frame edge.
- **Expected:** heavily occluded boxes filtered, fewer false announcements.
- **Pass:** object announced only when mostly visible.

## 9) Background/foreground transition
- **Setup:** start scan, home button/app switch, return.
- **Expected:** scanning state recovers, no runaway TTS.
- **Pass:** app resumes without duplicate rapid announcements.

## 10) Headphones connect/disconnect
- **Setup:** connect and disconnect headset while scanning.
- **Expected:** speech continues via available route.
- **Pass:** no crash, no stuck muted state.
