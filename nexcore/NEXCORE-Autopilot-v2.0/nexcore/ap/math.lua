local M={}
function M.finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
function M.clamp(n,a,b) return math.max(a,math.min(b,n)) end
function M.wrap(n) return (n+180)%360-180 end
function M.round(n) return math.floor(n+0.5) end
function M.distance(a,b) return math.sqrt((b.x-a.x)^2+(b.z-a.z)^2) end
function M.bearing(a,b) return math.deg(math.atan2(b.z-a.z,b.x-a.x)) end
function M.offset(position,reference,navAngle,knownHeading)
 return M.wrap(knownHeading-M.bearing(position,reference)+navAngle)
end
function M.heading(position,reference,navAngle,offset)
 return M.wrap(M.bearing(position,reference)-navAngle+offset)
end
M.patterns={forward={0,1,1,0},reverse={1,0,0,1},left={1,0,1,0},right={0,1,0,1}}
function M.altitude(y,vy,target,integral,base,dt,c)
 local error=target-y
 if math.abs(error)<=c.deadband and math.abs(vy)<=c.velocityDeadband then return base,integral end
 local ni=M.clamp(integral+error*dt,-c.integralLimit,c.integralLimit)
 local raw=base+c.kp*error+c.ki*ni-c.kd*vy
 local lo,hi=math.max(5,base-c.maxCorrection),math.min(500,base+c.maxCorrection)
 if raw>hi and error>0 or raw<lo and error<0 then ni=integral end
 return M.clamp(M.round(base+c.kp*error+c.ki*ni-c.kd*vy),lo,hi),ni
end
function M.route(position,heading,target,speed,c,turning)
 local distance=M.distance(position,target)
 if distance<=c.arrivalRadius then return "stop",0,distance,0,"ARRIVED" end
 local error=M.wrap(M.bearing(position,target)-heading)
 local threshold=turning and c.turnExit or c.turnEnter
 if math.abs(error)>threshold then
  return error>0 and "right" or "left",c.turnRPM,distance,error,"ALIGN"
 end
 -- Coasting stop, not active reverse braking. Bounds must be commissioned.
 local stopping=speed*speed/(2*c.assumedDeceleration)+c.arrivalRadius
 if distance<=stopping or speed>c.cruiseSpeed then return "stop",0,distance,error,"COAST" end
 local rpm=distance<c.approachRadius and c.approachRPM or c.maxRPM
 return "forward",rpm,distance,error,"CRUISE"
end
return M
