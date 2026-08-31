-module(dew_diff_list_diff_tests).

-include_lib("eunit/include/eunit.hrl").

empty_list_test() ->
  ?assertEqual([], dew_diff:diff([], [])).

identical_list_test_() ->
  [
    ?_assertEqual([], dew_diff:diff([a], [a])),
    ?_assertEqual([], dew_diff:diff([a, b, c], [a, b, c])),
    ?_assertEqual([], dew_diff:diff([1, 2, 3, 4, 5], [1, 2, 3, 4, 5])),
    ?_assertEqual([], dew_diff:diff([[a, b], [c, d]], [[a, b], [c, d]]))
  ].

single_element_replace_test() ->
  ?assertEqual(
    [#{operation => replace, path => [#{type => list, index => 0}], value => b, old_value => a}],
    dew_diff:diff([a], [b])
  ).

first_element_replace_test() ->
  ?assertEqual(
    [#{operation => replace, path => [#{type => list, index => 0}], value => x, old_value => a}],
    dew_diff:diff([a, b, c], [x, b, c])
  ).

middle_element_replace_test() ->
  ?assertEqual(
    [#{operation => replace, path => [#{type => list, index => 1}], value => x, old_value => b}],
    dew_diff:diff([a, b, c], [a, x, c])
  ).

last_element_replace_test() ->
  ?assertEqual(
    [#{operation => replace, path => [#{type => list, index => 2}], value => x, old_value => c}],
    dew_diff:diff([a, b, c], [a, b, x])
  ).

multiple_replacements_test() ->
  ?assertEqual(
    [
      #{operation => replace, path => [#{type => list, index => 0}], value => x, old_value => a},
      #{operation => replace, path => [#{type => list, index => 2}], value => z, old_value => c}
    ],
    dew_diff:diff([a, b, c], [x, b, z])
  ).

all_elements_replaced_test() ->
  ?assertEqual(
    [
      #{operation => replace, path => [#{type => list, index => 0}], value => x, old_value => a},
      #{operation => replace, path => [#{type => list, index => 1}], value => y, old_value => b},
      #{operation => replace, path => [#{type => list, index => 2}], value => z, old_value => c}
    ],
    dew_diff:diff([a, b, c], [x, y, z])
  ).

add_to_empty_list_test() ->
  ?assertEqual(
    [#{operation => add, path => [#{type => list, index => 0}], value => a}],
    dew_diff:diff([], [a])
  ).

add_to_end_test() ->
  ?assertEqual(
    [#{operation => add, path => [#{type => list, index => 3}], value => d}],
    dew_diff:diff([a, b, c], [a, b, c, d])
  ).

add_to_beginning_test() ->
  ?assertEqual(
    [#{operation => add, path => [#{type => list, index => 0}], value => x}],
    dew_diff:diff([a, b, c], [x, a, b, c])
  ).

add_to_middle_test() ->
  ?assertEqual(
    [#{operation => add, path => [#{type => list, index => 1}], value => x}],
    dew_diff:diff([a, b, c], [a, x, b, c])
  ).

multiple_additions_test() ->
  ?assertEqual(
    [
      #{operation => add, path => [#{type => list, index => 1}], value => x},
      #{operation => add, path => [#{type => list, index => 3}], value => y}
    ],
    dew_diff:diff([a, b, c], [a, x, b, y, c])
  ).

multiple_additions_at_beginning_test() ->
  ?assertEqual(
    [
      #{operation => add, path => [#{type => list, index => 0}], value => x},
      #{operation => add, path => [#{type => list, index => 1}], value => y}
    ],
    dew_diff:diff([a, b], [x, y, a, b])
  ).

multiple_additions_at_end_test() ->
  ?assertEqual(
    [
      #{operation => add, path => [#{type => list, index => 2}], value => x},
      #{operation => add, path => [#{type => list, index => 3}], value => y}
    ],
    dew_diff:diff([a, b], [a, b, x, y])
  ).

remove_single_element_test() ->
  ?assertEqual(
    [#{operation => remove, path => [#{type => list, index => 0}], value => a}],
    dew_diff:diff([a], [])
  ).

remove_first_element_test() ->
  ?assertEqual(
    [#{operation => remove, path => [#{type => list, index => 0}], value => a}],
    dew_diff:diff([a, b, c], [b, c])
  ).

remove_middle_element_test() ->
  ?assertEqual(
    [#{operation => remove, path => [#{type => list, index => 1}], value => b}],
    dew_diff:diff([a, b, c], [a, c])
  ).

remove_last_element_test() ->
  ?assertEqual(
    [#{operation => remove, path => [#{type => list, index => 2}], value => c}],
    dew_diff:diff([a, b, c], [a, b])
  ).

remove_multiple_elements_test() ->
  ?assertEqual(
    [
      #{operation => remove, path => [#{type => list, index => 1}], value => b},
      #{operation => remove, path => [#{type => list, index => 2}], value => d}
    ],
    dew_diff:diff([a, b, c, d], [a, c])
  ).

remove_multiple_from_beginning_test() ->
  ?assertEqual(
    [
      #{operation => remove, path => [#{type => list, index => 0}], value => a},
      #{operation => remove, path => [#{type => list, index => 0}], value => b}
    ],
    dew_diff:diff([a, b, c], [c])
  ).

remove_multiple_from_end_test() ->
  ?assertEqual(
    [
      #{operation => remove, path => [#{type => list, index => 2}], value => c},
      #{operation => remove, path => [#{type => list, index => 2}], value => d}
    ],
    dew_diff:diff([a, b, c, d], [a, b])
  ).

replace_with_insertion_test() ->
  ?assertEqual(
    [#{operation => replace, path => [#{type => list, index => 1}], value => x, old_value => b}],
    dew_diff:diff([a, b, c], [a, x, c])
  ).

shift_left_test() ->
  ?assertEqual(
    [#{operation => remove, path => [#{type => list, index => 0}], value => a}],
    dew_diff:diff([a, b, c, d], [b, c, d])
  ).

shift_right_test() ->
  ?assertEqual(
    [#{operation => add, path => [#{type => list, index => 0}], value => a}],
    dew_diff:diff([b, c, d], [a, b, c, d])
  ).

rotate_left_test() ->
  ?assertEqual(
    [
      #{operation => remove, path => [#{type => list, index => 0}], value => a},
      #{operation => add, path => [#{type => list, index => 2}], value => a}
    ],
    dew_diff:diff([a, b, c], [b, c, a])
  ).

rotate_right_test() ->
  ?assertEqual(
    [
      #{value => c, path => [#{index => 0,type => list}], operation => add},
      #{value => c, path => [#{index => 3,type => list}], operation => remove}
    ],
    dew_diff:diff([a, b, c], [c, a, b])
  ).

reverse_list_test() ->
  ?assert(dew_diff:diff([a, b, c], [c, b, a]) =/= []).

duplicate_values_equal_test() ->
  ?assertEqual([], dew_diff:diff([a, a, a], [a, a, a])).

duplicate_values_remove_one_test() ->
  ?assertEqual(1, length(dew_diff:diff([a, a, a], [a, a]))).

nested_list_replace_test() ->
  ?assertEqual(
    [#{operation => replace, path => [#{type => list, index => 0}, #{type => list, index => 1}], value => x, old_value => b}],
    dew_diff:diff([[a, b]], [[a, x]])
  ).

nested_list_add_test() ->
  ?assertEqual(
    [#{operation => add, path => [#{type => list, index => 1}], value => b}],
    dew_diff:diff([[a]], [[a], b])
  ).

nested_list_remove_test() ->
  ?assertEqual(
    [#{operation => remove, path => [#{type => list, index => 1}], value => b}],
    dew_diff:diff([[a], b], [[a]])
  ).

list_containing_maps_test() ->
  ?assertEqual(
    [#{operation => replace, path => [#{type => list, index => 0}, #{type => map, key => value}], value => 2, old_value => 1}],
    dew_diff:diff([#{value => 1}], [#{value => 2}])
  ).

list_containing_tuples_test() ->
  ?assertEqual(
    [#{operation => replace, path => [#{type => list, index => 0}], value => {x,b}, old_value => {a,b}}],
    dew_diff:diff([{a, b}], [{x, b}])
  ).

mixed_nested_terms_test() ->
  ?assert(dew_diff:diff([
    #{users => [{a, 1}, {b, 2}]}
  ], [
    #{users => [{a, 1}, {b, 3}]}
  ]) =/= []).

empty_to_many_test() ->
  ?assertEqual(3, length(dew_diff:diff([], [a, b, c]))).

many_to_empty_test() ->
  ?assertEqual(3, length(dew_diff:diff([a, b, c], []))).

one_to_many_test() ->
  ?assertEqual(2, length(dew_diff:diff([a], [a, b, c]))).

many_to_one_test() ->
  ?assertEqual(2, length(dew_diff:diff([a, b, c], [a]))).

list_to_non_list_test() ->
  ?assertEqual(
    [#{operation => replace, path => [], value => foo, old_value => [a, b]}],
    dew_diff:diff([a, b], foo)
  ).

non_list_to_list_test() ->
  ?assertEqual(
    [#{operation => replace, path => [], value => [a, b], old_value => foo}],
    dew_diff:diff(foo, [a, b])
  ).

replace_atoms_test() ->
  ?assert(dew_diff:diff([a], [b]) =/= []).

replace_integers_test() ->
  ?assert(dew_diff:diff([1], [2]) =/= []).

replace_binaries_test() ->
  ?assert(dew_diff:diff([<<"a">>], [<<"b">>]) =/= []).

replace_tuples_test() ->
  ?assert(dew_diff:diff([{a}], [{b}]) =/= []).

replace_maps_test() ->
  ?assert(dew_diff:diff([#{a => 1}], [#{a => 2}]) =/= []).

single_element_difference_is_not_empty_test() ->
  ?assert(dew_diff:diff([a], [b]) =/= []).

different_length_difference_is_not_empty_test() ->
  ?assert(dew_diff:diff([a], [a, b]) =/= []),
  ?assert(dew_diff:diff([a, b], [a]) =/= []).

completely_different_lists_are_not_empty_test() ->
  ?assert(dew_diff:diff([a, b, c], [x, y, z]) =/= []).

nested_difference_is_not_empty_test() ->
  ?assert(dew_diff:diff([[a, b], [c]], [[a, x], [c]]) =/= []).
