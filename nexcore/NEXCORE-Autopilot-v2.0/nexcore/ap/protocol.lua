local M={protocol="NEXCORE_SUMMON_V1"}
function M.validate(msg,sender,c,session,lastSeq,now)
 if type(msg)~="table" or sender~=c.peer or msg.key~=c.key or msg.session~=session then return false,"pair/session" end
 if type(msg.seq)~="number" or msg.seq%1~=0 or msg.seq<=lastSeq then return false,"replay" end
 if type(msg.sent)~="number" or msg.sent~=msg.sent or math.abs(msg.sent)==math.huge or math.abs(now-msg.sent)>5 then return false,"expired" end
 local allowed={heartbeat=true,status=true,stop=true,rearm=true,confirm=true,summon=true}
 if not allowed[msg.action] then return false,"action" end
 return true
end
return M
