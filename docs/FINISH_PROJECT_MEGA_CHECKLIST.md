# VisionBridge Finish Plan (Mega Checklist)

This is the full, implementation-focused path from current prototype to a finished product candidate.  
It includes:

- everything still needed,
- what is already done,
- what was attempted but did not work well,
- and concrete acceptance criteria for each area.

This document is intentionally long and explicit so the team can execute without ambiguity.

---

## 0) Executive Reality Check

### Current maturity

- **Vision core**: working (YOLOv8m Open Images V7, on-device CoreML and Python parity).
- **TTS guidance**: working and improved (queue/stack scheduler, dedupe, distance phrases).
- **Distance estimation**: heuristic and partially hardened (clamps, sanity bounds), not yet robust enough for production safety claims.
- **UX flow**: usable demo flow, not yet polished enough for broad user testing.
- **Reliability**: good for controlled demos, not enough evidence for diverse real-world conditions.

### Estimated remaining effort

- **Demo-solid**: hours to 1 day.
- **Field beta-ready**: several days with focused testing + tuning.
- **Production-grade assistive reliability**: multiple iterations with real-user feedback and safety review.

---

## 1) Product Definition Lock (Must Do First)

Before further coding, lock these decisions in writing:

1. **Primary mode**:
   - TTS-only guidance (current direction) as default.
2. **Distance trust language**:
   - "Estimated distance" (not exact).
3. **Supported hazard classes**:
   - Confirm final Open Images V7 subset and what is out-of-scope.
4. **Operating assumptions**:
   - Camera mount position, lighting expectations, movement speed assumptions.
5. **Safety disclaimer**:
   - App is assistive, not a replacement for cane/guide dog/orientation training.

### Acceptance criteria

- PRD, README, onboarding copy, and in-app disclaimers all say the same thing.

---

## 2) Vision Accuracy & Stability Work

### 2.1 Dataset + evaluation harness

Build a repeatable offline evaluation loop:

- Collect representative clips:
  - sidewalks, crosswalks, curbs, night, glare, rain, crowded scenes, fast pans.
- Label at least key classes and rough depth buckets.
- Add scripts to compute:
  - per-class precision/recall,
  - false-positive hotspots,
  - distance error buckets by class and range.

### 2.2 Class policy tuning

- Tune confidence thresholds globally and optionally per class.
- Decide whether some classes should be "detect but never speak."
- Add suppression rules for classes with poor practical value.

### 2.3 Frame-visibility filtering verification

Current: detections with mostly out-of-frame boxes are filtered by minimum in-frame area.

Need to validate:

- edge cases near frame borders,
- dynamic camera motion,
- whether threshold should be adaptive by class.

### 2.4 Tracking/identity consistency

- Improve stability of object IDs across jitter and brief occlusion.
- Reduce repeated speech due to track churn.

### Acceptance criteria

- Defined benchmark set with reproducible metrics.
- Clear class-level quality report.
- Measurable reduction in false positives and repeat chatter.

---

## 3) Distance Correctness Plan

Distance is the largest trust risk today.

### 3.1 Calibration pipeline

- Add guided calibration flow:
  - user places known object at known distance,
  - captures multiple samples,
  - computes per-device focal adjustment.
- Persist calibrated profile per device/configuration.

### 3.2 Distance confidence model

Expose confidence tiers for distance speech:

- **High confidence**: stable bbox, known class, low motion blur.
- **Medium**: acceptable but noisy.
- **Low**: uncertain; use broad language only ("near", "far").

### 3.3 Speech phrasing tied to confidence

- High confidence: numeric-ish ("about 2 meters").
- Low confidence: non-numeric ("nearby", "farther ahead").

### 3.4 Runtime safety constraints

Already partly done:

- clamp known height, focal length, bbox height,
- clamp output distance range.

Still needed:

- detect impossible frame-to-frame jumps and dampen,
- class-specific smoothing windows,
- explicit "distance unavailable" state for degenerate geometry.

### Acceptance criteria

- Distance error evaluated on reference set.
- Confidence-aware phrasing enabled and tested.
- No absurd spoken distances in stress tests.

---

## 4) TTS Experience (Biggest UX pain point)

Current state improved significantly, but still needs systematic tuning.

### 4.1 Signal-over-noise policy

Define strict rules:

- max lines per time window,
- priority preemption behavior,
- cooldowns per class/object/spatial cell,
- conditions for silence.

### 4.2 User modes

Implement and test at least:

- **Low noise** (default),
- **Normal**,
- **Critical-only** (speak only HIGH + very near).

### 4.3 Voice/utterance quality

Current:

- voice style picker,
- rate/pitch variations.

Still needed:

- verify best default voice per iOS version/device,
- fallback voice matrix when premium/enhanced voices unavailable.

### 4.4 Anti-overlap guarantees

Even with queue controls, finalize:

- no stale backlog after scene change,
- no rapid repeating same semantic message,
- bounded queue depth with drop policy metrics.

### Acceptance criteria

- "Noisy/overlapping" user complaint reproduced and resolved on test scripts.
- TTS remains understandable in busy urban clips.

---

## 5) Runtime Scheduling & Performance

User asked for real-time scheduling with priority behavior. Current TTS scheduler is priority-aware, but broader runtime still needs profiling.

### 5.1 End-to-end latency budget

Track:

- camera frame ingest,
- model inference,
- post-process/tracking,
- speech decision,
- utterance start delay.

### 5.2 Frame drop and backpressure policy

- ensure one-in-flight semantics are explicit and measured,
- avoid queue growth under load.

### 5.3 Device performance matrix

Test older/newer devices:

- sustained thermal behavior,
- battery usage,
- FPS and speech responsiveness over 15+ minute sessions.

### Acceptance criteria

- Latency + throughput dashboard available.
- No unbounded queueing anywhere in vision->speech path.

---

## 6) UX and Accessibility Polish

### 6.1 Onboarding and trust setup

- Explain what app can/cannot detect.
- Explain distance is estimated.
- Provide quick audio examples and guidance for interpretation.

### 6.2 Settings simplification

- Group expert settings under advanced.
- Keep daily-use toggles minimal.

### 6.3 Failure-state UX

- model missing,
- camera denied,
- low confidence scene,
- no detections,
- bridge fallback status if used.

### Acceptance criteria

- First-time user can start scan and understand output without team help.

---

## 7) Safety, Risk, and Legal Hygiene

### 7.1 Safety behavior requirements

- Never present output as guaranteed truth.
- Add conservative language for uncertainty.
- Add quick stop/mute gesture or control.

### 7.2 Documentation/legal

- Add disclaimers in app and docs.
- Ensure marketing language avoids over-claiming.

### Acceptance criteria

- Safety and disclaimer copy consistent across app/docs/demo script.

---

## 8) QA Matrix (must run repeatedly)

### 8.1 Automated

- Python tests (already in place; keep green).
- Swift package build.
- iOS app build.

### 8.2 Manual scenarios

1. Empty hallway.
2. One person crossing left to right.
3. Crowded sidewalk.
4. Vehicle at curb.
5. Night low-light.
6. Lens smudge scenario.
7. Rapid camera pan.
8. Partial objects at frame edge.
9. App background/foreground transitions.
10. Headphones connect/disconnect.

### 8.3 Regression checklist

- class output sanity,
- speech cadence,
- distance language,
- no speech overlap/backlog artifacts.

---

## 9) Engineering Debt / Refactor List

### 9.1 HearingEngine decomposition

Current `HearingEngine` has grown large. Split into:

- scheduler,
- dedupe policy,
- phrase builder,
- bridge source,
- telemetry logger.

### 9.2 Config centralization

- unify thresholds in one config surface (with defaults and docs).
- avoid "magic numbers" spread across files.

### 9.3 Telemetry and observability

Add optional local logs:

- queue depth over time,
- dropped utterance reasons,
- distance clamp events,
- confidence distributions.

---

## 10) Release Readiness Checklist

Before calling it "finished":

- [ ] PRD and README match actual behavior.
- [ ] iOS settings reflect final feature set.
- [ ] Distances are confidence-aware and user-safe.
- [ ] TTS noise acceptable in target environments.
- [ ] Model bundle and runtime validated on clean install.
- [ ] Demo script, fallback script, and known limitations prepared.
- [ ] Final risk list documented and signed off internally.

---

## 11) What We Tried That Did Not Work Well (or was rolled back)

This is the candid log of attempted directions and outcomes.

### 11.1 YOLO-World open-vocabulary path (rolled back)

What was attempted:

- Switched from YOLOv8n to YOLO-World (`yolov8s-worldv2`).
- Added `set_classes` for hazard-focused prompts.
- Exported CoreML with custom class order/mapping.

Problems encountered:

- Inconsistent practical accuracy for target use compared to expectation.
- Class confusion persisted (example category: trash can vs bottle concerns).
- Export/runtime complexity increased due to class-order semantics.
- CLIP dependency and first-run SSL/cert issues created fragility in workflow.

Outcome:

- Reverted to YOLOv8n pretrained COCO classes for stability and predictability.

### 11.2 SSL failure during YOLO-World CLIP path

What happened:

- `set_classes` attempted to pull CLIP assets and hit certificate verification failure in environment.

Mitigation tried:

- Introduced `certifi` / CA bundle strategy to unblock export.

Outcome:

- Export could be made to work, but broader YOLO-World direction still rolled back due to product-quality concerns.

### 11.3 TTS overlap/noise behavior (initial implementation)

What happened:

- Rapid repeating lines and stale queue effects in dynamic scenes.
- Too many announcements in dense scenes.

Mitigation:

- Introduced priority scheduling (high stack + normal queue), dedupe, cooldowns, queue caps, TTLs, scene flushes.
- Added voice/verbosity controls and stricter gating.

Status:

- Improved significantly; still needs field validation and possibly critical-only mode tuning.

### 11.4 "No hearing whatsoever" request + immediate correction

What happened:

- Direction briefly shifted toward disabling hearing entirely.
- Requirement immediately corrected to "still want TTS."

Outcome:

- Kept TTS, removed spatial-audio behavior direction, continued optimizing TTS-only flow.

---

## 12) Immediate Next 10 Tasks (Recommended)

1. Add **critical-only** speech mode.
2. Add TTS telemetry (queue depth, dropped lines, repeat suppression reasons).
3. Run 10 curated real-world videos and collect logs.
4. Tune cooldowns and queue parameters from evidence.
5. Add distance confidence tiers + confidence-aware phrase templates.
6. Build in-app calibration wizard for focal/distance tuning.
7. Add "uncertain distance" speech fallback.
8. Update PRD sections to reflect final TTS-only/no spatial behavior.
9. Record polished demo run + fallback runbook.
10. Freeze settings defaults and cut a release candidate tag.

---

## 13) Definition of Done (Proposed)

Project is "finished" when:

- it performs consistently on representative real-world tests,
- speech guidance is understandable and not overwhelming,
- distance language is safe and confidence-aware,
- docs/UI/behavior are aligned,
- and remaining limitations are explicitly documented.

Until then, treat as an advanced prototype approaching beta.

