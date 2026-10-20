-- POST /auctions/1/bids with increasing amounts (base passed via env BID_BASE)
local counter = 0
local tid = 0
local nthreads = 0
setup = function(thread) tid = tid + 1; thread:set("tid", tid); nthreads = tid end
init = function(args) tid = wrk.thread:get("tid") end
request = function()
  counter = counter + 1
  local amount = tonumber(os.getenv("BID_BASE") or "1000") + counter * 64 + tid
  local body = string.format('{"amount":%d}', amount)
  local auction = (counter % 50) + 1
  return wrk.format("POST", "/auctions/" .. auction .. "/bids", {["Content-Type"]="application/json", ["x-jwt-payload"]="eyJzdWIiOiJhMiIsICJuYW1lIjoiQnV5ZXIiLCAidV90eXAiOiIwIn0K"}, body)
end
