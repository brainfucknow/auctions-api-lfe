#!/usr/bin/env escript
%% Start the app on port 8080 with a throwaway log.
%% Usage: escript bench/boot.escript [nosync]
main(Args) ->
    application:load(auctions),
    application:set_env(auctions, events_file, "tmp/bench-events.log"),
    application:set_env(auctions, http_port, 8080),
    application:set_env(auctions, events_fsync, Args =/= ["nosync"]),
    {ok, _} = application:ensure_all_started(auctions),
    receive stop -> ok end.
