-- Audit never calls setters. `audit read` additionally trials zero-argument getters.
local U=require("nexcore.core")
local H=require("nexcore.hardware")
local args={...}; local rows={"NEXCORE live peripheral inventory"}
local names=peripheral.getNames(); table.sort(names)
for _,name in ipairs(names) do
  local types=U.pack(peripheral.getType(name)); types.n=nil
  local methods=peripheral.getMethods(name) or {}; table.sort(methods)
  rows[#rows+1]="\n"..name.." ["..table.concat(types,", ").."]"
  rows[#rows+1]=table.concat(methods,", ")
  local spec=H.lookup(name)
  if spec then local ok,why=H.check(spec); rows[#rows+1]=ok and "Manifest: OK" or "Manifest: "..tostring(why)
  else rows[#rows+1]="Manifest: additional device (never auto-bound)" end
end
for _,spec in ipairs(H.expected) do
  if not peripheral.isPresent(spec.name) then rows[#rows+1]="MISSING: "..spec.name end
end
local function save(path,lines)
  local f=assert(fs.open(path,"w")); f.write(table.concat(lines,"\n")); f.close()
end
save("audit.txt",rows); print("Inventory saved: audit.txt")
if args[1]~="read" then
  print("Optional: audit read (trials getters with no arguments, no setters)")
  return
end
local samples={"Read-only zero-argument trials; units and semantics UNVERIFIED"}
local done,total=0,0; local jobs={}
local getters={getScrollValue=true,getHeight=true,getAirPressure=true,
  getRelativeAngle=true,getRelativeAngleRad=true,getTargetAngle=true,
  getTargetAngleRad=true,getVelocity=true,isRunning=true,isWireless=true}
local pending={}
for _,spec in ipairs(H.expected) do
  for _,method in ipairs(spec.methods) do
    if getters[method] then
      local name,m=spec.name,method; local key=name.."."..m
      total=total+1; pending[key]=true
      jobs[#jobs+1]=function()
        local result=U.pack(pcall(peripheral.call,name,m))
        samples[#samples+1]=key.." => "..textutils.serialize(result,{compact=true})
        pending[key]=nil; done=done+1; save("readings.txt",samples)
      end
    end
  end
end
parallel.waitForAny(function() parallel.waitForAll(table.unpack(jobs)) end,function() U.sleep(8) end)
for key in pairs(pending) do samples[#samples+1]=key.." => TIMEOUT/not completed" end
save("readings.txt",samples)
print("Saved readings.txt: "..done.."/"..total.." completed. No output methods called.")
