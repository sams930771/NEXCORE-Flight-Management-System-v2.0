return {
  airship={mass=429.50,massUnit="kpg (reported; unverified)"},
  -- OBSERVE on every boot. No automatic output restoration after a reboot.
  tick=0.1, readPeriod=0.5, stale=3, callTimeout=2, refresh=1,
  monitor="monitor_0", altitude="back", nav="navigation_table_1",
  swivel="swivel_bearing_1", gear="Create_SequencedGearshift_1",
  velocities={"velocity_sensor_1","velocity_sensor_2"},
  gps={timeout=1, period=0.5, verifiedMoving=false},
  -- getHeight datum, unit, and motion tracking must be checked before use.
  height={verified=false, scale=1, offset=0},
  -- Stability is measured in raw getHeight units until its units are verified.
  calibration={settleSeconds=30,windowSeconds=30,tolerance=0.02,
    maxSlope=0.003,minRise=1,applyTimeout=5},
  source="gps", -- "gps" or "height"; never switch datums automatically.
  limits={min=-64,max=320,targetStep=1,maxOffset=5,maxVerticalSpeed=20},
  pid={kp=0.015,ki=0.001,kd=0.04,integralLimit=30},
  lift={confirmed=false,hover=0.5,slew=0.02,
    -- low/high: raw setScrollValue endpoints that produce LOW/HIGH lift.
    -- Endpoints, step and hover are deliberately unconfigured.
    channels={
      {name="aeronautics:adjustable_burner_2",low=false,high=false,step=false},
      {name="aeronautics:adjustable_burner_3",low=false,high=false,step=false},
      {name="aeronautics:adjustable_burner_4",low=false,high=false,step=false},
      {name="aeronautics:adjustable_burner_5",low=false,high=false,step=false},
    }},
  propulsion={confirmed=false,slew=0.25,cruise=0.2,
    -- Each value is a RAW SCROLL SETTING, never an assumed RPM.
    -- Test that neutral actually stops THRUST with the mechanical drive running.
    -- fwd/rev must produce opposite thrust, not just opposite visual rotation.
    -- 1,3 front: intended forward CCW; 2,4 rear: intended forward CW.
    channels={
      {name="aeronautics:propeller_bearing_1",fwd=false,neutral=false,rev=false,step=false},
      {name="aeronautics:propeller_bearing_2",fwd=false,neutral=false,rev=false,step=false},
      {name="aeronautics:propeller_bearing_3",fwd=false,neutral=false,rev=false,step=false},
      {name="aeronautics:propeller_bearing_4",fwd=false,neutral=false,rev=false,step=false},
    }},
  steering={mode="off", -- "off", "differential", or "gear"; one yaw controller.
    navVerified=false,navMethod="getRelativeAngle",navArgs={},
    navScaleToDegrees=1,navSign=1, -- positive calibrated error means turn RIGHT.
    kp=0.02,maxYaw=0.25,deadband=2,
    gearConfirmed=false,completionMode="busy-cycle",maxStep=3,cooldown=1,runTimeout=5,
    -- Supply tested rotate arguments. Example structure only:
    -- rotateArgs=function(step) return {step, TESTED_OTHER_ARGUMENT} end
    -- No default signature is supplied. step is bounded signed degrees.
    rotateArgs=false},
}
