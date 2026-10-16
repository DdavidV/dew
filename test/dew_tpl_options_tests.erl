-module(dew_tpl_options_tests).

-include_lib("eunit/include/eunit.hrl").

render(Source, Data, Options) ->
  {ok, Binary} = dew_tpl:render(Source, Data, Options),
  Binary.

reason(Result) ->
  {error, #{reason := Reason}} = Result,
  Reason.

keys_atom_default_test() ->
  ?assertEqual({ok, <<"1">>}, dew_tpl:render(<<"{{ a.b }}">>, #{a => #{b => 1}})),
  ?assertEqual({missing_key, <<"a">>}, reason(dew_tpl:render(<<"{{ a }}">>, #{<<"a">> => 1}))).

keys_atom_test() ->
  ?assertEqual(<<"1">>, render(<<"{{ a.b }}">>, #{a => #{b => 1}}, #{keys => atom})).

keys_binary_test() ->
  ?assertEqual(<<"1">>, render(<<"{{ a.b }}">>, #{<<"a">> => #{<<"b">> => 1}}, #{keys => binary})),
  ?assertEqual({missing_key, <<"a">>}, reason(dew_tpl:render(<<"{{ a }}">>, #{a => 1}, #{keys => binary}))).

keys_string_test() ->
  ?assertEqual(<<"1">>, render(<<"{{ a.b }}">>, #{"a" => #{"b" => 1}}, #{keys => string})),
  ?assertEqual(<<"x">>, render(<<"{{ a }}">>, [{"a", x}], #{keys => string})).

keys_fun_test() ->
  Keys = fun(Name) -> {key, Name} end,
  ?assertEqual(<<"1">>, render(<<"{{ a.b }}">>, #{{key, <<"a">>} => #{{key, <<"b">>} => 1}}, #{keys => Keys})).

keys_fun_crash_test() ->
  Keys = fun(_) -> erlang:error(boom) end,
  ?assertMatch(
    {error, #{phase := compile, reason := {function_crashed, keys, error, boom}, line := 1, column := 4}},
    dew_tpl:compile(<<"{{ a }}">>, #{keys => Keys})
  ).

keys_atom_does_not_create_atoms_test() ->
  Name = <<"dew_tpl_test_never_created_atom_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
  {ok, Template} = dew_tpl:compile(<<"{{ ", Name/binary, " }}">>),
  ?assertEqual({missing_key, Name}, reason(dew_tpl:render(Template, #{}))),
  ?assertError(badarg, binary_to_existing_atom(Name, utf8)).

keys_atom_created_after_compile_test() ->
  Name = <<"dew_tpl_test_late_atom_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
  {ok, Template} = dew_tpl:compile(<<"{{ x.", Name/binary, " }}">>),
  Atom = binary_to_atom(Name, utf8),
  ?assertEqual({ok, <<"late">>}, dew_tpl:render(Template, #{x => #{Atom => late}})).

late_atom_on_non_container_test() ->
  Name = <<"dew_tpl_test_never_atom_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
  ?assertMatch({not_accessible, _, 5}, reason(dew_tpl:render(<<"{{ x.", Name/binary, " }}">>, #{x => 5}))),
  ?assertMatch({missing_key, _}, reason(dew_tpl:render(<<"{{ x.", Name/binary, " }}">>, #{x => nil}))).

missing_error_default_test() ->
  ?assertMatch({error, #{reason := {missing_key, <<"a">>}}}, dew_tpl:render(<<"{{ a }}">>, #{})).

missing_empty_test_() ->
  Options = #{missing => empty},
  [
    ?_assertEqual(<<"[]">>, render(<<"[{{ a }}]">>, #{}, Options)),
    ?_assertEqual(<<"[]">>, render(<<"[{{ a.b.c }}]">>, #{a => #{}}, Options)),
    ?_assertEqual(<<"no">>, render(<<"{{ if a }}yes{{ else }}no{{ end }}">>, #{}, Options)),
    ?_assertEqual(<<"empty">>, render(<<"{{ for x in a }}{{ x }}{{ else }}empty{{ end }}">>, #{}, Options)),
    ?_assertEqual(<<"d">>, render(<<"{{ default(a, \"d\") }}">>, #{}, Options)),
    ?_assertEqual(<<"[]">>, render(<<"[{{ items[3] }}]">>, #{items => [1]}, Options))
  ].

missing_empty_keeps_type_errors_test() ->
  ?assertMatch({not_accessible, <<"a.b">>, 1}, reason(dew_tpl:render(<<"{{ a.b }}">>, #{a => 1}, #{missing => empty}))).

missing_empty_in_partials_test() ->
  Options = #{missing => empty, partials => #{p => <<"[{{ nope }}]">>}},
  ?assertEqual(<<"[]">>, render(<<"{{ include \"p\" }}">>, #{}, Options)).

escape_fun_none_test() ->
  ?assertEqual(<<"<b>">>, render(<<"{{ v }}">>, #{v => <<"<b>">>}, #{})),
  ?assertEqual(<<"<b>">>, render(<<"{{ v }}">>, #{v => <<"<b>">>}, #{escape_fun => none})).

escape_fun_html_test_() ->
  Options = #{escape_fun => fun dew_tpl:escape_html/1},
  [
    ?_assertEqual(<<"&lt;b&gt; &amp; &quot;q&quot; &#39;s&#39;">>, render(<<"{{ v }}">>, #{v => <<"<b> & \"q\" 's'">>}, Options)),
    ?_assertEqual(<<"<p>&lt;b&gt;</p>">>, render(<<"<p>{{ v }}</p>">>, #{v => <<"<b>">>}, Options)),
    ?_assertEqual(<<"<b>">>, render(<<"{{ raw(v) }}">>, #{v => <<"<b>">>}, Options)),
    ?_assertEqual(<<"&lt;B&gt;">>, render(<<"{{ raw(v) | upper }}">>, #{v => <<"<b>">>}, Options)),
    ?_assertEqual(<<"&lt;">>, render(<<"{{ \"<\" }}">>, #{}, Options)),
    ?_assertEqual(<<"<">>, render(<<"{{ raw(\"<\") }}">>, #{}, Options)),
    ?_assertEqual(<<"1">>, render(<<"{{ 1 }}">>, #{}, Options))
  ].

escape_fun_custom_test() ->
  Upper = fun(Text) -> string:uppercase(Text) end,
  ?assertEqual(<<"text HELLO">>, render(<<"text {{ v }}">>, #{v => <<"hello">>}, #{escape_fun => Upper})).

escape_fun_iodata_result_test() ->
  Wrap = fun(Text) -> [$[, Text, $]] end,
  ?assertEqual(<<"[a]">>, render(<<"{{ v }}">>, #{v => a}, #{escape_fun => Wrap})).

escape_fun_unicode_chardata_test() ->
  ToChars = fun(Text) -> unicode:characters_to_list(Text) end,
  ?assertEqual(<<"ű"/utf8>>, render(<<"{{ v }}">>, #{v => <<"ű"/utf8>>}, #{escape_fun => ToChars})).

escape_fun_invalid_output_test() ->
  Bad = fun(_) -> [-1] end,
  ?assertEqual(invalid_output, reason(dew_tpl:render(<<"{{ v }}">>, #{v => a}, #{escape_fun => Bad}))).

escape_fun_crash_test() ->
  Crash = fun(_) -> erlang:error(nope) end,
  ?assertMatch(
    {error, #{reason := {function_crashed, escape_fun, error, nope}, line := 1, column := 2}},
    dew_tpl:render(<<"x{{ v }}">>, #{v => a}, #{escape_fun => Crash})
  ).

escape_html_function_test_() ->
  [
    ?_assertEqual(<<"plain">>, dew_tpl:escape_html(<<"plain">>)),
    ?_assertEqual(<<>>, dew_tpl:escape_html(<<>>)),
    ?_assertEqual(<<"&amp;&amp;">>, dew_tpl:escape_html(<<"&&">>)),
    ?_assertEqual(<<"&lt;árvíz&gt;"/utf8>>, dew_tpl:escape_html(<<"<árvíz>"/utf8>>)),
    ?_assertEqual(<<"1">>, dew_tpl:escape_html(1)),
    ?_assertEqual(<<"&lt;a&gt;">>, dew_tpl:escape_html("<a>")),
    ?_assertEqual(<<"atom">>, dew_tpl:escape_html(atom)),
    ?_assertError(badarg, dew_tpl:escape_html({tuple}))
  ].

functions_test_() ->
  Functions = #{
    double => fun(X) -> X * 2 end,
    <<"concat">> => fun(A, B) -> <<A/binary, B/binary>> end,
    now => fun() -> <<"now">> end
  },
  Options = #{functions => Functions},
  [
    ?_assertEqual(<<"4">>, render(<<"{{ double(2) }}">>, #{}, Options)),
    ?_assertEqual(<<"4">>, render(<<"{{ n | double }}">>, #{n => 2}, Options)),
    ?_assertEqual(<<"8">>, render(<<"{{ n | double | double }}">>, #{n => 2}, Options)),
    ?_assertEqual(<<"ab">>, render(<<"{{ concat(\"a\", \"b\") }}">>, #{}, Options)),
    ?_assertEqual(<<"ab">>, render(<<"{{ \"a\" | concat(\"b\") }}">>, #{}, Options)),
    ?_assertEqual(<<"now">>, render(<<"{{ now() }}">>, #{}, Options)),
    ?_assertEqual(<<"yes">>, render(<<"{{ if double(n) > 3 }}yes{{ end }}">>, #{n => 2}, Options))
  ].

functions_override_builtin_test() ->
  Options = #{functions => #{upper => fun(_) -> <<"overridden">> end}},
  ?assertEqual(<<"overridden">>, render(<<"{{ x | upper }}">>, #{x => a}, Options)).

functions_override_special_test() ->
  Options = #{functions => #{default => fun(A, B) -> [A, B] end}},
  ?assertEqual(<<"ab">>, render(<<"{{ default(\"a\", \"b\") }}">>, #{}, Options)).

function_returning_error_test() ->
  Options = #{functions => #{check => fun(_) -> {error, invalid} end}},
  ?assertMatch(
    {error, #{reason := {function_error, <<"check">>, invalid}, line := 1, column := 4}},
    dew_tpl:render(<<"{{ check(1) }}">>, #{}, Options)
  ).

function_crash_test() ->
  Options = #{functions => #{boom => fun(X) -> erlang:error({bad, X}) end}},
  ?assertMatch(
    {error, #{reason := {function_crashed, <<"boom">>, error, {bad, 1}}, line := 1, column := 8}},
    dew_tpl:render(<<"{{ 1 | boom }}">>, #{}, Options)
  ).

function_throw_and_exit_test() ->
  Options = #{functions => #{t => fun(_) -> throw(oops) end, e => fun(_) -> exit(bye) end}},
  ?assertMatch({function_crashed, <<"t">>, throw, oops}, reason(dew_tpl:render(<<"{{ t(1) }}">>, #{}, Options))),
  ?assertMatch({function_crashed, <<"e">>, exit, bye}, reason(dew_tpl:render(<<"{{ e(1) }}">>, #{}, Options))).

function_arity_test() ->
  Options = #{functions => #{f => fun(A, B) -> {A, B} end}},
  ?assertMatch(
    {error, #{phase := compile, reason := {bad_arity, <<"f">>, 2, 1}, line := 1, column := 4}},
    dew_tpl:compile(<<"{{ f(1) }}">>, Options)
  ),
  ?assertMatch({bad_arity, <<"f">>, 2, 3}, reason(dew_tpl:compile(<<"{{ 1 | f(2, 3) }}">>, Options))).

name_option_test_() ->
  [
    ?_assertMatch({error, #{template := <<"page.tpl">>}}, dew_tpl:compile(<<"{{ ">>, #{name => <<"page.tpl">>})),
    ?_assertMatch({error, #{template := <<"page.tpl">>}}, dew_tpl:compile(<<"{{ ">>, #{name => "page.tpl"})),
    ?_assertMatch({error, #{template := <<"page">>}}, dew_tpl:compile(<<"{{ ">>, #{name => page})),
    ?_assertMatch({error, #{template := <<"page">>}}, dew_tpl:render(<<"{{ x }}">>, #{}, #{name => page}))
  ].

name_kept_by_compiled_template_test() ->
  {ok, Template} = dew_tpl:compile(<<"{{ x }}">>, #{name => <<"t">>}),
  ?assertMatch({error, #{template := <<"t">>}}, dew_tpl:render(Template, #{})).

partials_keys_test_() ->
  Partials = #{<<"bin">> => <<"b">>, atom => <<"a">>, "list" => <<"l">>, <<"tpl">> => element(2, dew_tpl:compile(<<"t">>))},
  Options = #{partials => Partials},
  [
    ?_assertEqual(<<"b">>, render(<<"{{ include \"bin\" }}">>, #{}, Options)),
    ?_assertEqual(<<"a">>, render(<<"{{ include \"atom\" }}">>, #{}, Options)),
    ?_assertEqual(<<"l">>, render(<<"{{ include \"list\" }}">>, #{}, Options)),
    ?_assertEqual(<<"t">>, render(<<"{{ include \"tpl\" }}">>, #{}, Options)),
    ?_assertEqual(<<"c">>, render(<<"{{ include \"chars\" }}">>, #{}, #{partials => #{chars => "c"}}))
  ].

partials_use_parent_compile_options_test() ->
  Options = #{keys => binary, escape_fun => fun dew_tpl:escape_html/1, partials => #{p => <<"{{ v }}">>}},
  {ok, Template} = dew_tpl:compile(<<"{{ include \"p\" }}">>, Options),
  ?assertEqual({ok, <<"&lt;">>}, dew_tpl:render(Template, #{<<"v">> => <<"<">>}, Options)).

max_include_depth_test() ->
  Partials = #{p => <<"x{{ include \"p\" }}">>},
  {error, Error} = dew_tpl:render(<<"{{ include \"p\" }}">>, #{}, #{partials => Partials, max_include_depth => 3}),
  ?assertMatch(#{reason := include_depth_exceeded, include_stack := [<<"p">>, <<"p">>, <<"p">>]}, Error).

max_include_depth_zero_test() ->
  ?assertEqual(
    include_depth_exceeded,
    reason(dew_tpl:render(<<"{{ include \"p\" }}">>, #{}, #{partials => #{p => <<>>}, max_include_depth => 0}))
  ).

max_include_depth_allows_limit_test() ->
  Partials = #{a => <<"a{{ include \"b\" }}">>, b => <<"b">>},
  ?assertEqual(<<"ab">>, render(<<"{{ include \"a\" }}">>, #{}, #{partials => Partials, max_include_depth => 2})).

invalid_options_test_() ->
  Invalid = fun(Options) ->
    {error, #{phase := compile, reason := Reason}} = dew_tpl:compile(<<>>, Options),
    Reason
  end,
  F = fun() -> ok end,
  [
    ?_assertEqual({invalid_option, options, [a]}, Invalid([a])),
    ?_assertEqual({invalid_option, unknown, 1}, Invalid(#{unknown => 1})),
    ?_assertEqual({invalid_option, name, 1}, Invalid(#{name => 1})),
    ?_assertEqual({invalid_option, name, [-1]}, Invalid(#{name => [-1]})),
    ?_assertEqual({invalid_option, keys, other}, Invalid(#{keys => other})),
    ?_assertEqual({invalid_option, keys, F}, Invalid(#{keys => F})),
    ?_assertEqual({invalid_option, functions, []}, Invalid(#{functions => []})),
    ?_assertEqual({invalid_option, {functions, f}, 1}, Invalid(#{functions => #{f => 1}})),
    ?_assertEqual({invalid_option, {functions, "f"}, F}, Invalid(#{functions => #{"f" => F}})),
    ?_assertEqual({invalid_option, escape_fun, F}, Invalid(#{escape_fun => F})),
    ?_assertEqual({invalid_option, missing, ignore}, Invalid(#{missing => ignore})),
    ?_assertEqual({invalid_option, partials, []}, Invalid(#{partials => []})),
    ?_assertEqual({invalid_option, {partials, p}, 1}, Invalid(#{partials => #{p => 1}})),
    ?_assertEqual({invalid_option, output, list}, Invalid(#{output => list})),
    ?_assertEqual({invalid_option, max_include_depth, -1}, Invalid(#{max_include_depth => -1})),
    ?_assertEqual({invalid_option, max_include_depth, infinity}, Invalid(#{max_include_depth => infinity}))
  ].

invalid_render_options_test() ->
  {ok, Template} = dew_tpl:compile(<<>>),
  ?assertMatch(
    {error, #{phase := render, reason := {invalid_option, missing, nope}}},
    dew_tpl:render(Template, #{}, #{missing => nope})
  ).

shared_options_map_test() ->
  Options = #{name => <<"t">>, keys => binary, missing => empty, output => iodata},
  {ok, Template} = dew_tpl:compile(<<"{{ a }}{{ b }}">>, Options),
  {ok, IoData} = dew_tpl:render(Template, #{<<"a">> => 1}, Options),
  ?assertEqual(<<"1">>, iolist_to_binary(IoData)).
