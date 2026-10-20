#!/usr/bin/env escript
main(_) ->
    io:format("ensure_all_started: ~p~n", [application:ensure_all_started(auctions)]),
    io:format("sup pid:            ~p~n", [erlang:whereis('auctions-sup')]),
    io:format("children:           ~p~n", [supervisor:which_children('auctions-sup')]),
    io:format("running:            ~p~n", [lists:keyfind(auctions, 1, application:which_applications())]),
    ok = application:stop(auctions),
    io:format("stopped cleanly:    ok~n").
