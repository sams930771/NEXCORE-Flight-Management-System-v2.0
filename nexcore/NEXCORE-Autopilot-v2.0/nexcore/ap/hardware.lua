local M={}
M.names={speed="Create_RotationSpeedController_3",relay="redstone_relay_2",
 height="back",nav="navigation_table_1",monitor="monitor_0",wireless="left"}
M.burners={};M.props={}
for i=2,5 do M.burners[#M.burners+1]="aeronautics:adjustable_burner_"..i end
for i=1,4 do M.props[i]="aeronautics:propeller_bearing_"..i end
M.specs={}
local function add(n,t,m) M.specs[n]={kind=t,methods=m} end
add(M.names.speed,"Create_RotationSpeedController",{"getTargetSpeed","setTargetSpeed"})
add(M.names.relay,"redstone_relay",{"getOutput","setOutput"})
add(M.names.height,"altitude_sensor",{"getHeight","getAirPressure"})
add(M.names.nav,"navigation_table",{"getRelativeAngle","getRelativeAngleRad"})
for _,n in ipairs(M.burners) do add(n,"aeronautics:adjustable_burner",{"getScrollValue","setScrollValue"}) end
for _,n in ipairs(M.props) do add(n,"aeronautics:propeller_bearing",{"getScrollValue","setScrollValue"}) end
for i=1,2 do
 add("velocity_sensor_"..i,"velocity_sensor",{"getVelocity"});M.specs["velocity_sensor_"..i].optional=true
end
add("swivel_bearing_1","swivel_bearing",{"getTargetAngle","getTargetAngleRad"});M.specs.swivel_bearing_1.optional=true
add("Create_SequencedGearshift_1","Create_SequencedGearshift",{"rotate","move","isRunning"});M.specs.Create_SequencedGearshift_1.optional=true
function M.check(name)
 local spec=M.specs[name]; if not spec then return false,"Unconfigured device" end
 local result={pcall(peripheral.getType,name)};if not result[1] then return false,"type lookup failed" end
 local match=false;for i=2,#result do if result[i]==spec.kind then match=true end end
 if not match then return false,"missing or wrong type: "..name end
 local ok,list=pcall(peripheral.getMethods,name);if not ok or not list then return false,"no methods: "..name end
 local seen={};for _,m in ipairs(list) do seen[m]=true end
 for _,m in ipairs(spec.methods) do if not seen[m] then return false,"missing "..name.."."..m end end
 return true
end
function M.invoke(name,method,...)
 local ok,why=M.check(name);if not ok then return false,why end
 return pcall(peripheral.call,name,method,...)
end
return M
