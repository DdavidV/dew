-module(dew_pipe_tests).

-compile({parse_transform, dew_pipe}).

-include_lib("eunit/include/eunit.hrl").

simple_pipe_test_() ->
  [
    ?_assertEqual([3, 2, 1], dew_pipe:pipe([1, 2, 3], lists:reverse())),
    ?_assertEqual([3, 2, 1], pipe([1, 2, 3], lists:reverse()))
  ].

multiple_pipe_stages_test_() ->
  [
    ?_assertEqual(6, dew_pipe:pipe([1, 2, 3], lists:reverse(), lists:sum())),
    ?_assertEqual(6, pipe([1, 2, 3], lists:reverse(), lists:sum()))
  ].

tap_stage_test_() ->
  [
    ?_assertEqual(6, dew_pipe:pipe(
      [1, 2, 3],
      lists:reverse(),
      tap(fun(X) -> io:format("Reversed list: ~p~n", [X]) end),
      lists:sum())
    ),
    ?_assertEqual(6, pipe(
      [1, 2, 3],
      lists:reverse(),
      tap(fun(X) -> io:format("Reversed list: ~p~n", [X]) end),
      lists:sum())
    )
  ].

then_stage_test_() ->
  [
    ?_assertEqual(7, dew_pipe:pipe(
      [1, 2, 3],
      lists:reverse(),
      lists:sum(),
      then(fun(X) -> X + 1 end))
    ),
    ?_assertEqual(7, pipe(
      [1, 2, 3],
      lists:reverse(),
      lists:sum(),
      then(fun(X) -> X + 1 end))
    )
  ].

additional_arguments_test_() ->
  [
    ?_assertEqual([1, 2, 3, 4, 5], dew_pipe:pipe(
      [1, 2, 3],
      lists:append([4, 5]))
    ),
    ?_assertEqual([1, 2, 3, 4, 5], pipe(
      [1, 2, 3],
      lists:append([4, 5]))
    )
  ].
