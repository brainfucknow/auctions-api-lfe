-- POST /auctions with unique ids per request
local counter = 0
local tid = 0
setup = function(thread) tid = tid + 1; thread:set("tid", tid) end
init = function(args) tid = wrk.thread:get("tid") end
request = function()
  counter = counter + 1
  local id = 1000000 + tid * 10000000 + counter
  local body = string.format('{"id":%d,"startsAt":"2023-01-01T10:00:00.000Z","endsAt":"2033-12-31T10:00:00.000Z","title":"Load","currency":"VAC"}', id)
  return wrk.format("POST", "/auctions", {["Content-Type"]="application/json", ["x-jwt-payload"]="eyJzdWIiOiJhMSIsICJuYW1lIjoiVGVzdCIsICJ1X3R5cCI6IjAifQo="}, body)
end
statuses = {}
response = function(status, headers, body) statuses[status] = (statuses[status] or 0) + 1 end
done = function(summary, latency, requests) end
