-module(dew_tpl_builtins_tests).

-include_lib("eunit/include/eunit.hrl").

render(Source, Data) ->
  {ok, Binary} = dew_tpl:render(Source, Data),
  Binary.

reason(Source, Data) ->
  {error, #{phase := render, reason := Reason}} = dew_tpl:render(Source, Data),
  Reason.

upper_test_() ->
  [
    ?_assertEqual(<<"ABC">>, render(<<"{{ upper(v) }}">>, #{v => <<"abc">>})),
    ?_assertEqual(<<"ÁRVÍZ"/utf8>>, render(<<"{{ upper(v) }}">>, #{v => <<"árvíz"/utf8>>})),
    ?_assertEqual(<<"ATOM">>, render(<<"{{ upper(v) }}">>, #{v => atom})),
    ?_assertEqual(<<"12">>, render(<<"{{ upper(v) }}">>, #{v => 12})),
    ?_assertEqual(<<>>, render(<<"{{ upper(v) }}">>, #{v => <<>>})),
    ?_assertEqual({unrenderable_value, #{}}, reason(<<"{{ upper(v) }}">>, #{v => #{}}))
  ].

lower_test_() ->
  [
    ?_assertEqual(<<"abc">>, render(<<"{{ lower(v) }}">>, #{v => <<"ABC">>})),
    ?_assertEqual(<<"őű"/utf8>>, render(<<"{{ lower(v) }}">>, #{v => <<"ŐŰ"/utf8>>})),
    ?_assertEqual(<<>>, render(<<"{{ lower(v) }}">>, #{v => undefined})),
    ?_assertEqual({unrenderable_value, {a}}, reason(<<"{{ lower(v) }}">>, #{v => {a}}))
  ].

trim_test_() ->
  [
    ?_assertEqual(<<"[a b]">>, render(<<"[{{ trim(v) }}]">>, #{v => <<"  a b \n\t">>})),
    ?_assertEqual(<<"[x]">>, render(<<"[{{ trim(v) }}]">>, #{v => "  x  "})),
    ?_assertEqual(<<"[]">>, render(<<"[{{ trim(v) }}]">>, #{v => <<"   ">>})),
    ?_assertEqual(<<"[ű]"/utf8>>, render(<<"[{{ trim(v) }}]">>, #{v => <<" ű "/utf8>>}))
  ].

length_test_() ->
  [
    ?_assertEqual(<<"3">>, render(<<"{{ length(v) }}">>, #{v => <<"abc">>})),
    ?_assertEqual(<<"5">>, render(<<"{{ length(v) }}">>, #{v => <<"árvíz"/utf8>>})),
    ?_assertEqual(<<"2">>, render(<<"{{ length(v) }}">>, #{v => [a, b]})),
    ?_assertEqual(<<"1">>, render(<<"{{ length(v) }}">>, #{v => #{a => 1}})),
    ?_assertEqual(<<"3">>, render(<<"{{ length(v) }}">>, #{v => {a, b, c}})),
    ?_assertEqual(<<"0">>, render(<<"{{ length(v) }}">>, #{v => <<>>})),
    ?_assertEqual(<<"0">>, render(<<"{{ length(v) }}">>, #{v => undefined})),
    ?_assertEqual(<<"yes">>, render(<<"{{ if length(v) > 1 }}yes{{ end }}">>, #{v => [1, 2]})),
    ?_assertEqual({bad_argument, <<"length">>, 5}, reason(<<"{{ length(v) }}">>, #{v => 5})),
    ?_assertEqual({bad_argument, <<"length">>, true}, reason(<<"{{ length(v) }}">>, #{v => true}))
  ].

join_test_() ->
  [
    ?_assertEqual(<<"a, b, c">>, render(<<"{{ join(v, \", \") }}">>, #{v => [a, <<"b">>, "c"]})),
    ?_assertEqual(<<"1-2.5">>, render(<<"{{ join(v, \"-\") }}">>, #{v => [1, 2.5]})),
    ?_assertEqual(<<"a">>, render(<<"{{ join(v, \"-\") }}">>, #{v => [a]})),
    ?_assertEqual(<<>>, render(<<"{{ join(v, \"-\") }}">>, #{v => []})),
    ?_assertEqual(<<"á|é"/utf8>>, render(<<"{{ join(v, \"|\") }}">>, #{v => [<<"á"/utf8>>, <<"é"/utf8>>]})),
    ?_assertEqual(<<"a1b">>, render(<<"{{ join(v, 1) }}">>, #{v => [a, b]})),
    ?_assertEqual({bad_argument, <<"join">>, <<"ab">>}, reason(<<"{{ join(v, \",\") }}">>, #{v => <<"ab">>})),
    ?_assertEqual({unrenderable_value, {x}}, reason(<<"{{ join(v, \",\") }}">>, #{v => [{x}]}))
  ].

truncate_test_() ->
  [
    ?_assertEqual(<<"abc">>, render(<<"{{ truncate(v, 3) }}">>, #{v => <<"abcdef">>})),
    ?_assertEqual(<<"ab">>, render(<<"{{ truncate(v, 5) }}">>, #{v => <<"ab">>})),
    ?_assertEqual(<<>>, render(<<"{{ truncate(v, 0) }}">>, #{v => <<"ab">>})),
    ?_assertEqual(<<"árv"/utf8>>, render(<<"{{ truncate(v, 3) }}">>, #{v => <<"árvíz"/utf8>>})),
    ?_assertEqual(<<"12">>, render(<<"{{ truncate(v, 2) }}">>, #{v => 12345})),
    ?_assertEqual({bad_argument, <<"truncate">>, -1}, reason(<<"{{ truncate(v, -1) }}">>, #{v => <<"a">>})),
    ?_assertEqual({bad_argument, <<"truncate">>, <<"2">>}, reason(<<"{{ truncate(v, \"2\") }}">>, #{v => <<"a">>}))
  ].

escape_test_() ->
  [
    ?_assertEqual(<<"&lt;a href=&quot;x&quot;&gt;">>, render(<<"{{ escape(v) }}">>, #{v => <<"<a href=\"x\">">>})),
    ?_assertEqual(<<"&#39;&amp;">>, render(<<"{{ v | escape }}">>, #{v => "'&"})),
    ?_assertEqual(<<"plain">>, render(<<"{{ escape(v) }}">>, #{v => plain})),
    ?_assertEqual({unrenderable_value, [{}]}, reason(<<"{{ escape(v) }}">>, #{v => [{}]}))
  ].

raw_test_() ->
  [
    ?_assertEqual(<<"<b>">>, render(<<"{{ raw(v) }}">>, #{v => <<"<b>">>})),
    ?_assertEqual(<<"<B>">>, render(<<"{{ raw(v | upper) }}">>, #{v => <<"<b>">>}))
  ].

builtin_error_position_test() ->
  ?assertMatch(
    {error, #{reason := {bad_argument, <<"length">>, 1}, line := 2, column := 11}},
    dew_tpl:render(<<"\nxx {{ v | length }}">>, #{v => 1})
  ).

invalid_utf8_arguments_test_() ->
  Bad = <<255, 254>>,
  Error = fun(Source) ->
    case dew_tpl:render(Source, #{v => Bad}) of
      {ok, _} -> ok;
      {error, #{reason := {bad_argument, _, _}}} -> ok
    end
  end,
  [
    ?_assertEqual(ok, Error(<<"{{ upper(v) }}">>)),
    ?_assertEqual(ok, Error(<<"{{ lower(v) }}">>)),
    ?_assertEqual(ok, Error(<<"{{ trim(v) }}">>)),
    ?_assertEqual(ok, Error(<<"{{ length(v) }}">>)),
    ?_assertEqual(ok, Error(<<"{{ truncate(v, 1) }}">>))
  ].

builtin_arity_test_() ->
  Arity = fun(Source) ->
    {error, #{phase := compile, reason := Reason}} = dew_tpl:compile(Source),
    Reason
  end,
  [
    ?_assertEqual({bad_arity, <<"upper">>, 1, 2}, Arity(<<"{{ upper(a, b) }}">>)),
    ?_assertEqual({bad_arity, <<"join">>, 2, 1}, Arity(<<"{{ a | join }}">>)),
    ?_assertEqual({bad_arity, <<"truncate">>, 2, 0}, Arity(<<"{{ truncate() }}">>)),
    ?_assertEqual({bad_arity, <<"default">>, 2, 1}, Arity(<<"{{ default(a) }}">>)),
    ?_assertEqual({bad_arity, <<"raw">>, 1, 2}, Arity(<<"{{ raw(a, b) }}">>)),
    ?_assertEqual({bad_arity, <<"defined">>, 1, 0}, Arity(<<"{{ defined() }}">>))
  ].
