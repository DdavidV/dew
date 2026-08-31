-module(dew_diff_map_diff_tests).

-include_lib("eunit/include/eunit.hrl").

empty_map_test() ->
  ?assertEqual([], dew_diff:diff(#{}, #{})).

identical_map_test_() ->
  [
    ?_assertEqual([], dew_diff:diff(#{a => 1}, #{a => 1})),
    ?_assertEqual([], dew_diff:diff(#{a => 1, b => 2}, #{a => 1, b => 2})),
    ?_assertEqual([], dew_diff:diff(#{key => #{nested => [1, 2, 3]}}, #{key => #{nested => [1, 2, 3]}}))
  ].

single_value_change_test() ->
  ?assertEqual(
    [#{operation => replace, path => [#{type => map, key => value}], value => 2, old_value => 1}],
    dew_diff:diff(#{value => 1}, #{value => 2})
  ).

missing_key_remove_test() ->
  ?assertEqual(
    [#{operation => remove, path => [#{type => map, key => b}], value => 2}],
    dew_diff:diff(#{a => 1, b => 2}, #{a => 1})
  ).

new_key_add_test() ->
  ?assertEqual(
    [#{operation => add, path => [#{type => map, key => c}], value => 3}],
    dew_diff:diff(#{a => 1}, #{a => 1, c => 3})
  ).

multiple_map_changes_test() ->
  ?assertEqual(
    [
      #{operation => replace, path => [#{type => map, key => a}], value => 10, old_value => 1},
      #{operation => remove, path => [#{type => map, key => d}], value => 4},
      #{operation => add, path => [#{type => map, key => c}], value => 3}
    ],
    dew_diff:diff(#{a => 1, b => 2, d => 4}, #{a => 10, b => 2, c => 3})
  ).

nested_map_change_test() ->
  ?assertEqual(
    [#{operation => replace, path => [#{type => map, key => user}, #{type => map, key => age}], value => 30, old_value => 20}],
    dew_diff:diff(#{user => #{age => 20}}, #{user => #{age => 30}})
  ).

nested_map_add_test() ->
  ?assertEqual(
    [#{operation => add, path => [#{type => map, key => user}, #{type => map, key => name}], value => "bob"}],
    dew_diff:diff(#{user => #{}}, #{user => #{name => "bob"}})
  ).

nested_map_remove_test() ->
  ?assertEqual(
    [#{operation => remove, path => [#{type => map, key => user}, #{type => map, key => age}], value => 20}],
    dew_diff:diff(#{user => #{age => 20, name => "alice"}}, #{user => #{name => "alice"}})
  ).

map_with_list_value_test() ->
  ?assertEqual(
    [#{operation => add, path => [#{type => map, key => items}, #{type => list, index => 2}], value => 3}],
    dew_diff:diff(#{items => [1, 2]}, #{items => [1, 2, 3]})
  ).

map_to_non_map_test() ->
  ?assertEqual(
    [#{operation => replace, path => [], value => foo, old_value => #{a => 1}}],
    dew_diff:diff(#{a => 1}, foo)
  ).

non_map_to_map_test() ->
  ?assertEqual(
    [#{operation => replace, path => [], value => #{a => 1}, old_value => foo}],
    dew_diff:diff(foo, #{a => 1})
  ).

map_replacing_nested_list_value_test() ->
  ?assertEqual(
    [#{operation => replace, path => [#{type => map, key => items}, #{type => list, index => 1}], value => x, old_value => b}],
    dew_diff:diff(#{items => [a, b, c]}, #{items => [a, x, c]})
  ).

map_with_tuple_value_test() ->
  ?assertEqual(
    [#{operation => replace, path => [#{type => map, key => pair}], value => {x, 2}, old_value => {a, 2}}],
    dew_diff:diff(#{pair => {a, 2}}, #{pair => {x, 2}})
  ).

different_map_not_empty_test() ->
  ?assert(dew_diff:diff(#{a => 1}, #{a => 2}) =/= []).

different_nested_map_not_empty_test() ->
  ?assert(dew_diff:diff(#{outer => #{inner => 1}}, #{outer => #{inner => 2}}) =/= []).

map_with_multiple_nested_changes_test() ->
  ?assertEqual(
    [
      #{operation => replace, path => [#{type => map, key => user}, #{type => map, key => age}], value => 35, old_value => 20},
      #{operation => add, path => [#{type => map, key => user}, #{type => map, key => city}], value => "Paris"}
    ],
    dew_diff:diff(#{user => #{age => 20, name => "alice"}}, #{user => #{age => 35, name => "alice", city => "Paris"}})
  ).
