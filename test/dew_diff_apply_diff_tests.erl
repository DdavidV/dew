-module(dew_diff_apply_diff_tests).

-include_lib("eunit/include/eunit.hrl").

apply_single_replace_test() ->
  ?assertEqual(
    [a, x, c],
    dew_diff:apply_diff([a, b, c], [#{operation => replace, path => [#{type => list, index => 1}], value => x}])
  ).

apply_single_add_test() ->
  ?assertEqual(
    [a, x, b, c],
    dew_diff:apply_diff([a, b, c], [#{operation => add, path => [#{type => list, index => 1}], value => x}])
  ).

apply_single_remove_test() ->
  ?assertEqual(
    [a, c],
    dew_diff:apply_diff([a, b, c], [#{operation => remove, path => [#{type => list, index => 1}], value => b}])
  ).

apply_nested_map_change_test() ->
  ?assertEqual(
    #{user => #{age => 30, name => "alice"}},
    dew_diff:apply_diff(
      #{user => #{age => 20, name => "alice"}},
      [#{operation => replace, path => [#{type => map, key => user}, #{type => map, key => age}], value => 30}]
    )
  ).

apply_multi_step_diff_test() ->
  ?assertEqual(
    #{items => [a, x, c], user => #{name => "bob"}},
    dew_diff:apply_diff(
      #{items => [a, b, c], user => #{name => "alice"}},
      [
        #{operation => replace, path => [#{type => map, key => items}, #{type => list, index => 1}], value => x},
        #{operation => replace, path => [#{type => map, key => user}, #{type => map, key => name}], value => "bob"}
      ]
    )
  ).

roundtrip_list_diff_test() ->
  Old = [a, b, c, d],
  New = [a, x, c, y],
  Diff = dew_diff:diff(Old, New),
  ?assertEqual(New, dew_diff:apply_diff(Old, Diff)).

roundtrip_map_diff_test() ->
  Old = #{user => #{name => "alice", age => 20}, items => [1, 2, 3]},
  New = #{user => #{name => "bob", age => 30}, items => [1, 9, 3]},
  Diff = dew_diff:diff(Old, New),
  ?assertEqual(New, dew_diff:apply_diff(Old, Diff)).

pretty_print_mixed_operations_test() ->
  Diff = [
    #{operation => replace,
      path => [#{type => map, key => user}, #{type => map, key => name}],
      value => <<"David">>,
      old_value => <<"Dave">>},
    #{operation => add,
      path => [#{type => map, key => user}, #{type => map, key => id}],
      value => 21},
    #{operation => remove,
      path => [#{type => map, key => user}, #{type => map, key => email}],
      value => <<"old@example.com">>}
  ],
  ?assertEqual(
    "~ user.name\n  <<\"Dave\">>\n  <<\"David\">>\n\n"
    "+ user.id\n  21\n\n"
    "- user.email\n  <<\"old@example.com\">>\n",
    dew_diff:pretty_print(Diff)
  ).

reverse_list_diff_test() ->
  Old = [a, b, c, d],
  New = [a, x, c, y],
  Diff = dew_diff:diff(Old, New),
  ?assertEqual(Old, dew_diff:apply_diff(New, Diff, #{reverse => true})).

reverse_map_diff_test() ->
  Old = #{user => #{name => "alice", age => 20}, items => [1, 2, 3]},
  New = #{user => #{name => "bob", age => 30}, items => [1, 9, 3]},
  Diff = dew_diff:diff(Old, New),
  ?assertEqual(Old, dew_diff:apply_diff(New, Diff, #{reverse => true})).

reverse_diff_generation_test() ->
  Old = [a, b, c],
  New = [a, x, c],
  Diff = dew_diff:diff(Old, New),
  ?assertEqual(Old, dew_diff:apply_diff(New, Diff, #{reverse => true})).
