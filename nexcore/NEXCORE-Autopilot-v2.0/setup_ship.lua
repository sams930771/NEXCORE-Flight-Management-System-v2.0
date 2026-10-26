-- Setup and compass-reference calibration. No peripheral outputs are written.
local Settings=require("nexcore.ap.settings");local X=require("nexcore.ap.math");local H=require("nexcore.ap.hardware")
local root=fs.getDir(shell.getRunningProgram());local path=fs.combine(root,"ship_settings.txt")
local args={...};local c=Settings.load(path) or Settings.defaults
local function number(label,default)
 write(label..(default~=nil and " ["..tostring(default).."]" or "")..": ")
 local s=read();local n=s=="" and default or tonumber(s);assert(X.finite(n),"A finite number is required");return n
end
if args[1]=="heading" then
 print("Use a fixed Navigation Table compass reference with KNOWN world X/Z.")
 print("A lodestone-bound compass is suitable; leave it in the table during flight.")
 print("Keep propulsion physically stopped. No outputs are changed by this setup.")
 c.reference={x=number("Compass reference WORLD X",c.reference.x),z=number("Compass reference WORLD Z",c.reference.z)}
 write("Is that exact fixed target installed on the table? Type YES: ")
 assert(read()=="YES","Reference confirmation required")
 local x,y,z=gps.locate(2,false);assert(X.finite(x) and X.finite(z),"GPS fix required")
 local position={x=x,z=z};assert(X.distance(position,c.reference)>c.nav.referenceExclusion,"Move farther from compass reference before calibrating")
 local ok,angle=H.invoke(H.names.nav,"getRelativeAngle");assert(ok and X.finite(angle),"Navigation angle required")
 print("Align your player's view with the ship's NOSE and use F3 direction/yaw.")
 print("N/E/S/W refer to the ship's nose, NOT the table's mounting direction.")
 write("Nose direction N/E/S/W, or exact F3 yaw: ");local cardinal=read():upper()
 local headings={N=-90,E=0,S=90,W=180}
 local known=headings[cardinal]
 if known==nil then local yaw=tonumber(cardinal);assert(X.finite(yaw),"Cardinal or finite F3 yaw required");known=X.wrap(yaw+90) end
 c.headingOffset=X.offset(position,c.reference,angle,known);c.referenceConfirmed=true
 print("Saved offset "..string.format("%.3f",c.headingOffset).." degrees.")
 print("Verify live heading during a short turn before any summon trial.")
else
 print("Ship computer ID: "..os.getComputerID())
 c.peer=number("Pocket computer ID",c.peer>=0 and c.peer or nil)
 write("Pair key (same on pocket; minimum 8 characters): ");local key=read("*")
 if key~="" then c.key=key end
 print("Ship uses wireless modem left. GPS must report the moving ship's world location.")
 write("Have you verified GPS follows actual ship movement? YES/NO: ");c.gpsVerified=read()=="YES"
 print("Existing calibrated burner baseline: 60; permitted integer range: 5..500.")
 print("Navigation speed is capped at tested target RPM 1.")
end
Settings.validate(c);Settings.save(path,c)
print("Saved "..path)
if not c.referenceConfirmed then print("Next: setup_ship heading") else print("Next: ship (starts propulsion stopped)") end
