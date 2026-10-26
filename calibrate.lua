-- First-flight burner calibration. Run separately from fms.lua.
-- Each + changes each burner by ONE RAW INTEGER, not one normalized PID unit.
local U=require("nexcore.core")
local H=require("nexcore.hardware")
local C=require("nexcore.config")
local args={...}
local minimum,maximum=tonumber(args[1]),tonumber(args[2])
if not minimum or not maximum then
  print("Use the burner GUI/docs to determine safe raw scroll limits first.")
  write("Validated minimum integer: "); minimum=tonumber(read())
  write("Validated maximum integer: "); maximum=tonumber(read())
end
assert(U.finite(minimum) and U.finite(maximum) and minimum<maximum,"Valid limits required")
assert(minimum==math.floor(minimum) and maximum==math.floor(maximum),"Integer limits required")
local K=C.calibration
local S={readings={},outputs={},phase="OBSERVE",revision=0,
  airborne=false,stepped=false,paused=false,message="Observe current values; + applies exactly one integer"}
local path="hover_calibration.jsonl"
local function freeze(reason)
  S.paused=true; S.phase="FROZEN"; S.airborne=false; S.window={}
  S.message=reason.."; current burner settings retained"
end
local function fresh(v) return v and v.at and U.now()-v.at<C.stale and not v.error end
local function poll(name,method,key)
  return function()
    while true do
      local sample=S.readings[key] or {}; S.readings[key]=sample
      if H.available(name,method) then
        local ok,value=pcall(peripheral.call,name,method)
        if ok and U.finite(value) then sample.value=value; sample.at=U.now(); sample.error=nil
        else sample.error="Getter must return a finite number: "..tostring(value) end
      else sample.error="Peripheral/method unavailable" end
      U.sleep(C.readPeriod)
    end
  end
end
local function beginStep()
  if S.paused then S.message="Frozen: R checks recovery; no automatic restart"; return end
  if S.phase=="APPLYING" then S.message="Wait for all four write acknowledgements"; return end
  local height=S.readings.height
  if not fresh(height) then S.message="Fresh altitude sensor reading required"; return end
  local targets={}
  for _,ch in ipairs(C.lift.channels) do
    local r=S.readings[ch.name]
    if not H.available(ch.name,"setScrollValue") or not fresh(r) then S.message="Fresh burner read required: "..ch.name; return end
    if r.value~=math.floor(r.value) then S.message="Noninteger burner scroll; stop and check API"; return end
    local target=U.nextInteger(r.value,minimum,maximum)
    if not target then S.message="Step outside entered safe limits"; return end
    targets[ch.name]=target
  end
  S.initialHeight=S.initialHeight or height.value
  S.targets=targets; S.revision=S.revision+1; S.changedAt=U.now()
  S.phase="APPLYING"; S.window={}; S.saved=false; S.airborne=false
  S.message="Applying one integer to each burner; confirm free flight with A after lift-off"
end
local function setter(ch)
  local o={applied=0}; S.outputs[ch.name]=o
  return function()
    while true do
      if not S.paused and S.phase=="APPLYING" and o.applied<S.revision then
        local revision=S.revision; local target=S.targets[ch.name]
        if not H.available(ch.name,"setScrollValue") then freeze("Burner unavailable: "..ch.name)
        else
          o.busy=U.now()
          local ok,value=pcall(peripheral.call,ch.name,"setScrollValue",target)
          o.busy=nil
          if not ok or value==false then o.error=tostring(value); freeze("Burner setter failed: "..ch.name)
          else o.applied=revision; o.at=U.now(); o.error=nil end
        end
      end
      U.sleep(C.tick)
    end
  end
end
local function record(window)
  local sum=0; local min,max=math.huge,-math.huge
  for _,v in ipairs(window) do sum=sum+v.y; min=math.min(min,v.y); max=math.max(max,v.y) end
  local values={}; local same; local collective
  for i,ch in ipairs(C.lift.channels) do
    local raw=S.readings[ch.name].value
    values[#values+1]={name=ch.name,scrollValue=raw}
    if i==1 then collective=raw; same=true elseif raw~=collective then same=false end
  end
  local observation={schema="nexcore.hover.v1",mass=C.airship.mass,massUnit=C.airship.massUnit,
    altitudeSource="back.getHeight",altitudeRaw=sum/#window,altitudeMin=min,altitudeMax=max,
    altitudeUnits="sensor raw; verify blocks/datum",burners=values,
    collectiveScrollValue=same and collective or nil,
    stableSeconds=window[#window].at-window[1].at,samples=#window,
    tolerance=K.tolerance,maxSlope=K.maxSlope,recordedUTC=os.epoch("utc"),
    airborneConfirmed=true,status="empirical hover observation; validate at other altitudes"}
  local encoded=textutils.serializeJSON(observation)
  local f=assert(fs.open(path,"a")); f.writeLine(encoded); f.close()
  S.saved=true; S.phase="RECORDED"; S.message="HOVER RECORDED at altitude "..string.format("%.3f",observation.altitudeRaw).." -> "..path
end
local function controller()
  while true do
    local now=U.now(); local h=S.readings.height
    if S.revision>0 and not S.paused then
      if not fresh(h) then freeze("Altitude sensor stale/disconnected") end
      for _,ch in ipairs(C.lift.channels) do
        local o=S.outputs[ch.name]; local r=S.readings[ch.name]
        if not fresh(r) then freeze("Burner read stale: "..ch.name) end
        if o.busy and now-o.busy>C.callTimeout then freeze("Burner write stalled: "..ch.name) end
      end
    end
    if not S.paused and S.phase=="APPLYING" then
      local all=true
      for _,ch in ipairs(C.lift.channels) do
        local o=S.outputs[ch.name]; local r=S.readings[ch.name]
        if o.applied~=S.revision or not fresh(r) or r.at<o.at or r.value~=S.targets[ch.name] then all=false end
      end
      if all then S.phase="SETTLING"; S.stepped=true; S.changedAt=now; S.window={}
      elseif now-S.changedAt>K.applyTimeout then freeze("Not all four burners confirmed the requested +1") end
    end
    if not S.paused and S.stepped and fresh(h) and S.phase~="APPLYING" then
      for _,ch in ipairs(C.lift.channels) do
        if S.readings[ch.name].value~=S.targets[ch.name] then freeze("Burner changed externally; restart calibration") end
      end
      if not S.paused and S.phase~="RECORDED" then
        if now-S.changedAt<K.settleSeconds or not S.airborne then S.window={}
        else
          S.phase="MEASURING"
          local w=S.window
          if not w[#w] or h.at>w[#w].at then w[#w+1]={y=h.value,at=h.at} end
          while #w>1 and h.at-w[2].at>=K.windowSeconds do table.remove(w,1) end
          local low,high=math.huge,-math.huge
          for _,v in ipairs(w) do low=math.min(low,v.y); high=math.max(high,v.y) end
          S.span=high-low; S.duration=#w>0 and h.at-w[1].at or 0
          local slope=#w>1 and (w[#w].y-w[1].y)/(w[#w].at-w[1].at) or math.huge
          S.slope=slope
          if U.hoverStable(w,K.windowSeconds,K.tolerance,K.maxSlope) then record(w) end
        end
      end
    end
    U.sleep(C.tick)
  end
end
local function input()
  while true do
    local e,key,isHeld=os.pullEventRaw()
    if e=="key" and (key==keys.equals or key==keys.numPadAdd) and not isHeld then beginStep()
    elseif e=="terminate" or (e=="key" and (key==keys.space or key==keys.x)) then freeze("Test paused")
    elseif e=="peripheral_detach" and (key==C.altitude or (H.lookup(key) and H.lookup(key).role=="lift")) then freeze("Test peripheral detached")
    elseif e=="key" and key==keys.a then
      local h=S.readings.height
      if S.stepped and fresh(h) and h.value-S.initialHeight>=K.minRise and S.phase~="APPLYING" and not S.paused then
        S.airborne=true; S.message="Free flight confirmed by operator; waiting for stability window"
      else S.message="A requires at least "..K.minRise.." raw altitude rise after a successful +1 step" end
    elseif e=="key" and key==keys.r then
      -- Does not resume interrupted multi-output steps or auto-apply pending values.
      local ready=fresh(S.readings.height)
      for _,ch in ipairs(C.lift.channels) do
        if S.outputs[ch.name].busy or not fresh(S.readings[ch.name]) then ready=false end
      end
      if ready then
        S.paused=false; S.phase="OBSERVE"; S.stepped=false; S.airborne=false
        S.initialHeight=S.readings.height.value; S.revision=0; S.targets=nil
        for _,o in pairs(S.outputs) do o.applied=0 end
        S.message="Recovery checked; no values changed; + starts a new step"
      end
    end
  end
end
local function display(target)
  return function()
    while true do
      pcall(function()
        local t=target=="local" and term.current() or peripheral.wrap(C.monitor)
        if not t then return end
        local w,h=t.getSize(); t.clear()
        local height=S.readings.height
        local rows={"NEXCORE | FIRST BURNER CALIBRATION", "Phase: "..S.phase.." | + = exactly ONE raw integer",
          "SPACE/X freezes test; burner settings retained", "Mass: "..C.airship.mass.." "..C.airship.massUnit,
          "back.getHeight: "..tostring(height and height.value or "waiting"),
          "A: confirm freely airborne after observed lift-off", "Settle "..K.settleSeconds.."s, stable window "..K.windowSeconds.."s",
          string.format("Window %.1fs | Span %s | Slope %s",S.duration or 0,tostring(S.span),tostring(S.slope)),
          "Entered safe integer limits: "..minimum.." .. "..maximum}
        for _,ch in ipairs(C.lift.channels) do
          local r=S.readings[ch.name]; rows[#rows+1]=ch.name..": "..tostring(r and r.value or "waiting")..(r and r.error and " ERROR" or "")
        end
        rows[#rows+1]=S.message; rows[#rows+1]="R: check recovery | No propulsion/gear outputs used"
        for i,line in ipairs(rows) do if i>h then break end; t.setCursorPos(1,i); t.write(line:sub(1,w)) end
      end)
      U.sleep(0.25)
    end
  end
end
assert(K.settleSeconds>=0 and K.windowSeconds>0 and K.tolerance>=0 and K.maxSlope>=0 and K.minRise>0)
local jobs={input,controller,display("local"),display("monitor"),poll(C.altitude,"getHeight","height")}
for _,ch in ipairs(C.lift.channels) do
  jobs[#jobs+1]=poll(ch.name,"getScrollValue",ch.name)
  jobs[#jobs+1]=setter(ch)
end
local guarded={}
for i,job in ipairs(jobs) do
  guarded[i]=function()
    while true do
      local ok,err=pcall(job)
      if not ok then freeze("Worker "..i.." error: "..tostring(err)) end
      U.sleep(0.5)
    end
  end
end
parallel.waitForAll(table.unpack(guarded))
