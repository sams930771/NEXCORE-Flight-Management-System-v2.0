local U=require("nexcore.core")
return function(C)
  local function positive(v) assert(U.finite(v) and v>0,"Expected positive finite configuration") end
  for _,v in ipairs({C.tick,C.readPeriod,C.stale,C.callTimeout,C.refresh,C.gps.timeout,C.gps.period,
    C.limits.maxVerticalSpeed,C.limits.maxOffset,C.limits.targetStep,C.lift.slew,C.propulsion.slew,
    C.steering.maxStep,C.steering.cooldown,C.steering.runTimeout}) do positive(v) end
  assert(C.callTimeout>C.tick and C.stale>C.gps.timeout+C.gps.period)
  assert(C.source=="gps" or C.source=="height")
  assert(U.finite(C.limits.min) and U.finite(C.limits.max) and C.limits.min<C.limits.max)
  for _,v in ipairs({C.pid.kp,C.pid.ki,C.pid.kd,C.pid.integralLimit,C.lift.hover,C.propulsion.cruise,C.steering.kp,C.steering.maxYaw,C.steering.deadband}) do assert(U.finite(v) and v>=0) end
  assert(C.lift.hover<=1 and C.propulsion.cruise<=1 and C.steering.maxYaw<=1)
  assert(C.steering.completionMode=="busy-cycle" or C.steering.completionMode=="return-is-complete")
  assert(C.steering.mode=="off" or C.steering.mode=="differential" or C.steering.mode=="gear")
  assert(C.steering.navMethod=="getRelativeAngle" or C.steering.navMethod=="getRelativeAngleRad")
  assert(U.finite(C.steering.navScaleToDegrees) and C.steering.navScaleToDegrees>0)
  assert(math.abs(C.steering.navSign)==1)
  assert(U.finite(C.height.scale) and C.height.scale>0 and U.finite(C.height.offset))
  if C.steering.gearConfirmed then assert(type(C.steering.rotateArgs)=="function","Test rotate arguments first") end
  local names={}
  for _,group in ipairs({C.lift,C.propulsion}) do
    assert(#group.channels==4)
    for _,ch in ipairs(group.channels) do assert(not names[ch.name],"Duplicate actuator"); names[ch.name]=true end
  end
end
