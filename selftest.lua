-- Run from the NEXCORE installation directory; no physical output calls.
local U=require("nexcore.core")
local C=require("nexcore.config")
local Commands=require("nexcore.commands")
require("nexcore.validate")(C)
local count=0
local function check(v,msg) count=count+1; assert(v,msg) end
local function near(a,b) return math.abs(a-b)<1e-9 end
local f=U.mix(1,0); check(f[1]==1 and f[2]==1 and f[3]==1 and f[4]==1,"forward")
local r=U.mix(-1,0); check(r[1]==-1 and r[4]==-1,"reverse")
local l=U.mix(0,-1); check(l[1]==-1 and l[2]==-1 and l[3]==1 and l[4]==1,"left turn pair mapping")
local y=U.mix(0,1); check(y[1]==1 and y[3]==-1,"right turn pair mapping")
local m=U.mix(1,1); check(m[1]==1 and m[3]==0,"mix saturation")
local ch={neutral=10,fwd=20,rev=2}
check(U.propRaw(0,ch)==10,"neutral")
check(U.propRaw(1,ch)==20 and U.propRaw(-1,ch)==2,"raw endpoints")
check(U.propRaw(-0.5,ch)==6,"raw interpolation")
check(near(U.quantize(0.26,0.1,0),0.3),"quantization")
local v,i=U.pid(100,0,0,1,{kp=1,ki=1,kd=0,integralLimit=30},0.5)
check(v==1 and i==0,"anti windup")
local b=U.pid(0,2,0,0.1,{kp=0.1,ki=0,kd=0.1,integralLimit=1},0.5)
check(near(b,0.3),"rising velocity reduces lift")
check(not U.finite(0/0) and not U.finite(math.huge),"nonfinite")
check(U.nextInteger(5,0,10)==6,"exact integer step")
check(U.nextInteger(10,0,10)==nil,"upper bound rejects step")
check(U.nextInteger(1.5,0,10)==nil,"noninteger rejected")
check(not U.hoverStable({{y=10,at=0},{y=10,at=5}},30,0.02,0.003),"short plateau rejected")
check(U.hoverStable({{y=10,at=0},{y=10,at=30}},30,0.02,0.003),"stable altitude window")
check(not U.hoverStable({{y=10,at=0},{y=10.1,at=30}},30,0.02,0.003),"altitude drift rejected")
check(not U.hoverStable({{y=10,at=0},{y=10.1,at=15},{y=10,at=30}},30,0.02,0.003),"oscillation rejected despite zero endpoint slope")
local manifest=require("nexcore.hardware").expected
check(#manifest==18,"18 exact peripheral specifications")
check(C.airship.mass==429.50,"reported mass preserved")
local S={burn=0.64,hold=true,propOutputs=false}
function S.stop(msg) S.estop=true; S.starting=false; S.forward=0; S.yaw=0; S.message=msg end
-- Test with a deliberately unconfirmed copy to prevent peripheral access.
local testC={propulsion={confirmed=false},lift={confirmed=false}}
Commands.handle(S,testC,"stop")
check(S.estop and S.forward==0 and S.yaw==0,"emergency propulsion stop")
check(S.burn==0.64 and S.hold==true,"emergency preserves lift control")
Commands.handle(S,testC,"freeze")
check(S.burn==0.64 and not S.hold,"freeze retains burner demand")
Commands.handle(S,testC,"cruise")
check(S.estop,"unconfirmed cruise remains inhibited")
Commands.handle(S,testC,"hold")
check(not S.hold,"unconfirmed lift remains inhibited")
for _,path in ipairs({"fms.lua","calibrate.lua","audit.lua","nexcore/core.lua","nexcore/config.lua",
  "nexcore/hardware.lua","nexcore/commands.lua","nexcore/validate.lua","nexcore/ui.lua"}) do
  local fn,err=loadfile(path); check(fn~=nil,path..": "..tostring(err))
end
print("PASS: "..count.." assertions. No output methods invoked.")
