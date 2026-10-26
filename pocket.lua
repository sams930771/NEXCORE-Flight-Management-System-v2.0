-- Pocket summoning remote; snapshot destination, no continuous following.
local X=require("nexcore.ap.math");local P=require("nexcore.ap.protocol")
local root=fs.getDir(shell.getRunningProgram());local path=fs.combine(root,"pocket_settings.txt")
local args={...};local c
if fs.exists(path) then local f=fs.open(path,"r");c=textutils.unserialize(f.readAll());f.close() end
if not c or args[1]=="setup" then
 print("Pocket ID: "..os.getComputerID())
 write("Ship computer ID: ");local peer=tonumber(read());assert(X.finite(peer) and peer>=0 and peer%1==0)
 write("Same pair key as ship: ");local key=read("*");assert(#key>=8,"Use at least 8 characters")
 c={peer=peer,key=key};local f=assert(fs.open(path,"w"));f.write(textutils.serialize(c));f.close()
end
local modem
for _,name in ipairs(peripheral.getNames()) do
 local ok,wireless=pcall(peripheral.call,name,"isWireless")
 if ok and wireless then modem=name;break end
end
assert(modem,"Wireless modem required (use a wireless pocket computer)")
rednet.open(modem)
local function now() return os.epoch("utc")/1000 end
local function pause(s) local t=os.startTimer(s);repeat local e,id=os.pullEventRaw() until e=="timer" and id==t end
local S={seq=0,message="Connecting to ship",lastHello=0}
local function send(action,extra)
 if not S.session and action~="hello" then S.message="Waiting for ship session";return end
 local msg=extra or {};msg.action=action;msg.key=c.key;msg.session=S.session;msg.sent=now()
 if action~="hello" then S.seq=S.seq+1;msg.seq=S.seq end
 local ok,value=pcall(rednet.send,c.peer,msg,P.protocol)
 if not ok or value==false then S.message="Radio send failed" end
end
local function gpsWorker()
 while true do
  local ok,x,y,z=pcall(gps.locate,1,false)
  if ok and X.finite(x) and X.finite(y) and X.finite(z) then S.fix={x=x,y=y,z=z,at=now()} else S.fix=nil end
  pause(0.5)
 end
end
local function receiver()
 while true do
  local id,msg=rednet.receive(P.protocol,1)
  if id==c.peer and type(msg)=="table" and msg.key==c.key then
   if msg.kind=="hello" then
    S.session=msg.session;S.seq=math.max(S.seq,(msg.nextSeq or 1)-1);S.challenge=nil
   elseif msg.session~=S.session then msg=nil end
   if msg then
    S.lastReply=now();S.message=tostring(msg.detail);S.status=msg.status
    if msg.kind=="confirm" then S.challenge=msg.extra;S.challengeAt=now() end
   end
  end
 end
end
local function keyboard()
 while not S.quit do
  local event,key,held=os.pullEventRaw()
  if event=="terminate" then send("stop")
  elseif event=="key" and not held then
   if key==keys.x or key==keys.space then S.challenge=nil;send("stop")
   elseif key==keys.r then send("rearm")
   elseif key==keys.y then
    if S.challenge and now()-S.challengeAt<10 then send("confirm",{challenge=S.challenge});S.challenge=nil
    else S.message="Press R first for a current rearm confirmation" end
   elseif key==keys.s then
    local f=S.fix
    if not f or now()-f.at>3 then S.message="Fresh pocket GPS required; summon not sent"
    elseif not S.lastReply or now()-S.lastReply>5 then S.message="No recent ship acknowledgement"
    else send("summon",{x=f.x,y=f.y,z=f.z,fixAt=f.at}) end
   elseif key==keys.t then send("status")
   elseif key==keys.q then send("stop");S.quit=true end
  end
 end
end
local function linkWorker()
 while true do
  if not S.session or not S.lastReply or now()-S.lastReply>5 then send("hello") else send("heartbeat") end
  pause(2)
 end
end
local function display()
 while true do
  local t=term.current();local w,h=t.getSize();t.clear()
  local f=S.fix;local st=S.status or {}
  local rows={"NEXCORE SUMMON REMOTE",S.message,
   "Ship "..tostring(c.peer).." | link age "..tostring(S.lastReply and math.floor(now()-S.lastReply)),
   f and string.format("GPS %.1f %.1f %.1f",f.x,f.y,f.z) or "GPS unavailable",
   "Ship: "..tostring(st.mode).." | armed "..tostring(st.armed),
   "Lift hold "..tostring(st.lift).." | integer "..tostring(st.burn),
   "Distance "..tostring(st.distance),
   "R then Y: arm | S: summon",
   "X/SPACE: propulsion stop",
   "T status | Q stop + exit",
   "Arrives nearby at held altitude.","No automatic landing/obstacle detection."}
  for i,line in ipairs(rows) do if i>h then break end;t.setCursorPos(1,i);t.write(line:sub(1,w)) end
  pause(0.25)
 end
end
local jobs={gpsWorker,receiver,keyboard,linkWorker,display};local safe={}
for i,fn in ipairs(jobs) do safe[i]=function() while true do
 local ok,err=pcall(fn);if not ok then S.message="Remote worker error: "..tostring(err) end;pause(0.5)
end end end
parallel.waitForAny(function() parallel.waitForAll(table.unpack(safe)) end,function() while not S.quit do pause(0.1) end end)
print("Remote closed; ship stop sent. Lost-link stop requires the ship program to remain running.")
