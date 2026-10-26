-- No peripheral outputs. Run from installed folder.
local X=require("nexcore.ap.math");local P=require("nexcore.ap.protocol");local Settings=require("nexcore.ap.settings")
local count=0
local function check(v,why) count=count+1;assert(v,why) end
local function near(a,b) return math.abs(a-b)<1e-8 end
check(near(X.wrap(351.53717041015625),-8.46282958984375),"angle wrap")
check(X.wrap(359)==-1 and X.wrap(-181)==179,"shortest angle")
local origin={x=0,z=0}
check(X.bearing(origin,{x=10,z=0})==0,"east")
check(X.bearing(origin,{x=0,z=10})==90,"south")
check(X.bearing(origin,{x=0,z=-10})==-90,"north")
local ref={x=100,z=0};local off=X.offset(origin,ref,84,0)
check(near(X.heading(origin,ref,84,off),0),"heading calibration")
check(near(X.heading(origin,ref,124,off),-40),"left increases nav angle")
local shifted={x=0,z=10};local a=X.bearing(shifted,ref)+off
check(near(X.heading(shifted,ref,a,off),0),"compensate translation relative to compass target")
check(table.concat(X.patterns.forward,",")=="0,1,1,0","authoritative forward")
check(table.concat(X.patterns.reverse,",")=="1,0,0,1","authoritative reverse")
check(table.concat(X.patterns.left,",")=="1,0,1,0","authoritative left")
check(table.concat(X.patterns.right,",")=="0,1,0,1","authoritative right")
local c=Settings.defaults.nav
local mode,rpm,dist,err,state=X.route(origin,0,{x=30,z=0},0,c,false)
check(mode=="forward" and rpm==1 and state=="CRUISE","route east")
mode,rpm=X.route(origin,0,{x=0,z=30},0,c,false);check(mode=="right" and rpm==1,"right steering")
mode,rpm=X.route(origin,0,{x=0,z=-30},0,c,false);check(mode=="left" and rpm==1,"left steering")
mode,rpm,dist,err,state=X.route(origin,0,{x=2,z=0},0,c,false);check(mode=="stop" and rpm==0 and state=="ARRIVED","arrival")
mode,rpm=X.route(origin,0,{x=30,z=0},2,c,false);check(mode=="stop" and rpm==0,"overspeed coast")
for _,error in ipairs({-100,-5,-0.4,0,0.4,5,100}) do
 local demand=X.altitude(0,0,error,0,60,2,Settings.defaults.lift)
 check(demand%1==0 and demand>=5 and demand<=500,"integer bounded lift")
end
check(X.altitude(0,0,0.2,0,60,2,Settings.defaults.lift)==60,"ignore known bobbing band")
check(X.altitude(0,0,1,0,60,2,Settings.defaults.lift)==61,"one-unit altitude error can command an integer increase")
local pairing={peer=7,key="testing-key"}
local msg={session="s",key=pairing.key,seq=2,sent=100,action="summon"}
check(P.validate(msg,7,pairing,"s",1,100),"paired command")
check(not P.validate(msg,8,pairing,"s",1,100),"wrong peer")
check(not P.validate(msg,7,pairing,"s",2,100),"replay")
check(not P.validate(msg,7,pairing,"s",1,110),"expired")
msg.sent=0/0;check(not P.validate(msg,7,pairing,"s",1,100),"nonfinite timestamp")
print("PASS: "..count.." autopilot assertions; no physical outputs invoked.")
