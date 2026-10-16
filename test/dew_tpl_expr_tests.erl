-module(dew_tpl_expr_tests).

-include_lib("eunit/include/eunit.hrl").

render(Source, Data) ->
  {ok, Binary} = dew_tpl:render(Source, Data),
  Binary.

%% Renders `{{ if Expression }}T{{ else }}F{{ end }}' and returns true or false.
truth(Expression, Data) ->
  case render(<<"{{ if ", Expression/binary, " }}T{{ else }}F{{ end }}">>, Data) of
    <<"T">> -> true;
    <<"F">> -> false
  end.

paths_test_() ->
  Data = #{
    a => #{b => #{c => <<"deep">>}},
    list => [<<"zero">>, <<"one">>, #{name => <<"two">>}],
    map => #{<<"some key">> => <<"spaced">>, 3 => <<"int key">>},
    tuple => {x, y},
    props => [{name, <<"prop">>}, {other, 1}]
  },
  [
    ?_assertEqual(<<"deep">>, render(<<"{{ a.b.c }}">>, Data)),
    ?_assertEqual(<<"zero">>, render(<<"{{ list[0] }}">>, Data)),
    ?_assertEqual(<<"one">>, render(<<"{{ list[1] }}">>, Data)),
    ?_assertEqual(<<"two">>, render(<<"{{ list[2].name }}">>, Data)),
    ?_assertEqual(<<"int key">>, render(<<"{{ map[3] }}">>, Data)),
    ?_assertEqual(<<"y">>, render(<<"{{ tuple[1] }}">>, Data)),
    ?_assertEqual(<<"prop">>, render(<<"{{ props.name }}">>, Data)),
    ?_assertEqual(<<"deep">>, render(<<"{{ a[\"b\"].c }}">>, Data))
  ].

bracket_string_key_test() ->
  Data = #{<<"some key">> => <<"spaced">>},
  ?assertEqual({ok, <<"spaced">>}, dew_tpl:render(<<"{{ this[\"some key\"] }}">>, #{<<"this">> => Data}, #{keys => binary})).

literal_test_() ->
  [
    ?_assertEqual(<<"text">>, render(<<"{{ \"text\" }}">>, #{})),
    ?_assertEqual(<<"10">>, render(<<"{{ 10 }}">>, #{})),
    ?_assertEqual(<<"0.1">>, render(<<"{{ 0.1 }}">>, #{}))
  ].

precedence_test_() ->
  [
    ?_assert(truth(<<"not false and true">>, #{})),
    ?_assert(truth(<<"false and false or true">>, #{})),
    ?_assert(truth(<<"true or false and false">>, #{})),
    ?_assertNot(truth(<<"not (false or true)">>, #{})),
    ?_assert(truth(<<"not false == true">>, #{})),
    ?_assert(truth(<<"1 < 2 and 3 > 2">>, #{})),
    ?_assert(truth(<<"(1 < 2) == true">>, #{})),
    ?_assert(truth(<<"name | upper == \"BOB\"">>, #{name => <<"bob">>})),
    ?_assert(truth(<<"not not true">>, #{})),
    ?_assert(truth(<<"((true))">>, #{}))
  ].

and_or_return_operands_test_() ->
  [
    ?_assertEqual(<<"b">>, render(<<"{{ \"a\" and \"b\" }}">>, #{})),
    ?_assertEqual(<<>>, render(<<"{{ \"\" and \"b\" }}">>, #{})),
    ?_assertEqual(<<"a">>, render(<<"{{ \"a\" or \"b\" }}">>, #{})),
    ?_assertEqual(<<"b">>, render(<<"{{ nil or \"b\" }}">>, #{})),
    ?_assertEqual(<<"anon">>, render(<<"{{ nick or name or \"anon\" }}">>, #{nick => <<>>, name => <<>>}))
  ].

short_circuit_test_() ->
  [
    ?_assertEqual(<<"false">>, render(<<"{{ false and missing.key }}">>, #{})),
    ?_assertEqual(<<"true">>, render(<<"{{ true or missing.key }}">>, #{}))
  ].

equality_test_() ->
  Data = #{atom => admin, bin => <<"admin">>, list => "admin", int => 1, float => 1.0, undef => undefined},
  [
    ?_assert(truth(<<"atom == \"admin\"">>, Data)),
    ?_assert(truth(<<"bin == \"admin\"">>, Data)),
    ?_assert(truth(<<"list == \"admin\"">>, Data)),
    ?_assert(truth(<<"atom == bin">>, Data)),
    ?_assert(truth(<<"atom == list">>, Data)),
    ?_assert(truth(<<"int == float">>, Data)),
    ?_assert(truth(<<"int == 1">>, Data)),
    ?_assert(truth(<<"undef == nil">>, Data)),
    ?_assert(truth(<<"atom != \"user\"">>, Data)),
    ?_assertNot(truth(<<"int == \"1\"">>, Data)),
    ?_assertNot(truth(<<"undef == \"undefined\"">>, Data)),
    ?_assertNot(truth(<<"true == \"true\"">>, Data)),
    ?_assert(truth(<<"true == true">>, Data)),
    ?_assertNot(truth(<<"bin == nil">>, Data))
  ].

nil_variants_are_equal_test_() ->
  [
    ?_assert(truth(<<"x == nil">>, #{x => nil})),
    ?_assert(truth(<<"x == nil">>, #{x => null})),
    ?_assert(truth(<<"x == y">>, #{x => null, y => undefined}))
  ].

ordering_test_() ->
  [
    ?_assert(truth(<<"1 < 2">>, #{})),
    ?_assert(truth(<<"1.5 < 2">>, #{})),
    ?_assert(truth(<<"2 <= 2.0">>, #{})),
    ?_assertNot(truth(<<"3 < 2">>, #{})),
    ?_assert(truth(<<"\"a\" < \"b\"">>, #{})),
    ?_assert(truth(<<"x > \"apple\"">>, #{x => banana})),
    ?_assert(truth(<<"x >= \"abc\"">>, #{x => "abc"}))
  ].

ordering_type_mismatch_test_() ->
  Mismatch = fun(Expression, Data) ->
    {error, #{reason := Reason}} = dew_tpl:render(<<"{{ ", Expression/binary, " }}">>, Data),
    Reason
  end,
  [
    ?_assertEqual({type_mismatch, '<', 1, <<"a">>}, Mismatch(<<"1 < \"a\"">>, #{})),
    ?_assertEqual({type_mismatch, '>', true, false}, Mismatch(<<"true > false">>, #{})),
    ?_assertEqual({type_mismatch, '<=', undefined, 1}, Mismatch(<<"nil <= 1">>, #{})),
    ?_assertEqual({type_mismatch, '>=', #{}, 1}, Mismatch(<<"m >= 1">>, #{m => #{}}))
  ].

truthiness_test_() ->
  Falsy = [false, undefined, nil, null, [], <<>>, #{}],
  Truthy = [true, 0, 0.0, -1, <<"0">>, <<" ">>, "a", [x], #{a => 1}, {}, self(), atom],
  [?_assertNot(truth(<<"v">>, #{v => V})) || V <- Falsy] ++
  [?_assert(truth(<<"v">>, #{v => V})) || V <- Truthy].

pipes_test_() ->
  [
    ?_assertEqual(<<"BOB">>, render(<<"{{ name | upper }}">>, #{name => <<"bob">>})),
    ?_assertEqual(<<"BO">>, render(<<"{{ name | upper | truncate(2) }}">>, #{name => <<"bob">>})),
    ?_assertEqual(<<"a-b">>, render(<<"{{ items | join(\"-\") }}">>, #{items => [a, b]})),
    ?_assertEqual(<<"BOB">>, render(<<"{{ upper(name) }}">>, #{name => <<"bob">>})),
    ?_assertEqual(<<"x">>, render(<<"{{ missing | default(\"x\") }}">>, #{})),
    ?_assertEqual(<<"3">>, render(<<"{{ (\"abc\") | length }}">>, #{})),
    ?_assertEqual(<<"BOB">>, render(<<"{{ upper(lower(name)) }}">>, #{name => <<"BoB">>}))
  ].

defined_and_default_test_() ->
  [
    ?_assertEqual(<<"true">>, render(<<"{{ defined(a) }}">>, #{a => 1})),
    ?_assertEqual(<<"true">>, render(<<"{{ defined(a) }}">>, #{a => undefined})),
    ?_assertEqual(<<"false">>, render(<<"{{ defined(a) }}">>, #{})),
    ?_assertEqual(<<"false">>, render(<<"{{ defined(a.b.c) }}">>, #{a => #{}})),
    ?_assertEqual(<<"1">>, render(<<"{{ default(a, 2) }}">>, #{a => 1})),
    ?_assertEqual(<<"2">>, render(<<"{{ default(a, 2) }}">>, #{})),
    ?_assertEqual(<<"2">>, render(<<"{{ default(a, 2) }}">>, #{a => nil})),
    ?_assertEqual(<<>>, render(<<"{{ default(a, 2) }}">>, #{a => <<>>})),
    ?_assertEqual(<<"d">>, render(<<"{{ default(a.b, default(c, \"d\")) }}">>, #{}))
  ].

defined_with_missing_empty_test() ->
  ?assertEqual(
    {ok, <<"false">>},
    dew_tpl:render(<<"{{ defined(a) }}">>, #{}, #{missing => empty})
  ).
