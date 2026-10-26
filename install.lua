-- NEXCORE FMS 2.0 installer for CC:Tweaked.
-- Upload this file to the ROOT of your GitHub repository.
-- Usage: install [branch] [repository-subfolder]
-- Examples: install main   OR   install main NEXCORE
-- No startup file is changed and no downloaded program is executed.
local args={...}
local branch=args[1] or "main"
local subfolder=args[2] or ""
local repository="sams930771/NEXCORE-Flight-Management-System-v2.0"
local destination="/nexcore_fms"
local staging="/nexcore_fms.download"
local files={
  "fms.lua", "calibrate.lua", "audit.lua", "selftest.lua",
  "nexcore/config.lua", "nexcore/core.lua", "nexcore/hardware.lua",
  "nexcore/commands.lua", "nexcore/ui.lua", "nexcore/validate.lua",
}
local function validPath(value)
  if value:find("..",1,true) or value:find("//",1,true) then return false end
  return value:match("^[%w_./%-]*$")~=nil
end
assert(validPath(branch) and branch~="","Invalid branch name")
assert(validPath(subfolder),"Invalid repository subfolder")
subfolder=subfolder:gsub("^/+",""):gsub("/+$","")
local base="https://raw.githubusercontent.com/"..repository.."/"..branch.."/"
if subfolder~="" then base=base..subfolder.."/" end
if not http or not http.get then error("HTTP is disabled or unavailable on this computer",0) end
if fs.exists(destination) then
  print("Installation folder already exists: "..destination)
  print("Nothing changed. Back up/rename that folder before installing again.")
  print("Your configuration and hover calibration records must be preserved.")
  return
end
if fs.exists(staging) then
  print("A previous download folder exists: "..staging)
  print("Nothing changed. Inspect/rename it, then run this installer again.")
  return
end
print("NEXCORE FMS 2.0 installer")
print("Source: "..repository.." / "..branch)
if subfolder~="" then print("Repository folder: "..subfolder) end
print("Downloading "..#files.." files. Flight controls will remain inactive.")
fs.makeDir(staging)
local function download(path,index)
  print("["..index.."/"..#files.."] "..path)
  local url=base..path
  -- Request a response handle even for HTTP errors, so it can be closed.
  local response,err,errorResponse=http.get(url,nil,false)
  if not response then
    if errorResponse then pcall(function() errorResponse.close() end) end
    error("Download failed: "..path.."\n"..tostring(err).."\nURL: "..url,0)
  end
  local ok,body=pcall(function()
    local code=response.getResponseCode()
    if code~=200 then error("HTTP "..tostring(code)) end
    return response.readAll()
  end)
  pcall(function() response.close() end)
  if not ok then error("Could not read "..path..": "..tostring(body),0) end
  if type(body)~="string" or #body==0 then error("Empty download: "..path,0) end
  -- This checks syntax only: downloaded code is NEVER executed by this installer.
  local fn,syntax=load(body,"@"..path,"t",{})
  if not fn then error("Invalid Lua in "..path..": "..tostring(syntax),0) end
  local target=fs.combine(staging,path)
  fs.makeDir(fs.getDir(target))
  local handle=assert(fs.open(target,"w"),"Cannot save "..path)
  local written,writeError=pcall(function() handle.write(body) end)
  pcall(function() handle.close() end)
  if not written then error("Could not save "..path..": "..tostring(writeError),0) end
end
local ok,err=pcall(function()
  for i,path in ipairs(files) do download(path,i) end
  -- Publish only after all required files have downloaded and parsed.
  -- Refuse to replace a folder created while the download was in progress.
  if fs.exists(destination) then error("Installation folder appeared during download; refusing to overwrite it",0) end
  fs.move(staging,destination)
end)
if not ok then
  printError(tostring(err))
  print("Installation did not complete. No flight program was started.")
  print("Partial files are retained in "..staging.." for inspection.")
  print("For a 404: check branch, public access, and extracted repository files.")
  print("If files are inside NEXCORE/, use: install "..branch.." NEXCORE")
  return
end
print("")
print("Installed successfully: "..destination)
print("Startup unchanged. No peripheral outputs were activated.")
print("Next, stop any existing flight program and enter:")
print("  cd "..destination)
print("  selftest")
print("  audit read")
print("  calibrate")
print("Use validated burner integer limits for the calibration test.")
