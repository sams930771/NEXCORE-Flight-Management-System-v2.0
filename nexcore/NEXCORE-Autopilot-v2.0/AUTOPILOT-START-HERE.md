# NEXCORE FMS 2.0 — Integrated Ship + Summoning Pocket

This is the new integrated controller. Use `ship`, not the older `fms` program. It installs beside the existing calibration package in `/nexcore_fms_ap`. Do not run both controllers at once. Existing calibration records and startup files are left alone.

## What is ready

- Integer-only burner hold, range **5–500**, using the altitude sensor on `back`. Initial empirical baseline is **60**, mass **477.00 kpg**. H captures the actual current balanced burner setting and current sensor altitude. Default hold deadband is 0.5 raw altitude units, so it does not chase the known 0.41-unit bobbing. Gains and response limits remain initial commissioning values, not proven flight tuning.
- Confirmed burner enable: `redstone_relay_2`, output `top`, `setOutput("top", true)`. X, link failure, and navigation failure never request burner-off. Fuel or hardware failure can still remove lift.
- Shared speed control using `Create_RotationSpeedController_3`. Only the tested target speeds **0 and 1** are enabled. This is a commanded controller target, not an RPM measurement at the propellers.
- Latest authoritative bearing matrix, with zero-speed interlock and a configurable 3-second coasting wait before direction changes.
- GPS-coordinate summon, compass-reference heading, conservative approach/coasting, short turn pulses, arrival radius, and progress timeout.
- Paired wireless pocket remote with GPS fix, acknowledgements, two-step arming, per-session sequence checks, stale-message rejection, and link-loss stop. Pair keys are sent in the radio payload; this is simple in-world pairing, not encrypted or cryptographically authenticated communication.
- Optional raw velocity sensor, gear-running and swivel-target telemetry. Neither velocity sensor is assumed to be a signed world-axis speed sensor. Mechanical gear steering is observe-only in this first integrated version; it is not driven alongside differential yaw.

| Maneuver | Bearing 1 | Bearing 2 | Bearing 3 | Bearing 4 |
|---|---:|---:|---:|---:|
| Forward | 0 | 1 | 1 | 0 |
| Reverse | 1 | 0 | 0 | 1 |
| Left | 1 | 0 | 1 | 0 |
| Right | 0 | 1 | 0 | 1 |

Stop commands shared controller target **0**. A bearing value of 0 is a direction setting, not a stop setting. Autonomous navigation uses forward travel and left/right alignment; reverse mapping is retained but active reverse braking is not commissioned.

## 1. Upload the files

Upload the CONTENTS of this ZIP to the ROOT of your GitHub repository, preserving `nexcore/ap/` and replacing `install.lua`. The root must contain `ship.lua`, `setup_ship.lua`, `pocket.lua`, `autopilot_test.lua`, and `install.lua`.

Do not upload just the ZIP: the installer fetches individual raw files.

On the ship computer, one command per line:

```text
wget https://raw.githubusercontent.com/sams930771/NEXCORE-Flight-Management-System-v2.0/main/install.lua install_ap.lua
install_ap ship
cd /nexcore_fms_ap
autopilot_test
```

On the wireless pocket computer:

```text
wget https://raw.githubusercontent.com/sams930771/NEXCORE-Flight-Management-System-v2.0/main/install.lua install_ap.lua
install_ap pocket
cd /nexcore_fms_ap
pocket
```

If `install_ap.lua` already exists, rename it before downloading the replacement. Installer arguments are `install_ap ship [branch] [repository-folder]` or `install_ap pocket [branch] [repository-folder]`. Installation never runs flight code or changes startup. Existing destination/staging folders are refused rather than overwritten. For future upgrades, preserve `ship_settings.txt` and `pocket_settings.txt`.

## 2. Pair the two computers

The pocket setup prints its computer ID and asks for the ship ID (your diagnostics identify ship computer **0**) and a pair key of at least 8 characters. Choose your own key.

On the ship run:

```text
setup_ship
```

Enter the pocket's ID and the SAME key. It also asks whether GPS has been verified to follow actual ship movement in world coordinates. Answer NO until verified. A single stationary fix does not prove moving-ship support. Answering NO permits local altitude-hold testing but blocks propulsion arming. Re-run setup later to update the confirmation.

Both need wireless modem coverage and working GPS hosts. Ship wireless modem is `left`; `bottom` and `top` are wired. The pocket must be a wireless pocket computer. The pocket program must remain open during travel: ship stops propulsion after **8 seconds** without a valid paired message. It does not shut off the burners. Default summon range is **128 blocks**, further limited by actual radio/GPS coverage. There is no relay network in this version.

## 3. FIRST LIVE TEST: altitude hold only

End the older calibration program with Q if supported. Confirm propulsion physically stopped. Keep the known balanced integer setting **60** on all four burners and a clear test area.

Run:

```text
ship
```

It requests shared drive target **0** at startup. Burner settings and activation are not written until H. Wait for sensor readings, then press **H**. H captures the current altitude, adopts the current equal burner setting as its baseline, and enables the tested burner relay.

Watch the burner READBACK line and altitude. Burner changes are whole integers, limited to **one integer per two seconds** and within **10 integers of the captured baseline** by default. All four must initially read equal valid integers. The default deadband accommodates the previously observed bobbing rather than trying to remove every small oscillation.

Do not arm propulsion yet. Test **Up** once for a bounded 1-unit altitude increase, observe the delayed physical response, and use Down to return only after the response is understood. If response diverges, press **F** to freeze burner commands at their last settings and stop propulsion. F and X never issue relay-off. Active altitude stabilization has not been proven on your ship simply because the software tests pass.

After faults, output calls must be resolved before H is used again. H deliberately recaptures the current balanced setting and altitude; it does not restore a stale target automatically. Physical fuel, thermal and lift limits still apply.

## 4. Establish the compass reference and heading

The installed Navigation Table implementation returns an angle to the target provided by its item. It returns zero when no target exists. The degree getter returns degrees; the Rad getter converts that value into radians. A normal compass generally references world spawn, NOT world north.

For arbitrary pocket GPS destinations, a relative angle to an UNKNOWN spawn position is insufficient. This version needs a compass target whose exact fixed WORLD X/Z you know. A compass bound to a fixed lodestone in the same dimension is a practical option. Keep it installed on the table. Alternatively use a normal compass only if you know its actual spawn target coordinates.

Use a fixed reference preferably well away from the flight area; navigation is inhibited within **8 blocks** of the reference. Adding blocks/items changes ship loading; update mass metadata and check the burner baseline if the mass changes.

With propulsion stopped, exit the ship program by F, wait for drive target zero, then Q. Run:

```text
setup_ship heading
```

Enter the known compass target's world X/Z and explicitly confirm that exact target is installed. Align your PLAYER VIEW along the ship's NOSE; enter the exact F3 yaw, or N/E/S/W if the nose really is aligned to that cardinal direction. Player facing and table placement alone are not ship heading. No rotation or output command is issued by setup.

The calculation uses GPS bearing to the known compass reference minus the table's relative angle plus a calibrated mounting offset. Your test established that a left turn increases the table angle. Stored offset handles mounting orientation. GPS position is used to compensate for changing bearing to the fixed reference as the ship moves; we do not assume the table angle is an absolute compass heading or substitute GPS course for stationary heading.

Restart `ship`, press H and verify the displayed heading against the ship's known orientation before arming. Validate a short turn in an open test area before an actual summon. A missing compass can still return a plausible zero; these two methods expose no target-valid flag. Keep the item installed. The software also checks that sustained driven-forward GPS course broadly agrees with calculated heading and stops on a large disagreement, but that cannot detect every reference failure while stationary.

## 5. Arm and summon

After successful local lift testing, verified GPS movement, and reference/heading calibration:

- Keep the ship's `ship` program running with H altitude hold active.
- On the pocket, press **R**, then **Y within 10 seconds** to deliberately arm propulsion at zero speed. Local R/Y on the ship is also supported.
- Confirm the pocket GPS fix is current and represents your intended destination. Stand in an open area clear of obstacles.
- Press **S**. The ship acknowledges acceptance or displays a reason for rejection.
- Leave the pocket program running. S sends a location SNAPSHOT, not a continuous follow target. A new S command can replace the target while armed.

The ship aligns with short 0.4-second turn commands and a coasting pause, then travels forward. GPS-derived speed limits can command coasting. Approach uses conservative speed targets and a configured assumed stopping deceleration, which still needs live measurement. It requests propulsion zero inside the default **8-block horizontal arrival radius**. That is an arrival/coasting indication, not a promise of physically stationary position or a measured braking distance. It does not actively reverse-brake, hover over a point, land, or turn burners off.

The ship retains its CAPTURED altitude-sensor target during summon. Pocket Y is retained in destination telemetry but never directly becomes a burner target. It does not mix sensor datum with GPS Y and does not descend to the player's ground level.

## Controls

Ship:

| Key | Action |
|---|---|
| H | Capture current altitude and equal integer burner baseline; enable relay |
| Up / Down | Change held altitude by 1 within a 5-unit commissioning envelope |
| R then Y | Deliberately arm at zero speed |
| X / Space | Stop propulsion and cancel mission; retain altitude hold |
| F | Stop propulsion and freeze burner demand; relay remains requested on |
| Q | Exit only after F, propulsion disarmed, and zero target acknowledged |

Pocket:

| Key | Action |
|---|---|
| R then Y | Two-step propulsion arm |
| S | Summon to current valid pocket GPS snapshot |
| X / Space | Emergency propulsion stop; altitude hold continues |
| T | Status request |
| Q | Send propulsion stop and exit |

No remote command changes burner baseline, disables burner redstone, or silently arms propulsion. Rejected commands do not start a mission. Re-arm deliberately after emergency stop, data loss, or link-loss stop.

## Failure behavior and limits

- Stale height, burner output errors or burner/relay disconnection freeze altitude commands at the last settings and stop propulsion. The controller cannot restore lift through physically disconnected hardware.
- GPS/heading loss, excessive altitude deviation, lack of progress, or expired remote heartbeat stops propulsion while retaining healthy altitude hold.
- A reconnected drive is commanded zero. No mission resumes automatically. R/Y and a fresh summon are needed.
- Every propeller direction change happens with acknowledged speed TARGET zero and a timed coast wait. No shaft-speed sensor is exposed, so the wait is not measured proof of physical standstill. You verified zero target stops the drivetrain; revalidate the wait under load.
- CC:Tweaked workers are cooperative. Sensor/display loops continue while another mod call yields, but a non-yielding mod bug can stall the computer. A pending actuator command cannot be forcibly cancelled; a late positive-speed write may execute before the subsequent stop. Keep a separate physical propulsion cutoff for this case.
- Neither GPS nor the Navigation Table detects terrain, trees, buildings, or other ships. This version is for supervised OPEN-AIR test routes at a clear altitude, with no automatic takeoff, landing, obstacle avoidance or dimension travel.
- Do not enable startup auto-arming. Reboots lose sessions and disarm navigation. Burner settings/relay state after a power interruption depend on the blocks; verify them rather than assuming persistence.

## Verification performed

Parsed all Lua files using Cobalt 0.9.9 from the installed CC:Tweaked runtime. Existing 35 assertions plus 31 new autopilot assertions pass (66 total). New checks cover exact latest direction patterns, angular wrap, calibrated reference heading, translation compensation, turn selection, integer lift commands and replay/expiry/peer rejection.

Actual program simulation scenarios pass: straight summon arrival, turning approach with pulsed steering, remote emergency stop, GPS loss, link loss, ongoing integer burner hold in stop cases, and zero-speed direction writes. Pocket scenarios pass handshake, R/Y confirmation, valid GPS summon, refusal without GPS, X stop and Q exit. Installer scenarios pass ship/pocket manifests, failed download handling and existing-install protection.

All integration scenarios use mock peripherals and simplified motion. They validate software transitions, not real Minecraft dynamics, radio range, GPS ship compatibility, lift tuning, compass calibration, stopping distance or terrain clearance. The first live test is ALTITUDE HOLD ONLY.
