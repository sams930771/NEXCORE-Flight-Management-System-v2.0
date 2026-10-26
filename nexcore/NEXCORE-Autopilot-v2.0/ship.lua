-- Integrated ship entry point. Start in STOP; H captures altitude, R then Y arms.
local root=fs.getDir(shell.getRunningProgram())
local Settings=require("nexcore.ap.settings")
local c,why=Settings.load(fs.combine(root,"ship_settings.txt"))
if not c then print(why);return end
Settings.validate(c)
require("nexcore.ap.runtime").run(c)
