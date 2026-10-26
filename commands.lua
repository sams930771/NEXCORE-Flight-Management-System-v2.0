-- Shared command boundary for local UI and a future authenticated pocket module.
-- No modem receive channel or remote control is enabled in this version.
local U=require("nexcore.core")
local H=require("nexcore.hardware")
local M={}
function M.channelsReady(C,kind)
  local group=kind=="lift" and C.lift or C.propulsion
  if not group.confirmed then return false,"Calibration not confirmed: "..kind end
  local names={}
  for _,ch in ipairs(group.channels) do
    if names[ch.name] then return false,"Duplicate channel" end
    names[ch.name]=true
    local spec=H.lookup(ch.name)
    if not spec or spec.role~=(kind=="lift" and "lift" or "prop") then return false,"Wrong channel role" end
    if not H.available(ch.name,"setScrollValue") then return false,"Unavailable "..ch.name end
    if not U.finite(ch.step) or ch.step<=0 then return false,"Uncalibrated step" end
    if kind=="lift" then
      if not U.finite(ch.low) or not U.finite(ch.high) or ch.low==ch.high then return false,"Uncalibrated lift endpoints" end
    else
      if not U.finite(ch.fwd) or not U.finite(ch.rev) or not U.finite(ch.neutral) then return false,"Uncalibrated propulsion endpoints" end
    end
  end
  if #group.channels~=4 then return false,"Four calibrated channels required" end
  return true
end
function M.handle(S,C,action,value)
  if action=="stop" then
    S.stop("Emergency: propulsion neutral; burners preserved")
    local ok=M.channelsReady(C,"prop")
    if ok then S.propOutputs=true end -- permit a calibrated stop even before P.
  elseif action=="hold" then
    local ok,why=M.channelsReady(C,"lift")
    local a=S.alt
    if ok and not S.liftOutputs then
      for _,ch in ipairs(C.lift.channels) do
        local sample=S.samples[ch.name]
        if not sample or not sample.at or U.now()-sample.at>C.stale or sample.error or not U.finite(sample.value) then
          ok=false; why="Fresh burner scroll readings required"; break
        end
        local n=(sample.value-ch.low)/(ch.high-ch.low)
        if n<0 or n>1 then ok=false; why="Burner outside calibrated range"; break end
      end
    end
    if not ok then S.message=why
    elseif not a or U.now()-a.at>C.stale then S.message="Fresh calibrated altitude required"
    elseif a.y<C.limits.min or a.y>C.limits.max then S.message="Altitude outside limits"
    elseif S.liftFault then S.message="Resolve fault then R to recover lift"
    else
      if not S.liftOutputs then S.burn=C.lift.hover end
      S.liftOutputs=true; S.hold=true; S.target=a.y; S.integral=0
      S.message="Altitude hold: current altitude captured"
    end
  elseif action=="freeze" then
    S.hold=false; S.integral=0; S.stop("Lift demand frozen; propulsion stopped")
  elseif action=="target" then
    if S.hold and S.alt and U.finite(value) then
      local low=math.max(C.limits.min,S.alt.y-C.limits.maxOffset)
      local high=math.min(C.limits.max,S.alt.y+C.limits.maxOffset)
      if low<=high then S.target=U.clamp(value,low,high) end
    end
  elseif action=="cruise" then
    local ok,why=M.channelsReady(C,"prop")
    if not ok then S.message=why
    elseif S.propFault then S.message="Resolve propulsion fault then R"
    elseif not S.hold then S.message="Active altitude hold required"
    else
      S.propOutputs=true; S.neutralSince=U.now(); S.starting=true
      S.estop=true; S.forward=0; S.yaw=0
      S.message="Neutralizing all four props before automatic cruise"
    end
  elseif action=="recover" then
    -- Recovery never resumes motion, lift control, or gear commands by itself.
    local liftOK=M.channelsReady(C,"lift"); local propOK=M.channelsReady(C,"prop")
    local function healthy(group)
      for _,ch in ipairs(group.channels) do
        local o=S.outputs[ch.name]
        if o and (o.busy or o.error) then return false end
      end
      return true
    end
    if liftOK and healthy(C.lift) then S.liftFault=false end
    if propOK and healthy(C.propulsion) then S.propFault=false end
    if S.gear.running==false and S.gear.at and U.now()-S.gear.at<C.stale and not S.gear.busy then
      S.gearFault=false
    end
    S.stop("Recovery checked; H to recapture altitude, P to restart cruise")
  end
end
return M
