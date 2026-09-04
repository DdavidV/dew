-module(dew_pmap_tests).

-include_lib("eunit/include/eunit.hrl").

list_result_preserves_input_order_test() ->
  Fun = fun
    (1) -> timer:sleep(30), 10;
    (2) -> 20;
    (3) -> timer:sleep(10), 30
  end,
  ?assertEqual(
    [10, 20, 30],
    dew_pmap:map(Fun, [1, 2, 3], #{max_worker_count => 3})
  ).

map_result_preserves_keys_test() ->
  Fun = fun(Key, Value) -> {Key, Value * 2} end,
  ?assertEqual(
    #{a => {a, 2}, b => {b, 4}},
    dew_pmap:map(Fun, #{a => 1, b => 2})
  ).

empty_input_result_matches_input_type_test_() ->
  [
    ?_assertEqual([], dew_pmap:map(fun(Value) -> Value end, [])),
    ?_assertEqual(#{}, dew_pmap:map(fun(_Key, Value) -> Value end, #{}))
  ].

list_crash_result_uses_original_position_test() ->
  Fun = fun
    (first) -> exit(first_failed);
    (second) -> second_succeeded
  end,
  ?assertEqual(
    [first_failed, second_succeeded],
    dew_pmap:map(Fun, [first, second],
      #{max_worker_count => 1, crash_handling => one_for_one})
  ).

map_crash_result_uses_original_key_test() ->
  Fun = fun
    (first, _Value) -> exit(first_failed);
    (second, Value) -> {second_succeeded, Value}
  end,
  ?assertEqual(
    #{first => first_failed, second => {second_succeeded, 2}},
    dew_pmap:map(Fun, #{first => 1, second => 2},
      #{max_worker_count => 1, crash_handling => one_for_one})
  ).

list_crash_result_uses_middle_position_test() ->
  Fun = fun
    (first) -> first_succeeded;
    (second) -> exit(second_failed);
    (third) -> third_succeeded
  end,
  ?assertEqual(
    [first_succeeded, second_failed, third_succeeded],
    dew_pmap:map(Fun, [first, second, third],
      #{max_worker_count => 1, crash_handling => one_for_one})
  ).

one_for_all_rethrows_worker_reason_test() ->
  Fun = fun(_Value) -> exit(worker_failed) end,
  ?assertError(
    worker_failed,
    dew_pmap:map(Fun, [value],
      #{max_worker_count => 1, crash_handling => one_for_all})
  ).

timeout_throws_and_stops_workers_test() ->
  Fun = fun(_Value) -> timer:sleep(50), finished end,
  ?assertThrow(
    timeout,
    dew_pmap:map(Fun, [value], #{max_worker_count => 1, timeout => 10})
  ).

graceful_timeout_is_stored_at_list_position_test() ->
  Parent = self(),
  Fun = fun
    (1) -> first_finished;
    (2) -> timer:sleep(50), Parent ! second_finished, second_finished;
    (3) -> third_finished
  end,
  ?assertEqual(
    [first_finished, timeout, third_finished],
    dew_pmap:map(Fun, [1, 2, 3],
      #{max_worker_count => 3, timeout => 10, timeout_handling => graceful})
  ),
  receive
    second_finished -> ?assert(false)
  after 100 ->
    ok
  end.

graceful_timeout_is_stored_under_map_key_test() ->
  Fun = fun
    (first, _Value) -> first_finished;
    (second, _Value) -> timer:sleep(50), second_finished;
    (third, _Value) -> third_finished
  end,
  ?assertEqual(
    #{first => first_finished, second => timeout, third => third_finished},
    dew_pmap:map(Fun, #{first => 1, second => 2, third => 3},
      #{max_worker_count => 3, timeout => 10, timeout_handling => graceful})
  ).

list_map_function_and_worker_limit_test() ->
  Fun = fun(Value) -> {Value, Value * 2} end,
  ?assertEqual(
    [{1, 2}, {2, 4}, {3, 6}],
    dew_pmap:map(Fun, [1, 2, 3], #{max_worker_count => 1})
  ).

node_selector_is_called_for_each_item_test() ->
  Parent = self(),
  NodeSelectFun = fun(Key) -> Parent ! {selected, Key}, node() end,
  Result = dew_pmap:map(
    fun(Value) -> Value end,
    [first, second],
    #{max_worker_count => 2, node_select_fun => NodeSelectFun}
  ),
  ?assertEqual([first, second], Result),
  ?assertEqual({selected, 1}, receive Message1 -> Message1 end),
  ?assertEqual({selected, 2}, receive Message2 -> Message2 end).