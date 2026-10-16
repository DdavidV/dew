-module(dew_pid_tests).

-include_lib("eunit/include/eunit.hrl").

to_pid_test() ->
  Self = self(),
  "<" ++ Rest = pid_to_list(Self),
  [X, Y, Z] = [list_to_integer(S) || S <- string:tokens(Rest, ".>")],
  ?assertEqual(Self, dew_pid:to_pid(Self)),
  ?assertEqual(Self, dew_pid:to_pid(pid_to_list(Self))),
  ?assertEqual(Self, dew_pid:to_pid(list_to_binary(pid_to_list(Self)))),
  ?assertEqual(Self, dew_pid:to_pid({X, Y, Z})),
  ?assertEqual(whereis(code_server), dew_pid:to_pid(code_server)),
  ?assertEqual(undefined, dew_pid:to_pid(no_such_registered_name)),
  ?assertEqual(undefined, dew_pid:to_pid("not a pid")).

fold_test() ->
  Count = dew_pid:fold(fun(_, N) -> N + 1 end, 0),
  ?assert(Count > 0),
  ?assert(dew_pid:fold(fun(P, Acc) -> Acc orelse P =:= self() end, false)).
