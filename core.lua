local M={}
function M.finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
function M.clamp(v,a,b) return math.max(a,math.min(b,v)) end
function M.now() return os.epoch("utc")/1000 end
function M.sleep(seconds)
  local timer=os.startTimer(seconds)
  repeat local e,id=os.pullEventRaw() until e=="timer" and id==timer
end
function M.pack(...) return {n=select("#",...),...} end
function M.mix(forward,yaw)
  local l,r=forward+yaw,forward-yaw
  local scale=math.max(1,math.abs(l),math.abs(r))
  return {l/scale,l/scale,r/scale,r/scale}
end
function M.propRaw(demand,ch)
  return ch.neutral+math.abs(demand)*((demand>=0 and ch.fwd or ch.rev)-ch.neutral)
end
function M.quantize(value,step,origin)
  return origin+math.floor((value-origin)/step+0.5)*step
end
function M.pid(error,vy,integral,dt,c,hover)
  local ni=M.clamp(integral+error*dt,-c.integralLimit,c.integralLimit)
  local raw=hover+c.kp*error+c.ki*ni-c.kd*vy
  if (raw>1 and error>0) or (raw<0 and error<0) then ni=integral end
  return M.clamp(hover+c.kp*error+c.ki*ni-c.kd*vy,0,1),ni
end
function M.nextInteger(raw,minimum,maximum)
  if not M.finite(raw) or raw~=math.floor(raw) or raw<minimum or raw+1>maximum then return nil end
  return raw+1
end
function M.hoverStable(window,seconds,tolerance,maxSlope)
  if #window<2 then return false end
  local first,last=window[1],window[#window]
  local duration=last.at-first.at
  if duration<=0 or duration<seconds then return false end
  local low,high=math.huge,-math.huge
  for _,v in ipairs(window) do low=math.min(low,v.y); high=math.max(high,v.y) end
  return high-low<=tolerance and math.abs((last.y-first.y)/duration)<=maxSlope
end
return M
