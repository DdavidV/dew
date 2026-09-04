-module(dew_retry_tests).

-include_lib("eunit/include/eunit.hrl").

-export([
  return_ok/0,
  return_error/0,
  return_argument/1
]).

run_returns_success_without_retry_test() ->
  put(retry_count, 0),
  dew_retry:run(fun next_count/0, #{}),
  ?assertEqual(1, get(retry_count)).

run_retries_default_errors_test() ->
  put(retry_count, 0),
  Fun = fun() ->
    Count = next_count(),
    case Count of
      0 -> {error, temporary};
      _ -> ok
    end
  end,
  Result = dew_retry:run(Fun, #{max_retries => 1}),
  ?assertEqual(ok, Result),
  ?assertEqual(2, get(retry_count)).

run_stops_after_retry_limit_test() ->
  put(retry_count, 0),
  Result = dew_retry:run(fun return_error/0, #{max_retries => 2}),
  ?assertEqual({error, permanent}, Result),
  ?assertEqual(3, get(retry_count)).

run_honors_max_elapsed_test() ->
  Result = dew_retry:run(fun() -> {error, elapsed} end, #{
    max_retries => infinity,
    max_elapsed => -1
  }),
  ?assertEqual({error, elapsed}, Result).

run_custom_retry_evaluator_stops_test() ->
  Result = dew_retry:run(fun() -> unexpected end, #{
    retry_eval => fun(_Context) -> stop end
  }),
  ?assertEqual(unexpected, Result).

run_custom_retry_evaluator_retries_test() ->
  put(retry_count, 0),
  Result = dew_retry:run(fun next_count/0, #{
      max_retries => 1,
      retry_eval => fun(#{result := 0}) -> retry;
                       (_) -> stop
                    end
    }
  ),
  ?assertEqual(1, Result),
  ?assertEqual(2, get(retry_count)).

run_allows_infinite_retries_until_evaluator_stops_test() ->
  Self = self(),
  Result = dew_retry:run(fun() -> {error, retry} end, #{
    max_retries => infinity,
    retry_eval => fun(#{attempt := 1} = Context) ->
                    Self ! {attempt_context, Context}, retry;
                   (#{attempt := 2} = Context) ->
                    Self ! {attempt_context, Context}, stop
                end
  }),
  ?assertEqual({error, retry}, Result),
  receive
    {attempt_context, FirstContext} ->
      ?assertEqual(1, maps:get(attempt, FirstContext)),
      ?assertEqual(undefined, maps:get(previous_delay, FirstContext))
  after 1000 ->
    ?assert(false)
  end,
  receive
    {attempt_context, SecondContext} ->
      ?assertEqual(2, maps:get(attempt, SecondContext)),
      ?assertEqual(0, maps:get(previous_delay, SecondContext))
  after 1000 ->
    ?assert(false)
  end.

run_does_not_delay_when_elapsed_limit_is_reached_test() ->
  Result = dew_retry:run(fun() -> {error, elapsed} end, #{
    max_retries => infinity,
    max_elapsed => -1,
    backoff => fun(_) -> erlang:error(backoff_should_not_run) end
  }),
  ?assertEqual({error, elapsed}, Result).

run_calls_retry_logger_with_context_test() ->
  Self = self(),
  Result = dew_retry:run(fun() -> {error, retry} end, #{
    max_retries => 1,
    retry_logger => fun(Context) -> Self ! {retry_logged, Context}, ok end
  }),
  ?assertEqual({error, retry}, Result),
  receive
    {retry_logged, Context} ->
      ?assertEqual({error, retry}, maps:get(result, Context)),
      ?assertEqual(1, maps:get(attempt, Context)),
      ?assertEqual(0, maps:get(retries, Context)),
      ?assertEqual(undefined, maps:get(previous_delay, Context)),
      ?assert(is_integer(maps:get(start_time, Context))),
      ?assert(is_integer(maps:get(elapsed, Context)))
  after 1000 ->
    ?assert(false)
  end.

run_passes_context_to_backoff_and_jitter_test() ->
  Self = self(),
  Result = dew_retry:run(fun() -> {error, retry} end, #{
    max_retries => 1,
    backoff => fun(Context) -> Self ! {backoff_context, Context}, 7 end,
    jitter => fun(7, Context) -> Self ! {jitter_context, Context}, 0 end
  }),
  ?assertEqual({error, retry}, Result),
  receive
    {backoff_context, BackoffContext} ->
      ?assertEqual({error, retry}, maps:get(result, BackoffContext)),
      ?assertEqual(1, maps:get(attempt, BackoffContext))
  after 1000 ->
    ?assert(false)
  end,
  receive
    {jitter_context, JitterContext} ->
      ?assertEqual({error, retry}, maps:get(result, JitterContext)),
      ?assertEqual(1, maps:get(attempt, JitterContext)),
      ?assertEqual(undefined, maps:get(previous_delay, JitterContext))
  after 1000 ->
    ?assert(false)
  end.

run_supports_zero_argument_mfa_test() ->
  ?assertEqual(ok, dew_retry:run({?MODULE, return_ok}, #{})).

run_supports_argument_mfa_test() ->
  ?assertEqual({ok, value}, dew_retry:run({?MODULE, return_argument, [value]}, #{})).

constant_returns_configured_delay_test() ->
  Backoff = dew_retry:constant(42),
  ?assertEqual(42, Backoff(test_context(1))).

linear_uses_attempt_number_test() ->
  Backoff = dew_retry:linear(3),
  ?assertEqual(3, Backoff(test_context(1))),
  ?assertEqual(12, Backoff(test_context(4))).

exponential_uses_powers_of_two_test() ->
  Backoff = dew_retry:exponential(3),
  ?assertEqual(3, Backoff(test_context(1))),
  ?assertEqual(6, Backoff(test_context(2))),
  ?assertEqual(12, Backoff(test_context(3))).

exponential_applies_maximum_test() ->
  Backoff = dew_retry:exponential(3, 7),
  ?assertEqual(3, Backoff(test_context(1))),
  ?assertEqual(6, Backoff(test_context(2))),
  ?assertEqual(7, Backoff(test_context(3))).

no_jitter_preserves_delay_test() ->
  Jitter = dew_retry:no_jitter(),
  ?assertEqual(11, Jitter(11, test_context(1))).

full_jitter_returns_value_in_range_test() ->
  Jitter = dew_retry:full_jitter(),
  ?assertEqual(0, Jitter(0, test_context(1))),
  Values = [Jitter(10, test_context(1)) || _ <- lists:seq(1, 100)],
  ?assert(lists:all(fun(Value) -> Value >= 0 andalso Value < 10 end, Values)),
  ?assert(lists:any(fun(Value) -> Value > 0 end, Values)).

equal_jitter_returns_value_in_range_test() ->
  Jitter = dew_retry:equal_jitter(),
  ?assertEqual(0, Jitter(0, test_context(1))),
  Values = [Jitter(10, test_context(1)) || _ <- lists:seq(1, 100)],
  ?assert(lists:all(fun(Value) -> Value >= 5 andalso Value < 11 end, Values)).

percent_range_jitter_returns_value_in_range_test() ->
  Jitter = dew_retry:percent_range_jitter(30),
  Values = [Jitter(10, test_context(1)) || _ <- lists:seq(1, 100)],
  ?assert(lists:all(fun(Value) -> Value >= 3 andalso Value < 11 end, Values)),
  ZeroJitter = dew_retry:percent_range_jitter(30),
  ?assertEqual(0, ZeroJitter(0, test_context(1))).

test_context(Attempt) ->
  #{
    start_time => 0,
    elapsed => 0,
    attempt => Attempt,
    retries => 0,
    previous_delay => undefined,
    result => undefined
  }.

next_count() ->
  Count = case get(retry_count) of
    Value when is_integer(Value) -> Value;
    _ -> 0
  end,
  put(retry_count, Count + 1),
  Count.

return_ok() ->
  ok.

return_error() ->
  next_count(),
  {error, permanent}.

return_argument(Value) ->
  {ok, Value}.
