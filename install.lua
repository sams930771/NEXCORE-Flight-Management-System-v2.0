-- Upload install.lua to the repository root.
-- install ship [branch] [folder]   OR   install pocket [branch] [folder]
local args={...};local role=args[1] or "ship";local branch=args[2] or "main";local folder=args[3] or ""
-- Preserve the older `install main` invocation as a ship install.
if role~="ship" and role~="pocket" then folder=args[2] or "";branch=role;role="ship" end
local repo="sams930771/NEXCORE-Flight-Management-System-v2.0"
local destination="/nexcore_fms_ap";local staging=destination..".download"
local files=role=="pocket" and {"pocket.lua","nexcore/ap/math.lua","nexcore/ap/protocol.lua"} or {
 "ship.lua","setup_ship.lua","autopilot_test.lua","nexcore/ap/math.lua",
 "nexcore/ap/hardware.lua","nexcore/ap/protocol.lua","nexcore/ap/settings.lua","nexcore/ap/runtime.lua"}
local function valid(s) return s:match("^[%w_./%-]*$") and not s:find("..",1,true) and not s:find("//",1,true) end
assert(valid(branch) and branch~="" and valid(folder),"Invalid branch/folder")
folder=folder:gsub("^/+",""):gsub("/+$","")
local base="https://raw.githubusercontent.com/"..repo.."/"..branch.."/"..(folder~="" and folder.."/" or "")
if not http or not http.get then error("HTTP unavailable",0) end
if fs.exists(destination) or fs.exists(staging) then
 print("Installation/staging folder already exists. Nothing overwritten.")
 print("Preserve your ship_settings.txt or pocket_settings.txt before an upgrade.")
 print("Inspect/rename existing "..destination.." and "..staging.." before retrying.")
 return
end
fs.makeDir(staging)
local ok,why=pcall(function()
 for i,path in ipairs(files) do
  print("["..i.."/"..#files.."] "..path)
  local response,err,errorResponse=http.get(base..path,nil,false)
  if not response then if errorResponse then pcall(function() errorResponse.close() end) end;error(path..": "..tostring(err),0) end
  local good,body=pcall(function() assert(response.getResponseCode()==200,"HTTP error");return response.readAll() end)
  pcall(function() response.close() end)
  assert(good and type(body)=="string" and #body>0,"Download/read failed: "..path)
  local parsed,syntax=load(body,"@"..path,"t",{});assert(parsed,path..": "..tostring(syntax))
  local target=fs.combine(staging,path);fs.makeDir(fs.getDir(target));local f=assert(fs.open(target,"w"))
  local written,err=pcall(function() f.write(body) end);f.close();assert(written,err)
 end
 assert(not fs.exists(destination),"Destination appeared during download")
 fs.move(staging,destination)
end)
if not ok then printError(tostring(why));print("Incomplete download retained in "..staging);return end
print("Installed "..role.." in "..destination..". No flight code executed; startup unchanged.")
print("cd "..destination)
if role=="ship" then print("autopilot_test");print("setup_ship");print("setup_ship heading");print("ship") else print("pocket") end
