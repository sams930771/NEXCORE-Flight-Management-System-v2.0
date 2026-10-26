local M={}
function M.run(C)
 local X=require("nexcore.ap.math");local H=require("nexcore.ap.hardware");local P=require("nexcore.ap.protocol")
 local function now() return os.epoch("utc")/1000 end
 local function pause(s) local t=os.startTimer(s);repeat local e,id=os.pullEventRaw() until e=="timer" and id==t end
 local function fresh(s) return s and s.at and now()-s.at<C.stale and not s.error end
 local S={samples={},outputs={},health={},mode="STOPPED",armed=false,liftActive=false,
  burn=60,integral=0,desired={mode="stop",rpm=0},queue={},lastSeq=0,
  session=tostring(os.epoch("utc")).."-"..tostring(math.random(100000,999999)),message="H: capture altitude; R then Y: arm propulsion"}
 function S.stop(reason)
  S.armed=false;S.goal=nil;S.desired={mode="stop",rpm=0};S.challenge=nil
  S.mode="STOPPED";S.message=reason
 end
 local function liftFault(reason)
  S.liftFault=true;S.liftActive=false;S.stop("LIFT FROZEN: "..reason)
 end
 local function response(id,kind,detail,extra)
  if #S.queue>=20 then table.remove(S.queue,1) end
  S.queue[#S.queue+1]={id=id,msg={key=C.key,session=S.session,kind=kind,detail=detail,extra=extra,nextSeq=S.lastSeq+1,
   status={mode=S.mode,armed=S.armed,lift=S.liftActive,burn=S.burn,target=S.target,
    distance=S.distance,heading=S.heading,speed=S.speed or 0}}}
 end
 local function sensor(key,name,method)
  return function()
   while true do
    local ok,v=H.invoke(name,method)
    if ok then S.samples[key]={value=v,at=now()}
    else local s=S.samples[key] or {};s.error=tostring(v);S.samples[key]=s end
    pause(0.5)
   end
  end
 end
 local function gpsWorker()
  while true do
   local ok,x,y,z=pcall(gps.locate,1,false)
   if ok and X.finite(x) and X.finite(y) and X.finite(z) then
    local previous=S.samples.gps;local g={x=x,y=y,z=z,at=now()}
    if fresh(previous) and g.at>previous.at then
     local dt=g.at-previous.at;local moved=X.distance(previous,g)
     if moved/dt>30 then g.error="GPS jump" else S.speed=0.5*(S.speed or 0)+0.5*moved/dt end
    else S.speed=0 end
    S.samples.gps=g
    -- GPS course is only an independent sanity check during driven forward
    -- travel; it is never substituted for body heading during stationary turns.
    local drive=S.outputs[H.names.speed]
    if not g.error and drive and drive.lastRPM and drive.lastRPM>0 and S.desired.mode=="forward" and X.finite(S.heading) then
     S.courseStart=S.courseStart or g
     if X.distance(S.courseStart,g)>=1 then
      local course=X.bearing(S.courseStart,g)
      if math.abs(X.wrap(course-S.heading))>60 then S.stop("Forward course disagrees with heading; check compass/calibration") end
      S.courseStart=g
     end
    else S.courseStart=nil end
   else local s=S.samples.gps or {};s.error="No GPS fix";S.samples.gps=s end
   pause(0.5)
  end
 end
 local function healthWorker()
  while true do
   for name in pairs(H.specs) do
    local ok,why=H.check(name);S.health[name]=ok
    if not ok then
     if name==H.names.relay or name==H.names.height then
      if S.liftActive then liftFault(why) end
     elseif name==H.names.speed then S.driveFault=true;S.stop(why)
     else
      for _,b in ipairs(H.burners) do if b==name and S.liftActive then liftFault(why) end end
      for _,p in ipairs(H.props) do if p==name then S.driveFault=true;S.stop(why) end end
     end
    end
   end
   pause(0.5)
  end
 end
 local function liftWorker(name)
  local o={};S.outputs[name]=o
  return function()
   while true do
    if S.liftActive then
     local current=S.samples[name]
     if not fresh(current) or not X.finite(current.value) or current.value%1~=0 then liftFault("Burner feedback invalid: "..name)
     elseif not o.last or o.last~=S.burn or not o.at or now()-o.at>1 then
      -- All writes are bounded whole integers. The control loop permits one
      -- integer change per configured step interval.
      local target=X.clamp(X.round(S.burn),5,500)
      o.busy=now();local ok,v=H.invoke(name,"setScrollValue",target);o.busy=nil
      if ok and v~=false then
       o.busy=now();local verified,actual=H.invoke(name,"getScrollValue");o.busy=nil
       if verified and actual==target then o.last=target;o.at=now();o.error=nil
       else o.error="Burner readback mismatch";liftFault(o.error..": "..name) end
      else o.error=tostring(v);liftFault("Burner write failed: "..name) end
     end
    end
    pause(C.tick)
   end
  end
 end
 local function relayWorker()
  local o={};S.outputs[H.names.relay]=o
  while true do
   if S.relayRequested and (not o.at or now()-o.at>1) then
    o.busy=now();local ok,v=H.invoke(H.names.relay,"setOutput","top",true);o.busy=nil
    if ok and v~=false then o.at=now();o.error=nil
    else o.error=tostring(v);liftFault("Burner relay write failed") end
   end
   -- No propulsion command, fault handler, or remote message can set this false.
   pause(C.tick)
  end
 end
 local function driveWorker()
  local o={lastRPM=nil,lastMode=nil};S.outputs[H.names.speed]=o
  local zeroSince;local turnCoolUntil=0
  local function writeSpeed(rpm)
   o.busy=now();local ok,v=H.invoke(H.names.speed,"setTargetSpeed",rpm);o.busy=nil
   if ok and v~=false then
    if rpm>0 and (o.lastRPM or 0)==0 then o.motionSince=now() elseif rpm==0 then o.motionSince=nil end
    o.lastRPM=rpm;o.at=now();o.error=nil;return true end
   o.error=tostring(v);S.driveFault=true;S.stop("Drive output failed");return false
  end
  while true do
   local desired=S.desired;local rpm=S.armed and desired.rpm or 0
   if desired.mode=="left" or desired.mode=="right" then
    if now()<turnCoolUntil then rpm=0
    elseif o.lastRPM and o.lastRPM>0 and o.motionSince and now()-o.motionSince>=0.4 then
     rpm=0;turnCoolUntil=now()+C.stopWait
    end
   end
   if rpm==0 or desired.mode~=o.lastMode then
    if o.lastRPM~=0 or not o.at or now()-o.at>1 then writeSpeed(0) end
    if o.lastRPM==0 then zeroSince=zeroSince or now() end
    if rpm>0 and zeroSince and now()-zeroSince>=C.stopWait then
     local feedback=S.samples.rpm
     if not fresh(feedback) or feedback.value~=0 then S.driveFault=true;S.stop("Cannot confirm zero target before direction change")
     else
      local pattern=X.patterns[desired.mode];local success=pattern~=nil
      for i,name in ipairs(H.props) do
       if not success or not S.armed or S.desired~=desired then success=false;break end
       o.busy=now();local ok,v=H.invoke(name,"setScrollValue",pattern[i]);o.busy=nil
       if not ok or v==false then success=false;S.driveFault=true;S.stop("Direction setter failed: "..name);break end
       o.busy=now();local good,readback=H.invoke(name,"getScrollValue");o.busy=nil
       if not good or readback~=pattern[i] then success=false;S.driveFault=true;S.stop("Direction readback mismatch: "..name);break end
      end
      if success then o.lastMode=desired.mode end
     end
    end
   elseif S.armed and S.desired==desired and X.patterns[desired.mode] then
    if o.lastRPM~=rpm or not o.at or now()-o.at>1 then writeSpeed(rpm) end
    if o.lastRPM~=0 then zeroSince=nil end
   end
   pause(C.tick)
  end
 end
 local function preflight()
  if not S.liftActive or S.liftFault then return false,"Enable healthy altitude hold with H" end
  if not C.gpsVerified or not C.referenceConfirmed or not X.finite(C.headingOffset) then return false,"Complete GPS/reference/heading setup first" end
  if not X.finite(S.heading) then return false,"Heading unavailable or compass reference too close" end
  if not fresh(S.samples.gps) or not fresh(S.samples.nav) or not X.finite(S.samples.nav.value) then return false,"Navigation data stale" end
  if not fresh(S.samples.relay) or S.samples.relay.value~=true then return false,"Burner activation readback not confirmed" end
  for name,spec in pairs(H.specs) do if not spec.optional and not S.health[name] then return false,"Hardware unavailable: "..name end end
  local drive=S.outputs[H.names.speed]
  if not drive or drive.busy or drive.lastRPM~=0 or not fresh(S.samples.rpm) or S.samples.rpm.value~=0 then return false,"Drive must confirm zero target" end
  for _,o in pairs(S.outputs) do if o.busy or o.error then return false,"Resolve pending/failed output first" end end
  return true
 end
 local function command(action,msg,sender)
  local function reply(kind,detail,extra) if sender then response(sender,kind,detail,extra) else S.message=detail end end
  if action=="stop" then S.stop("Emergency propulsion stop; lift preserved");reply("ack",S.message)
  elseif action=="status" or action=="heartbeat" then reply("status",S.message)
  elseif action=="hold" then
   if not fresh(S.samples.height) or not X.finite(S.samples.height.value) then return reply("reject","Fresh height required") end
   local base
   for _,name in ipairs(H.burners) do
    local sample=S.samples[name];local o=S.outputs[name]
    if not fresh(sample) or not X.finite(sample.value) or sample.value%1~=0 or sample.value<5 or sample.value>500 or o.busy then return reply("reject","Fresh integer burner readings required") end
    if base and sample.value~=base then return reply("reject","Balance all four burner settings before capture") end
    base=sample.value
   end
   local y=S.samples.height.value
   if y<C.height.min or y>C.height.max then return reply("reject","Height outside limits") end
   S.base=base;S.burn=base;S.target=y;S.baseHeight=y;S.integral=0;S.liftFault=false;S.liftActive=true;S.relayRequested=true
   reply("ack","Altitude hold captured; burners remain integer-only")
  elseif action=="freeze" then S.liftActive=false;S.stop("Lift frozen at last settings; propulsion stopped")
  elseif action=="rearm" then
   local ok,why=preflight();if not ok then return reply("reject",why) end
   S.challenge=tostring(math.random(100000,999999));S.challengeAt=now();S.challengeOwner=sender or "local"
   reply("confirm","Press Y within 10 seconds to arm at zero speed",S.challenge)
  elseif action=="confirm" then
   if not S.challenge or now()-S.challengeAt>10 or S.challengeOwner~=(sender or "local") or sender and msg.challenge~=S.challenge then return reply("reject","Rearm confirmation missing/expired") end
   local ok,why=preflight();if not ok then return reply("reject",why) end
   S.armed=true;S.driveFault=false;S.challenge=nil;S.mode="ARMED IDLE";reply("ack","Propulsion armed at zero speed")
  elseif action=="summon" then
   if not S.armed then return reply("reject","R then Y must arm propulsion first") end
   if not S.liftActive or not fresh(S.samples.gps) then return reply("reject","Altitude hold/GPS unavailable") end
   if not X.finite(msg.x) or not X.finite(msg.y) or not X.finite(msg.z) then return reply("reject","Invalid pocket coordinates") end
   if not X.finite(msg.fixAt) or math.abs(now()-msg.fixAt)>C.stale then return reply("reject","Pocket GPS fix too old") end
   if X.distance(S.samples.gps,msg)>C.nav.maxRange then return reply("reject","Destination exceeds configured range") end
   S.goal={x=msg.x,y=msg.y,z=msg.z};S.missionAt=now();S.progressAt=now();S.bestDistance=math.huge;S.bestError=180
   reply("ack","Summon accepted; current held flight altitude retained")
  end
 end
 local function controlWorker()
  local lastLift=0;local oldHeight
  while true do
   local t=now();local h=S.samples.height
   if fresh(h) and X.finite(h.value) and (not oldHeight or h.at~=oldHeight.at) then
    S.vy=0
    if oldHeight and h.at>oldHeight.at and h.at-oldHeight.at<C.stale then
     local vy=(h.value-oldHeight.value)/(h.at-oldHeight.at)
     if math.abs(vy)>C.height.maxVerticalSpeed then if S.liftActive then liftFault("Implausible height jump") end
     else S.vy=0.5*(S.lastVY or 0)+0.5*vy;S.lastVY=S.vy end
    end
    oldHeight=h
   end
   if S.liftActive then
    if not fresh(h) or not X.finite(h.value) then liftFault("Height sensor stale")
    elseif h.value<C.height.min or h.value>C.height.max then liftFault("Height outside configured limits")
    elseif t-lastLift>=C.lift.stepSeconds then
     local dt=lastLift==0 and C.lift.stepSeconds or math.min(5,t-lastLift);lastLift=t
     local demand;demand,S.integral=X.altitude(h.value,S.vy or 0,S.target,S.integral,S.base,dt,C.lift)
     S.burn=X.clamp(demand,S.burn-1,S.burn+1)
    end
   end
   local g,n=S.samples.gps,S.samples.nav
   if fresh(g) and fresh(n) and X.finite(n.value) and X.finite(C.headingOffset) and X.distance(g,C.reference)>C.nav.referenceExclusion then
    S.heading=X.heading(g,C.reference,n.value,C.headingOffset)
   else S.heading=nil end
   if S.goal then
    if not S.armed or not S.liftActive then S.stop("Mission stopped: propulsion/lift unavailable")
    elseif not S.lastPeer or t-S.lastPeer>C.heartbeatTimeout then S.stop("Remote link lost; propulsion stopped")
    elseif not fresh(g) or not S.heading then S.stop("GPS/heading stale or reference too close")
    elseif math.abs(h.value-S.target)>C.height.maxTargetOffset then S.stop("Altitude deviation; lift control continues")
    elseif t-S.missionAt>300 or t-S.progressAt>30 then S.stop("Mission progress timeout")
    else
     local turning=S.desired.mode=="left" or S.desired.mode=="right"
     local mode,rpm,distance,error,phase=X.route(g,S.heading,S.goal,S.speed or 0,C.nav,turning)
     S.distance=distance;S.angleError=error;S.mode=phase
     if distance<S.bestDistance-0.5 or math.abs(error)<S.bestError-2 then
      S.progressAt=t;S.bestDistance=math.min(S.bestDistance,distance);S.bestError=math.min(S.bestError,math.abs(error))
     end
     if phase=="ARRIVED" then S.goal=nil;S.desired={mode="stop",rpm=0};S.message="Arrival radius reached; coasting, no landing"
     elseif S.desired.mode~=mode or S.desired.rpm~=rpm then S.desired={mode=mode,rpm=rpm} end
    end
   end
   for name,o in pairs(S.outputs) do
    if o.busy and t-o.busy>C.callTimeout then
     if name==H.names.speed then S.driveFault=true;S.stop("Drive call stalled") else liftFault("Output call stalled: "..name) end
    end
   end
   pause(C.tick)
  end
 end
 local function keyboard()
  while not S.quit do
   local e,k,held=os.pullEventRaw()
   if e=="terminate" then command("stop",{})
   elseif e=="key" and not held then
    if k==keys.x or k==keys.space then command("stop",{})
    elseif k==keys.h then command("hold",{})
    elseif k==keys.f then command("freeze",{})
    elseif k==keys.r then command("rearm",{})
    elseif k==keys.y then command("confirm",{})
    elseif (k==keys.up or k==keys.down) and S.liftActive then
     S.target=X.clamp(S.target+(k==keys.up and 1 or -1),math.max(C.height.min,S.baseHeight-C.height.maxTargetOffset),math.min(C.height.max,S.baseHeight+C.height.maxTargetOffset))
    elseif k==keys.q and not S.liftActive and not S.armed and S.outputs[H.names.speed].lastRPM==0 then S.quit=true end
   end
   if S.liftActive and not S.baseHeight then S.baseHeight=S.target end
  end
 end
 local function receiver()
  assert(peripheral.call(H.names.wireless,"isWireless"),"left must be the wireless modem")
  rednet.open(H.names.wireless)
  while true do
   local id,msg=rednet.receive(P.protocol,1)
   if id and type(msg)=="table" and id==C.peer and msg.key==C.key then
    if msg.action=="hello" then response(id,"hello","Ship session ready")
    else
     local ok=P.validate(msg,id,C,S.session,S.lastSeq,now())
     if ok then S.lastSeq=msg.seq;S.lastPeer=now();command(msg.action,msg,id) end
    end
   end
  end
 end
 local function transmitter()
  while true do
   local item=table.remove(S.queue,1)
   if item then pcall(rednet.send,item.id,item.msg,P.protocol) else pause(0.05) end
  end
 end
 local function display(remote)
  return function()
   while true do
    pcall(function()
     local t=remote and peripheral.wrap(H.names.monitor) or term.current();if not t then return end
     local w,h=t.getSize();t.clear()
     local rows={"NEXCORE FMS 2.0 | SUMMON",S.mode.." | "..(S.armed and "ARMED" or "PROP STOP"),S.message,
      "Lift "..(S.liftActive and "HOLD" or "FROZEN").." | integer demand "..S.burn.." | mass "..C.mass.." "..C.massUnit,
      "Burner readback "..table.concat((function() local values={};for _,name in ipairs(H.burners) do values[#values+1]=tostring(S.samples[name] and S.samples[name].value or "--") end;return values end)(),", "),
      "Y "..tostring(S.samples.height and S.samples.height.value).." -> "..tostring(S.target),
      "Drive demand "..S.desired.mode.." "..S.desired.rpm.." | target readback "..tostring(S.samples.rpm and S.samples.rpm.value),
      "Heading "..tostring(S.heading).." | speed (GPS) "..string.format("%.2f",S.speed or 0),
      "Velocity sensors raw: "..tostring(S.samples.velocity1 and S.samples.velocity1.value)..", "..tostring(S.samples.velocity2 and S.samples.velocity2.value),
      "Distance "..tostring(S.distance).." | turn error "..tostring(S.angleError),
      "H capture hold | Up/Down altitude | F freeze lift",
      "R then Y arm | X/SPACE stop PROP only",
      "F then Q to exit; leaves burner/relay state",
      "Pocket ID "..C.peer.." | link "..tostring(S.lastPeer and math.floor(now()-S.lastPeer)).."s"}
     for name,o in pairs(S.outputs) do if o.error or o.busy then rows[#rows+1]=name..": "..tostring(o.error or "PENDING") end end
     for i,line in ipairs(rows) do if i>h then break end;t.setCursorPos(1,i);t.write(line:sub(1,w)) end
    end)
    pause(0.25)
   end
  end
 end
 local jobs={gpsWorker,healthWorker,controlWorker,keyboard,receiver,transmitter,driveWorker,relayWorker,display(false),display(true),
 sensor("height",H.names.height,"getHeight"),sensor("nav",H.names.nav,"getRelativeAngle"),
 sensor("rpm",H.names.speed,"getTargetSpeed"),
 sensor("velocity1","velocity_sensor_1","getVelocity"),sensor("velocity2","velocity_sensor_2","getVelocity"),
 sensor("swivel","swivel_bearing_1","getTargetAngle"),sensor("gear","Create_SequencedGearshift_1","isRunning")}
 -- Relay read is a separate getter with its confirmed top-side argument.
 jobs[#jobs+1]=function() while true do local ok,v=H.invoke(H.names.relay,"getOutput","top");S.samples.relay={value=v,at=ok and now() or nil,error=not ok and tostring(v) or nil};pause(0.5) end end
 for _,name in ipairs(H.burners) do jobs[#jobs+1]=sensor(name,name,"getScrollValue");jobs[#jobs+1]=liftWorker(name) end
 local guarded={}
 for i,fn in ipairs(jobs) do guarded[i]=function() while true do
  local ok,err=pcall(fn);if not ok then S.liftActive=false;S.liftFault=true;S.stop("Worker "..i.." fault: "..tostring(err)) end;pause(0.5)
 end end end
 parallel.waitForAny(function() parallel.waitForAll(table.unpack(guarded)) end,function() while not S.quit do pause(0.1) end end)
 print("Exited: propulsion zero requested; burner/relay states retained.")
end
return M
