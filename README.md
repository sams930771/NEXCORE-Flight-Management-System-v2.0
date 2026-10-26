# NEXCORE FMS 2.0 — Aerostate

Independent implementation based on the supplied 18-device diagnostics. This is not an exact migration of v3.5.2; that source was not supplied. No files in your Minecraft save have been changed.

## Start with the one-integer burner test

1. Copy the contents of this package into a folder named `nexcore_fms` on computer 0. Keep the inner `nexcore` folder intact. The computer's existing program/startup can remain in place while you prepare the folder. Run only one flight-control/calibration program at a time.
2. In the computer terminal:

   ```lua
   cd /nexcore_fms
   selftest
   audit read
   ```

   `audit.txt` inventories current names/types/methods. `readings.txt` trials only zero-argument getters, preserves all return values, and marks failures/timeouts. A successful getter still needs unit and meaning checks. The program does not invoke any setter during this audit.
3. Keep propulsion mechanically disengaged for this first burner test. The calibration program controls only burners; it cannot establish or stop unknown propulsion behavior. Ensure the altitude sensor moves with the ship. Check that `back.getHeight()` changes when the ship actually rises and has the expected direction and resolution.
4. Inspect the adjustable burner's actual GUI/documentation for its allowed integer scroll limits. Start:

   ```lua
   calibrate
   ```

   Enter the validated lower and upper integer limits when prompted. No range is guessed. Alternatively pass your two validated numbers as arguments. Starting the program only reads hardware.
5. Tap **+** (the `=` key, with or without Shift, or keypad +). Each physical key press raises **each of the four burners by exactly one raw integer** from its latest measured setting. Held-key repeats are ignored. While writes are pending, further presses are ignored. The program checks all four readbacks before observing stability. The test itself is the first controlled trial of `setScrollValue(integer)`; method names alone did not confirm its signature.
6. Observe the response before pressing + again. Each accepted + resets the settling timer and stability observation. No autonomous ramp is used. If increasing scroll reduces lift or does something unexpected, freeze the test and investigate the mapping.
7. After a successful step and at least **1 raw altitude unit of rise from the starting height**, press **A** to confirm the ship is freely airborne, without ground/ceiling contact or support. This operator confirmation is required because a constant altitude reading alone cannot distinguish hover from being physically held in place.
8. Following the last acknowledged change, allow **30 seconds of settling**, then **30 continuous seconds of stable altitude readings**. If A is pressed later, the stable window starts later. Default stability requires a total height range no greater than **0.02 raw units**, and endpoint drift no greater than **0.003 raw units/second**. Oscillation also prevents recording. These are editable observation criteria in `nexcore/config.lua`, not established sensor precision.
9. On success, the screen says **HOVER RECORDED** and appends a record to `hover_calibration.jsonl` in this folder. Burners retain their settings. A later + begins another observation; A is required again.

The record includes the mean/min/max altitude, all four exact burner scroll values, a common value if all four match, the stability duration, timestamp, and **429.50 kpg as reported**. That mass is metadata, not a conversion into throttle. Hover observations apply to the tested mass, altitude, loading, and thermal conditions.

**SPACE/X or Ctrl+T freezes further calibration commands while retaining burner settings.** It does not reduce lift or stop a mechanically running propulsion system. A setter already in progress cannot be cancelled. A timeout or partial failure freezes the test; four setters are not an atomic transaction and may have applied unevenly. Inspect each burner and use **R** only after resolving the cause. R discards the interrupted step and begins a fresh observation baseline; it never automatically finishes pending changes.

A slowly drifting ship can appear stationary when a sensor rounds to whole units. Inspect `readings.txt`, lengthen the window for thermal lag/coarse sensors, and validate against independent GPS observations. The saved value is an empirical hover observation, not proof of an indefinitely stable equilibrium. Do not infer a complete altitude/power curve from one observation.

## What is integrated

- Exact name/type/method manifest for all 18 devices, including the second velocity sensor and altitude sensor. See `HARDWARE.md` for every method in the log.
- Independent yielding workers for GPS, each sensor reading, each actuator, display, hardware checks, and bounded gear steering. Slow/yielding GPS and peripheral calls do not block the other cooperative workers.
- GPS altitude hold with filtered vertical velocity, bounded PI-D, anti-windup, target limits, output quantization, and slew limits. A validated `getHeight()` source is available instead. No automatic source switch mixes GPS world Y with an unverified sensor datum.
- Four-propeller collective/differential mapping through calibrated raw scroll endpoints per bearing. The software does not equate scroll value with RPM.
- Optional navigation-relative steering through differential thrust OR a sequenced gearshift; never both yaw controllers at once. This follows the Navigation Table's tested relative target, not an invented compass heading or GPS waypoint route.
- Read-only pressure, both velocity sensors, Navigation Table, swivel TARGET angle, and gear-running telemetry. Raw units/return shapes remain visible until verified.
- Independent propulsion neutral command, preserving burner control. This requires a tested neutral setting that actually produces zero thrust.
- Fault latching, stale-sensor checks, neutralization retries, bounded call watchdogs, and explicit rearming after reconnection.
- A shared local command module for future pocket integration. No modem control receiver or unauthenticated remote command path is enabled.

## Calibrate before enabling the full FMS

`fms` starts in OBSERVE on every boot. No burner, propeller, swivel, or gear movement is issued at boot. The zero-argument read-only telemetry trials run; failures remain visible. Configuration flags default to false.

After the first test, retain `hover_calibration.jsonl` and `readings.txt`. Use measured raw endpoints, integer increments and hover settings to populate the configuration. The calibration log is deliberately not auto-imported into active flight settings: it does not establish safe low/high endpoints, propulsion neutral, or gear arguments.

### Burners and altitude

- Set each lift channel's `low`, `high`, and raw `step`. Low/high mean low/high **lift**, and need not be numerically ascending. They must be validated operating bounds, not guessed API limits.
- Convert a measured hover scroll into normalized hover: `(hoverRaw - low)/(high - low)`. The configuration uses a common normalized `lift.hover`; ensure each channel's calibrated mapping produces the recorded balanced hover settings at that common demand.
- Validate mass/load, fuel availability, thermal delay, increasing-lift direction, and repeated hover behavior before setting `lift.confirmed=true`.
- For GPS control, confirm that fixes follow the moving ship and set `gps.verifiedMoving=true`. CC GPS reports the computer location; ship-mod compatibility must be tested. For height control, set `source="height"`, validate datum/scale/offset, and set `height.verified=true`.
- Gains are conservative starting placeholders, not flight-tested tuning for this ship. Begin with small target changes. Determine thermal delay first; excessive integral action can produce large delayed oscillations. Default target changes are 1 unit and limited to within 5 units of measured altitude and the configured world limits. This is altitude control, not roll/pitch stabilization or terrain avoidance.
- H requires fresh current burner scroll reads at first activation, then slews from those values toward the controller's demand. If the selected altitude source goes stale, the last burner demand is retained and propulsion stops; H must explicitly recapture a fresh altitude. This cannot guarantee altitude if fuel, lift hardware or world loading fails.

### Propellers

The exact names include the `aeronautics:` prefix. Each has only `getScrollValue` and `setScrollValue`.

| Demand | Bearing 1 | Bearing 2 | Bearing 3 | Bearing 4 |
|---|---|---|---|---|
| Forward | forward/CCW intent | forward/CW intent | forward/CCW intent | forward/CW intent |
| Reverse | reverse/CW intent | reverse/CCW intent | reverse/CW intent | reverse/CCW intent |
| Turn left | reverse | reverse | forward | forward |
| Turn right | forward | forward | reverse | reverse |

Positive yaw means turn right. Mixing computes pair 1/2 = forward + yaw and pair 3/4 = forward - yaw, then scales together to prevent saturation. Physical CW/CCW viewing direction and actual thrust must be checked individually.

For each channel, calibrate `fwd`, `neutral`, `rev`, and raw `step` with the mechanical drive in its operating state. Test intermediate values as well as endpoints: the implementation interpolates raw scroll settings. Verify whether scroll controls blade pitch, speed, or something else. If it cannot give proportional reversible thrust and true neutral, leave `propulsion.confirmed=false`. Additional independently controllable drive hardware may be required; none is invented by this package. In particular, the log contains no rotation-speed-controller peripheral.

After validating all four channels, set `propulsion.confirmed=true` and choose a small signed cruise demand (`0..1` is currently accepted by validation; reverse mapping is supplied for future command extensions). P neutralizes all four outputs and waits for setter acknowledgements before enabling automatic constant cruise. Setter acknowledgement is not proof that physical thrust has already decayed. There is no automatic cruise on boot.

SPACE/X requests each calibrated neutral immediately, bypassing propulsion slew. Burners continue altitude hold. With unconfirmed propulsion calibration it cannot send an unknown stop value. The gearshift has no exposed `stop` method: an already running mechanical sequence can continue after propulsion neutral is requested. A hardware clutch/cutoff is needed if scroll-neutral cannot reliably remove thrust.

### Navigation and sequenced gearshift

- `getRelativeAngle` and `getRelativeAngleRad` exist; their reference target, arguments, output unit, wrapping and physical sign must be measured. Set `navArgs`, `navScaleToDegrees` and `navSign` accordingly. Radians require a tested conversion to degrees. No getter result is silently treated as absolute heading.
- For differential navigation steering, set `steering.mode="differential"` and `navVerified=true` only after verifying that positive converted error requires a right turn and that the propeller mapping reduces it. The default navigation mode is off.
- For gear steering, also set `gearConfirmed=true` and supply the tested `rotateArgs(step)` function. `step` is a bounded signed degree correction; the function must translate it into the device's actual argument convention, direction and limits. No default rotate signature is supplied. `move` is discovered but unused.
- Gear automation owns one command at a time, checks boolean `isRunning`, limits step/cooldown, and latches failures. Default `completionMode="busy-cycle"` requires observing running then stopped before another correction. For very short or synchronous sequences that never expose a running sample, it times out safely. Use `"return-is-complete"` only if experiments establish that a returned rotate plus idle `isRunning` really means completed movement.
- Check mechanical angular stops, maximum travel, backlash and drift. No verified current physical steering-angle sensor is exposed. The swivel getters report a target and cannot by themselves verify completed movement or support absolute recentering. Automated recentering, unlimited travel and disassembly/assembly commands are intentionally absent.
- Stale or invalid required navigation/gear telemetry stops propulsion while preserving lift.

### Velocity and GPS

Both `getVelocity` readings are displayed with sample ages and complete return values. The report does not establish scalar/vector shape, axis, reference frame, sign or units, so neither is used as vertical-speed feedback by default. Vertical speed is derived from the selected validated altitude source.

For `gps.locate`, maintain correctly configured GPS hosts and modem coverage. `bottom` and `top` expose wired-network methods. `left` lacks those methods; trial `isWireless` in `readings.txt` establishes its actual radio type. The program does not assume all three are wired or open rednet channels. GPS and all needed remote devices/chunks must remain available; this package does not add chunk loading.

## Full-system operation

From the installed folder, run `fms`:

| Key | Action |
|---|---|
| H | Capture current altitude and enable calibrated lift hold |
| Up / Down | Bounded altitude target change |
| P | Neutralize, then begin calibrated automatic cruise |
| SPACE / X | Propulsion neutral; preserve burner altitude control |
| F | Freeze burner demand and stop propulsion |
| R | Check recovery; never automatically rearm motion or lift hold |

A disconnected burner freezes lift control and stops propulsion; remaining burners retain the last common demand. Failed outputs retry that retained demand. A reconnected propeller is commanded neutral, never its previous cruise setting. After faults clear, use R, then H/P as appropriate. Sensor-only or monitor failures do not kill unrelated workers. Ctrl+T is intercepted, but a peripheral getter/setter may also report interruption as a fault; use SPACE/X for normal emergency neutral. Reboot/power loss cannot be caught and may leave the physical machinery at its last state.

CC:Tweaked parallelism is cooperative, not preemptive. A yielding stalled setter remains pending while other tasks continue, but cannot be forcibly cancelled or safely reissued in another worker. Its late completion may precede a later neutral command. A non-yielding mod bug can stall the whole computer. Software cannot guarantee a bounded physical shutdown during those failures; retain an independent mechanical propulsion cutoff.

Only after bench tests, optionally use `startup.lua.example` as the computer's startup file, adjusting its folder path if needed. It always starts OBSERVE and needs deliberate H/P activation.

## Verification

All Lua files were parsed with Cobalt 0.9.9 extracted from the installed CC:Tweaked 1.120.2 mod. Thirty-five assertions passed, including signed pair mixing, endpoint mapping, integer-step limits, PID anti-windup, emergency lift preservation, and stability-window rejection of short plateaus/drift/oscillation.

The actual calibration program also passed simulated event/peripheral runs for lift-off hover capture, held-key repeat rejection, and refusal to record a grounded plateau. A full FMS simulation passed observe-only boot, cruise, emergency propulsion neutral with ongoing burner updates, disconnection, and explicit recovery/rearming. These tests used mocked hardware and do not validate Minecraft method arguments, units, physics, or real network timing. Run the included `selftest` in CC:Tweaked before the first live test.

Official CC:Tweaked references: [peripheral discovery](https://tweaked.cc/module/peripheral.html), [GPS](https://tweaked.cc/module/gps.html), and [cooperative parallel workers](https://tweaked.cc/module/parallel.html). Mod-specific capabilities come from your supplied diagnostics, not guessed documentation.
