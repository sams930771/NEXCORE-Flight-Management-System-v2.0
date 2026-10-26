local U=require("nexcore.core")
local M={}
local function val(v)
  if v==nil then return "--" end
  return textutils.serialize(v,{compact=true}):gsub("\n"," ")
end
local function lines(S,C)
  local function sample(key,label)
    local v=S.samples[key]
    if not v then return label..": waiting" end
    local age=v.at and string.format("%.1fs",U.now()-v.at) or "no sample"
    return label.." ["..age.."] "..val(v.values or v.error or v)
  end
  local health=0; for _,h in pairs(S.health) do if h.ok then health=health+1 end end
  local rows={"NEXCORE FMS 2.0 | AEROSTATE", "Hardware "..health.."/18 | "..(S.hold and "ALT HOLD" or "LIFT HOLD OFF").." | PROP "..(S.estop and "STOP" or "CRUISE"),
    "Altitude source: "..C.source.." | Y "..(S.alt and string.format("%.2f",S.alt.y) or "UNVERIFIED/STALE"),
    "Target "..val(S.target).." | Lift demand "..string.format("%.3f",S.burn),
    string.format("Thrust %.2f | Yaw %.2f | Steering %s",S.forward,S.yaw,C.steering.mode),
    sample("gps","GPS"),sample("height","Height raw"),sample("pressure","Pressure raw"),
    sample("nav","Relative angle raw"),sample("swivel","Swivel TARGET raw"),
    sample("velocity_sensor_1","Velocity 1 raw"),sample("velocity_sensor_2","Velocity 2 raw"),
    "Gear running: "..val(S.gear.running).." | "..tostring(S.gear.error or "polling"),
    S.message,"H: capture/hold | P: automatic cruise | Up/Down: altitude",
    "SPACE/X: propulsion stop | F: freeze lift | R: recovery check"}
  for name,o in pairs(S.outputs) do
    if o.error or o.busy then rows[#rows+1]=name..": "..tostring(o.error or "PENDING") end
  end
  for name,h in pairs(S.health) do if not h.ok then rows[#rows+1]=name..": "..tostring(h.error) end end
  return rows
end
function M.worker(S,C,target)
  return function()
    while true do
      pcall(function()
        local t=target=="local" and term.current() or peripheral.wrap(C.monitor)
        if t then
          local w,h=t.getSize(); t.clear()
          for i,line in ipairs(lines(S,C)) do
            if i>h then break end
            t.setCursorPos(1,i); t.write(line:sub(1,w))
          end
        end
      end)
      U.sleep(0.25)
    end
  end
end
return M
