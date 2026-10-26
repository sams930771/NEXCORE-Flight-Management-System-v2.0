local M={}
M.defaults={version=1,mass=477.00,massUnit="kpg",peer=-1,key="",gpsVerified=false,
 referenceConfirmed=false,headingOffset=false,reference={x=0,z=0},
 height={min=-64,max=320,maxTargetOffset=5,maxVerticalSpeed=20},
 lift={base=60,deadband=0.5,velocityDeadband=0.15,kp=0.6,ki=0.005,kd=2,
 integralLimit=30,maxCorrection=10,stepSeconds=2},
 nav={maxRPM=1,turnRPM=1,approachRPM=1,cruiseSpeed=0.5,arrivalRadius=8,
 approachRadius=24,turnEnter=12,turnExit=4,maxRange=128,
 assumedDeceleration=0.05,referenceExclusion=8},
 stale=3,heartbeatTimeout=8,stopWait=3,callTimeout=3,tick=0.1}
function M.load(path)
 if not fs.exists(path) then return nil,"Run setup_ship first" end
 local f=assert(fs.open(path,"r"));local s=f.readAll();f.close()
 local c=textutils.unserialize(s);if type(c)~="table" then return nil,"Invalid settings file" end
 return c
end
function M.save(path,c)
 local f=assert(fs.open(path,"w"));f.write(textutils.serialize(c));f.close()
end
function M.validate(c)
 local X=require("nexcore.ap.math")
 assert(type(c.key)=="string" and #c.key>=8,"Pair key must be at least 8 characters")
 assert(X.finite(c.peer) and c.peer>=0 and c.peer%1==0,"Pocket computer ID required")
 assert(c.version==1 and X.finite(c.mass) and c.mass>0,"Invalid config")
 for _,v in ipairs({c.stale,c.heartbeatTimeout,c.stopWait,c.callTimeout,c.tick,c.lift.stepSeconds,
 c.height.maxTargetOffset,c.height.maxVerticalSpeed,c.nav.cruiseSpeed,c.nav.arrivalRadius,
 c.nav.approachRadius,c.nav.maxRange,c.nav.assumedDeceleration,c.nav.referenceExclusion}) do assert(X.finite(v) and v>0,"Invalid positive limit") end
 for _,v in ipairs({c.lift.base,c.lift.maxCorrection,c.nav.maxRPM,c.nav.turnRPM,c.nav.approachRPM}) do assert(X.finite(v) and v%1==0 and v>=0,"Integer outputs required") end
 assert(c.lift.base>=5 and c.lift.base<=500 and c.lift.maxCorrection<=100)
 -- Only target RPM 1 has been commissioned on this ship so far.
 assert(c.nav.maxRPM<=1 and c.nav.turnRPM<=1 and c.nav.approachRPM<=1,"Commission higher RPM before changing this guard")
 for _,v in ipairs({c.lift.kp,c.lift.ki,c.lift.kd,c.lift.integralLimit,c.lift.deadband,c.lift.velocityDeadband}) do assert(X.finite(v) and v>=0) end
 assert(c.height.min<c.height.max and c.nav.turnExit>0 and c.nav.turnExit<c.nav.turnEnter and c.nav.turnEnter<180)
 assert(X.finite(c.reference.x) and X.finite(c.reference.z))
 assert(c.headingOffset==false or X.finite(c.headingOffset))
end
return M
