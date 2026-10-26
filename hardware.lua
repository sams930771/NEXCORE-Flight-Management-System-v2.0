-- Exact manifest transcribed from supplied diagnostics. No inferred setters.
local M={}
M.expected={}
local function add(name,kind,methods,role)
  M.expected[#M.expected+1]={name=name,kind=kind,methods=methods,role=role}
end
add("Create_SequencedGearshift_1","Create_SequencedGearshift",{"isRunning","move","rotate"},"gear")
for i=2,5 do add("aeronautics:adjustable_burner_"..i,"aeronautics:adjustable_burner",{"getScrollValue","setScrollValue"},"lift") end
for i=1,4 do add("aeronautics:propeller_bearing_"..i,"aeronautics:propeller_bearing",{"getScrollValue","setScrollValue"},"prop") end
add("back","altitude_sensor",{"getAirPressure","getHeight"},"height")
local modem={"close","closeAll","isOpen","isWireless","open","transmit"}
local wired={"callRemote","close","closeAll","getMethodsRemote","getNameLocal","getNamesRemote","getTypeRemote","hasTypeRemote","isOpen","isPresentRemote","isWireless","open","transmit"}
add("bottom","modem",wired,"network"); add("left","modem",modem,"network")
add("monitor_0","monitor",{"blit","clear","clearLine","getBackgroundColor","getBackgroundColour","getCursorBlink","getCursorPos","getPaletteColor","getPaletteColour","getSize","getTextColor","getTextColour","getTextScale","isColor","isColour","scroll","setBackgroundColor","setBackgroundColour","setCursorBlink","setCursorPos","setPaletteColor","setPaletteColour","setTextColor","setTextColour","setTextScale","write"},"display")
add("navigation_table_1","navigation_table",{"getRelativeAngle","getRelativeAngleRad"},"nav")
add("swivel_bearing_1","swivel_bearing",{"getTargetAngle","getTargetAngleRad"},"swivel")
add("top","modem",wired,"network")
for i=1,2 do add("velocity_sensor_"..i,"velocity_sensor",{"getVelocity"},"velocity") end
function M.check(spec)
  local ok,types=pcall(function() return {peripheral.getType(spec.name)} end)
  if not ok then return false,"type lookup failed" end
  local found=false
  for _,t in ipairs(types) do if t==spec.kind then found=true end end
  if not found then return false,"missing or wrong type" end
  local success,list=pcall(peripheral.getMethods,spec.name)
  if not success or not list then return false,"method lookup failed" end
  local methods={}; for _,m in ipairs(list) do methods[m]=true end
  for _,m in ipairs(spec.methods) do if not methods[m] then return false,"missing "..m end end
  return true
end
function M.lookup(name)
  for _,s in ipairs(M.expected) do if s.name==name then return s end end
end
function M.available(name,method)
  local spec=M.lookup(name)
  if not spec then return false end
  local ok=M.check(spec); if not ok then return false end
  for _,m in ipairs(spec.methods) do if m==method then return true end end
  return false
end
return M
