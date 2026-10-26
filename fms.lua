-- NEXCORE FMS v2.0 / Aerostate. Independent implementation; no v3.5.2 source used.
local C=require("nexcore.config")
local U=require("nexcore.core")
local H=require("nexcore.hardware")
local Commands=require("nexcore.commands")
local S={hold=false,estop=true,forward=0,yaw=0,integral=0,burn=C.lift.hover,
  samples={},outputs={},health={},gear={},message="OBSERVE: outputs inactive"}
function S.stop(reason)
  S.estop=true; S.starting=false; S.forward=0; S.yaw=0
  S.message=reason or "Propulsion stopped; lift preserved"
end
local function fail(role,reason)
  if role=="lift" then S.liftFault=true; S.hold=false; S.integral=0
  elseif role=="prop" then S.propFault=true
  elseif role=="gear" then S.gearFault=true end
  S.stop(reason)
end
local function fresh(sample) return sample and sample.at and U.now()-sample.at<C.stale end
local function reader(name,method,args,key)
  return function()
    while true do
      local sample=S.samples[key] or {}; S.samples[key]=sample
      if H.available(name,method) then
        sample.busy=U.now()
        local result=U.pack(pcall(peripheral.call,name,method,table.unpack(args or {})))
        sample.busy=nil
        if result[1] then
          local values={n=result.n-1}
          for i=2,result.n do values[i-1]=result[i] end
          sample.values=values; sample.value=values[1]; sample.at=U.now(); sample.error=nil
        else sample.error=tostring(result[2]) end
      else sample.error="Unavailable "..name.."."..method end
      U.sleep(C.readPeriod)
    end
  end
end
local function gpsWorker()
  while true do
    local result=U.pack(pcall(gps.locate,C.gps.timeout,false))
    if result[1] and U.finite(result[2]) and U.finite(result[3]) and U.finite(result[4]) then
      S.samples.gps={x=result[2],y=result[3],z=result[4],at=U.now()}
    else
      local old=S.samples.gps or {}; old.error="GPS unavailable"; S.samples.gps=old
    end
    U.sleep(C.gps.period)
  end
end
local function altitudeUpdate()
  local a
  if C.source=="gps" and C.gps.verifiedMoving then
    local g=S.samples.gps
    if fresh(g) and not g.error then a={y=g.y,at=g.at} end
  elseif C.source=="height" and C.height.verified then
    local h=S.samples.height
    if fresh(h) and not h.error and U.finite(h.value) then
      a={y=h.value*C.height.scale+C.height.offset,at=h.at}
    end
  end
  if not a then S.alt=nil; return end
  local old=S.lastAlt
  if old and a.at==old.at then S.alt=old; return end
  if old and a.at>old.at and a.at-old.at<C.stale then
    local vy=(a.y-old.y)/(a.at-old.at)
    if math.abs(vy)>C.limits.maxVerticalSpeed then
      S.alt=nil; S.altError="Implausible altitude jump; select/calibrate source"
      if S.hold then S.hold=false; S.integral=0; S.stop(S.altError) end
      -- Adopt new baseline only for observation, never resume hold here.
      S.lastAlt={y=a.y,at=a.at,vy=0}; return
    end
    a.vy=0.5*(old.vy or 0)+0.5*vy
  else a.vy=0 end
  S.lastAlt=a; S.alt=a; S.altError=nil
end
local function controller()
  local previous=U.now()
  while true do
    local now=U.now(); local dt=U.clamp(now-previous,0.01,0.5); previous=now
    altitudeUpdate()
    if S.hold then
      if not fresh(S.alt) then
        S.hold=false; S.integral=0; S.stop("Altitude stale: last burner demand retained; H required")
      elseif S.liftFault then S.hold=false; S.stop("Lift fault: demand retained")
      else
        S.burn,S.integral=U.pid(S.target-S.alt.y,S.alt.vy,S.integral,dt,C.pid,C.lift.hover)
      end
    end
    if S.starting then
      if not S.hold then S.stop("Cruise canceled: altitude hold inactive")
      else
        local neutral=true
        for _,ch in ipairs(C.propulsion.channels) do
          local o=S.outputs[ch.name]
          if not o or o.error or o.busy or not o.at or o.at<S.neutralSince or o.lastRaw~=ch.neutral then neutral=false end
        end
        if neutral then S.estop=false; S.starting=false; S.message="Automatic cruise enabled"
        elseif now-S.neutralSince>C.callTimeout+C.refresh then fail("prop","Neutral confirmation timed out") end
      end
    end
    if not S.estop then
      if not S.hold then S.stop("Cruise stopped: altitude hold inactive")
      else
        S.forward=C.propulsion.cruise; S.yaw=0
        if C.steering.mode~="off" then
          local nav=S.samples.nav
          if not C.steering.navVerified or not fresh(nav) or nav.error or not U.finite(nav.value) then
            S.stop("Steering navigation unavailable: propulsion stopped")
          elseif C.steering.mode=="gear" and (not C.steering.gearConfirmed or S.gearFault or not fresh(S.gear)) then
            S.stop("Gear steering unavailable: propulsion stopped")
          else
            S.navError=nav.value*C.steering.navScaleToDegrees*C.steering.navSign
            if math.abs(S.navError)>C.steering.deadband and C.steering.mode=="differential" then
              S.yaw=U.clamp(S.navError*C.steering.kp,-C.steering.maxYaw,C.steering.maxYaw)
            end
          end
        end
      end
    end
    for name,o in pairs(S.outputs) do
      if o.busy and now-o.busy>C.callTimeout then fail(o.role,"Output call stalled: "..name) end
      if o.active and o.at and now-o.at>C.callTimeout+C.refresh then fail(o.role,"Output heartbeat stale: "..name) end
    end
    if S.gear.busy and now-S.gear.busy>C.callTimeout then fail("gear","Gear call stalled") end
    U.sleep(C.tick)
  end
end
local function outputWorker(ch,role)
  local o={role=role}; S.outputs[ch.name]=o
  return function()
    while true do
      local active=role=="lift" and S.liftOutputs or role=="prop" and S.propOutputs
      if active then
        o.active=true
        local demand,raw
        if role=="lift" then
          if not o.lastNorm then
            local sample=S.samples[ch.name]
            if not fresh(sample) or sample.error or not U.finite(sample.value) then
              fail(role,"Fresh burner scroll read required: "..ch.name)
            else
              local norm=(sample.value-ch.low)/(ch.high-ch.low)
              if norm<0 or norm>1 then fail(role,"Burner scroll outside calibrated range: "..ch.name)
              else o.lastNorm=norm end
            end
          end
          if o.lastNorm then
            demand=U.clamp(S.burn,o.lastNorm-C.lift.slew*C.tick,o.lastNorm+C.lift.slew*C.tick)
            raw=U.clamp(U.quantize(ch.low+demand*(ch.high-ch.low),ch.step,ch.low),math.min(ch.low,ch.high),math.max(ch.low,ch.high))
          end
        else
          local mix=U.mix(S.forward,S.yaw)
          demand=S.estop and 0 or mix[ch.index]
          if demand~=0 then demand=U.clamp(demand,(o.lastNorm or 0)-C.propulsion.slew*C.tick,(o.lastNorm or 0)+C.propulsion.slew*C.tick) end
          if demand==0 then raw=ch.neutral -- bypass slew and quantization for emergency neutral.
          else
            raw=U.quantize(U.propRaw(demand,ch),ch.step,ch.neutral)
            raw=U.clamp(raw,math.min(ch.rev,ch.neutral,ch.fwd),math.max(ch.rev,ch.neutral,ch.fwd))
          end
        end
        if raw~=nil then
          if not H.available(ch.name,"setScrollValue") then
            o.error="Unavailable setter"; fail(role,"Output disconnected: "..ch.name)
          elseif o.lastRaw~=raw or not o.at or U.now()-o.at>C.refresh then
            o.busy=U.now()
            local ok,value=pcall(peripheral.call,ch.name,"setScrollValue",raw)
            o.busy=nil
            if ok and value~=false then
              o.lastRaw=raw; o.lastNorm=demand; o.at=U.now(); o.error=nil
            else o.error=tostring(value); fail(role,"Output failed: "..ch.name) end
          else o.lastNorm=demand end
        end
      end
      U.sleep(C.tick)
    end
  end
end
local function gearWorker()
  local lastCommand=-math.huge; local runningSince; local pending; local sawRunning=false
  while true do
    if H.available(C.gear,"isRunning") then
      S.gear.busy=U.now()
      local ok,running=pcall(peripheral.call,C.gear,"isRunning")
      S.gear.busy=nil
      if ok and type(running)=="boolean" then
        S.gear.running=running; S.gear.at=U.now(); S.gear.error=nil
        if pending then
          if running then sawRunning=true end
          if not running and (sawRunning or C.steering.completionMode=="return-is-complete") then
            pending=nil; sawRunning=false
          elseif U.now()-pending>C.steering.runTimeout then
            fail("gear","Gear completion unconfirmed; no further rotate commands")
          end
          if S.gearFault and not running then pending=nil; sawRunning=false end
        end
        if running then
          runningSince=runningSince or U.now()
          if U.now()-runningSince>C.steering.runTimeout and C.steering.mode=="gear" then fail("gear","Gear running timeout") end
        else runningSince=nil end
        if C.steering.mode=="gear" and C.steering.gearConfirmed and C.steering.navVerified
          and not S.estop and not S.gearFault and not pending and not running and U.now()-lastCommand>C.steering.cooldown then
          local nav=S.samples.nav
          if fresh(nav) and not nav.error and U.finite(nav.value) then
            local err=nav.value*C.steering.navScaleToDegrees*C.steering.navSign
            if math.abs(err)>C.steering.deadband then
              local step=U.clamp(err,-C.steering.maxStep,C.steering.maxStep)
              local args=C.steering.rotateArgs(step)
              assert(type(args)=="table","rotateArgs must return a tested argument list")
              -- Single command owner; no queue or parallel rotate calls.
              if not S.estop and H.available(C.gear,"rotate") then
                lastCommand=U.now(); pending=lastCommand; sawRunning=false; S.gear.busy=U.now()
                local success,result=pcall(peripheral.call,C.gear,"rotate",table.unpack(args))
                S.gear.busy=nil
                if not success or result==false then fail("gear","rotate failed: "..tostring(result)) end
              end
            end
          end
        end
      else S.gear.error=tostring(running); if not S.estop and C.steering.mode=="gear" then fail("gear","isRunning failed") end end
    else
      S.gear.error="Gearshift unavailable"
      if not S.estop and C.steering.mode=="gear" then fail("gear",S.gear.error) end
    end
    U.sleep(C.readPeriod)
  end
end
local function healthWorker()
  while true do
    for _,spec in ipairs(H.expected) do
      local ok,why=H.check(spec); S.health[spec.name]={ok=ok,error=why}
      if not ok then
        if spec.role=="lift" and S.liftOutputs then fail("lift","Disconnected/mismatched lift: "..spec.name)
        elseif spec.role=="prop" and S.propOutputs then fail("prop","Disconnected/mismatched prop: "..spec.name)
        elseif spec.role=="gear" and C.steering.mode=="gear" and not S.estop then fail("gear","Gearshift disconnected") end
      end
    end
    U.sleep(1)
  end
end
local function commandWorker()
  while true do
    local event,a,b=os.pullEventRaw()
    if event=="terminate" then Commands.handle(S,C,"stop")
    elseif event=="nexcore_command" then Commands.handle(S,C,a,b)
    elseif event=="peripheral_detach" then
      local spec=H.lookup(a)
      if spec then
        if spec.role=="lift" and S.liftOutputs then fail("lift","Detached burner: "..a)
        elseif spec.role=="prop" and S.propOutputs then fail("prop","Detached prop: "..a)
        elseif spec.role=="gear" and C.steering.mode=="gear" and not S.estop then fail("gear","Detached gearshift") end
      end
    elseif event=="key" then
      if a==keys.space or a==keys.x then Commands.handle(S,C,"stop")
      elseif a==keys.h then Commands.handle(S,C,"hold")
      elseif a==keys.p then Commands.handle(S,C,"cruise")
      elseif a==keys.f then Commands.handle(S,C,"freeze")
      elseif a==keys.r then Commands.handle(S,C,"recover")
      elseif a==keys.up or a==keys.down then Commands.handle(S,C,"target",(S.target or 0)+(a==keys.up and 1 or -1)*C.limits.targetStep) end
    end
  end
end
local UI=require("nexcore.ui")
local jobs={commandWorker,controller,gpsWorker,healthWorker,gearWorker,
  UI.worker(S,C,"local"),UI.worker(S,C,"monitor"),
  reader(C.altitude,"getHeight",{},"height"),reader(C.altitude,"getAirPressure",{},"pressure"),
  reader(C.nav,C.steering.navMethod,C.steering.navArgs,"nav"),
  reader(C.swivel,"getTargetAngle",{},"swivel")}
for _,name in ipairs(C.velocities) do jobs[#jobs+1]=reader(name,"getVelocity",{},name) end
for _,group in ipairs({C.lift,C.propulsion}) do
  for i,ch in ipairs(group.channels) do
    ch.index=i
    jobs[#jobs+1]=reader(ch.name,"getScrollValue",{},ch.name)
    jobs[#jobs+1]=outputWorker(ch,group==C.lift and "lift" or "prop")
  end
end
require("nexcore.validate")(C)
local guarded={}
for i,job in ipairs(jobs) do
  guarded[i]=function()
    while true do
      local ok,err=pcall(job)
      if not ok then
        S.hold=false; S.liftFault=true; S.propFault=true; S.gearFault=true
        S.stop("Worker fault "..i..": "..tostring(err))
      end
      U.sleep(0.5)
    end
  end
end
parallel.waitForAll(table.unpack(guarded))
