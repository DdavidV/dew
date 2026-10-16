-module(dew_tpl_render_tests).

-include_lib("eunit/include/eunit.hrl").

render(Source, Data) ->
  render(Source, Data, #{}).

render(Source, Data, Options) ->
  {ok, Binary} = dew_tpl:render(Source, Data, Options),
  Binary.

value_rendering_test_() ->
  Render = fun(Value) -> render(<<"{{ v }}">>, #{v => Value}) end,
  [
    ?_assertEqual(<<"bin">>, Render(<<"bin">>)),
    ?_assertEqual(<<"chars">>, Render("chars")),
    ?_assertEqual(<<"ab">>, Render([<<"a">>, "b"])),
    ?_assertEqual(<<"ű"/utf8>>, Render([369])),
    ?_assertEqual(<<"42">>, Render(42)),
    ?_assertEqual(<<"-42">>, Render(-42)),
    ?_assertEqual(<<"1.5">>, Render(1.5)),
    ?_assertEqual(<<"0.1">>, Render(0.1)),
    ?_assertEqual(<<"1.0e20">>, Render(1.0e20)),
    ?_assertEqual(<<"atom">>, Render(atom)),
    ?_assertEqual(<<"true">>, Render(true)),
    ?_assertEqual(<<"false">>, Render(false)),
    ?_assertEqual(<<>>, Render(undefined)),
    ?_assertEqual(<<>>, Render(nil)),
    ?_assertEqual(<<>>, Render(null)),
    ?_assertEqual(<<>>, Render([])),
    ?_assertEqual(<<>>, Render(<<>>))
  ].

unrenderable_values_test_() ->
  Reason = fun(Value) ->
    {error, #{reason := R}} = dew_tpl:render(<<"{{ v }}">>, #{v => Value}),
    R
  end,
  [
    ?_assertEqual({unrenderable_value, #{a => 1}}, Reason(#{a => 1})),
    ?_assertEqual({unrenderable_value, {a, b}}, Reason({a, b})),
    ?_assertEqual({unrenderable_value, [a]}, Reason([a])),
    ?_assertMatch({unrenderable_value, _}, Reason(self())),
    ?_assertMatch({unrenderable_value, _}, Reason(fun() -> ok end))
  ].

if_test_() ->
  Source = <<"{{ if a }}A{{ else if b }}B{{ else if c }}C{{ else }}D{{ end }}">>,
  [
    ?_assertEqual(<<"A">>, render(Source, #{a => true, b => true, c => true})),
    ?_assertEqual(<<"B">>, render(Source, #{a => false, b => true, c => true})),
    ?_assertEqual(<<"C">>, render(Source, #{a => false, b => false, c => true})),
    ?_assertEqual(<<"D">>, render(Source, #{a => false, b => false, c => false})),
    ?_assertEqual(<<"x">>, render(<<"{{ if a }}x{{ end }}">>, #{a => 1})),
    ?_assertEqual(<<>>, render(<<"{{ if a }}x{{ end }}">>, #{a => 0 == 1})),
    ?_assertEqual(<<"y">>, render(<<"{{ if a }}x{{ else }}y{{ end }}">>, #{a => []}))
  ].

if_is_lazy_test() ->
  ?assertEqual(<<"ok">>, render(<<"{{ if true }}ok{{ else }}{{ missing }}{{ end }}">>, #{})),
  ?assertEqual(<<"ok">>, render(<<"{{ if a }}{{ missing }}{{ else }}ok{{ end }}">>, #{a => false})).

if_literal_folding_test_() ->
  [
    ?_assertEqual(<<"t">>, render(<<"{{ if true }}t{{ else }}f{{ end }}">>, #{})),
    ?_assertEqual(<<"f">>, render(<<"{{ if false }}t{{ else }}f{{ end }}">>, #{})),
    ?_assertEqual(<<"b">>, render(<<"{{ if false }}a{{ else if true }}b{{ else }}c{{ end }}">>, #{})),
    ?_assertEqual(<<"c">>, render(<<"{{ if false }}a{{ else if nil }}b{{ else }}c{{ end }}">>, #{})),
    ?_assertEqual(<<"b">>, render(<<"{{ if x }}a{{ else if 1 }}b{{ else }}c{{ end }}">>, #{x => false})),
    ?_assertEqual(<<"a">>, render(<<"{{ if x }}a{{ else if \"y\" }}b{{ else }}c{{ end }}">>, #{x => true})),
    ?_assertEqual(<<>>, render(<<"{{ if false }}a{{ end }}">>, #{}))
  ].

nested_if_test() ->
  Source = <<"{{ if a }}{{ if b }}ab{{ else }}a{{ end }}{{ else }}{{ if b }}b{{ else }}-{{ end }}{{ end }}">>,
  ?assertEqual(<<"ab">>, render(Source, #{a => true, b => true})),
  ?assertEqual(<<"a">>, render(Source, #{a => true, b => false})),
  ?assertEqual(<<"b">>, render(Source, #{a => false, b => true})),
  ?assertEqual(<<"-">>, render(Source, #{a => false, b => false})).

for_list_test_() ->
  [
    ?_assertEqual(<<"abc">>, render(<<"{{ for x in xs }}{{ x }}{{ end }}">>, #{xs => [a, b, c]})),
    ?_assertEqual(<<"0a1b">>, render(<<"{{ for i, x in xs }}{{ i }}{{ x }}{{ end }}">>, #{xs => [a, b]})),
    ?_assertEqual(<<"12">>, render(<<"{{ for u in users }}{{ u.id }}{{ end }}">>, #{users => [#{id => 1}, #{id => 2}]})),
    ?_assertEqual(<<"name">>, render(<<"{{ for p in props }}{{ p[0] }}{{ end }}">>, #{props => [{name, 1}]}))
  ].

for_map_test_() ->
  Map = #{c => 3, a => 1, b => 2},
  [
    ?_assertEqual(<<"a=1,b=2,c=3,">>, render(<<"{{ for k, v in m }}{{ k }}={{ v }},{{ end }}">>, #{m => Map})),
    ?_assertEqual(<<"123">>, render(<<"{{ for v in m }}{{ v }}{{ end }}">>, #{m => Map}))
  ].

for_else_test_() ->
  Source = <<"{{ for x in xs }}{{ x }}{{ else }}empty{{ end }}">>,
  [
    ?_assertEqual(<<"empty">>, render(Source, #{xs => []})),
    ?_assertEqual(<<"empty">>, render(Source, #{xs => #{}})),
    ?_assertEqual(<<"empty">>, render(Source, #{xs => undefined})),
    ?_assertEqual(<<"empty">>, render(Source, #{xs => nil})),
    ?_assertEqual(<<"empty">>, render(Source, #{xs => null})),
    ?_assertEqual(<<"1">>, render(Source, #{xs => [1]}))
  ].

for_not_iterable_test_() ->
  Reason = fun(Value) ->
    {error, #{reason := R, line := 1, column := 1}} = dew_tpl:render(<<"{{ for x in xs }}{{ end }}">>, #{xs => Value}),
    R
  end,
  [
    ?_assertEqual({not_iterable, <<"abc">>}, Reason(<<"abc">>)),
    ?_assertEqual({not_iterable, 1}, Reason(1)),
    ?_assertEqual({not_iterable, {a}}, Reason({a})),
    ?_assertEqual({not_iterable, true}, Reason(true))
  ].

loop_fields_test_() ->
  Data = #{xs => [a, b, c]},
  Loop = fun(Field) ->
    render(<<"{{ for x in xs }}{{ loop.", Field/binary, " }},{{ end }}">>, Data)
  end,
  [
    ?_assertEqual(<<"1,2,3,">>, Loop(<<"index">>)),
    ?_assertEqual(<<"0,1,2,">>, Loop(<<"index0">>)),
    ?_assertEqual(<<"true,false,false,">>, Loop(<<"first">>)),
    ?_assertEqual(<<"false,false,true,">>, Loop(<<"last">>)),
    ?_assertEqual(<<"3,3,3,">>, Loop(<<"length">>))
  ].

loop_fields_in_map_test() ->
  ?assertEqual(
    <<"1/2 2/2 ">>,
    render(<<"{{ for k, v in m }}{{ loop.index }}/{{ loop.length }} {{ end }}">>, #{m => #{a => 1, b => 2}})
  ).

loop_separator_test() ->
  ?assertEqual(
    <<"a, b, c">>,
    render(<<"{{ for x in xs }}{{ x }}{{ if not loop.last }}, {{ end }}{{ end }}">>, #{xs => [a, b, c]})
  ).

nested_loops_test() ->
  Source = <<"{{ for row in rows }}{{ loop.index }}:{{ for c in row }}{{ loop.index }}{{ c }}{{ end }};{{ end }}">>,
  ?assertEqual(<<"1:1a2b;2:1c;">>, render(Source, #{rows => [[a, b], [c]]})).

outer_loop_in_inner_else_test() ->
  Source = <<"{{ for r in rows }}{{ for c in r }}{{ c }}{{ else }}empty{{ loop.index }}{{ end }}{{ end }}">>,
  ?assertEqual(<<"empty1xempty3">>, render(Source, #{rows => [[], [x], []]})).

loop_variable_named_loop_test() ->
  ?assertEqual(<<"ab">>, render(<<"{{ for loop in xs }}{{ loop }}{{ end }}">>, #{xs => [a, b]})).

loop_variable_shadows_data_test() ->
  ?assertEqual(<<"12-top">>, render(<<"{{ for x in xs }}{{ x }}{{ end }}-{{ x }}">>, #{xs => [1, 2], x => top})).

loop_outside_for_is_data_test() ->
  ?assertEqual(<<"data">>, render(<<"{{ loop.index }}">>, #{loop => #{index => data}})).

loop_variables_in_nested_blocks_test() ->
  Source = <<"{{ for x in xs }}{{ if x > 1 }}{{ case x }}{{ when 2 }}two{{ else }}{{ x }}{{ end }}{{ end }}{{ end }}">>,
  ?assertEqual(<<"two3">>, render(Source, #{xs => [1, 2, 3]})).

large_loop_test() ->
  Items = lists:seq(1, 10000),
  Binary = render(<<"{{ for i in items }}{{ i }},{{ end }}">>, #{items => Items}),
  ?assertEqual(iolist_to_binary([[integer_to_binary(I), ","] || I <- Items]), Binary).

case_test_() ->
  Source = <<"{{ case role }}{{ when \"dev\", \"ops\" }}eng{{ when \"pm\" }}mgr{{ else }}other{{ end }}">>,
  [
    ?_assertEqual(<<"eng">>, render(Source, #{role => dev})),
    ?_assertEqual(<<"eng">>, render(Source, #{role => <<"ops">>})),
    ?_assertEqual(<<"mgr">>, render(Source, #{role => "pm"})),
    ?_assertEqual(<<"other">>, render(Source, #{role => ceo})),
    ?_assertEqual(<<"other">>, render(Source, #{role => undefined}))
  ].

case_without_else_test_() ->
  Source = <<"{{ case n }}{{ when 1 }}one{{ when 2.0 }}two{{ end }}">>,
  [
    ?_assertEqual(<<"one">>, render(Source, #{n => 1})),
    ?_assertEqual(<<"two">>, render(Source, #{n => 2})),
    ?_assertEqual(<<>>, render(Source, #{n => 3}))
  ].

case_with_only_else_test() ->
  ?assertEqual(<<"e">>, render(<<"{{ case n }}{{ else }}e{{ end }}">>, #{n => 1})),
  ?assertEqual(<<>>, render(<<"{{ case n }}{{ end }}">>, #{n => 1})).

case_multiline_test() ->
  Source = <<"{{ case x }}\n  {{ when true }}\nyes\n  {{ when false }}\nno\n{{ end }}\n">>,
  ?assertEqual(<<"yes\n">>, render(Source, #{x => true})),
  ?assertEqual(<<"no\n">>, render(Source, #{x => false})).

case_values_are_expressions_test() ->
  Source = <<"{{ case x }}{{ when y, z | upper }}match{{ else }}no{{ end }}">>,
  ?assertEqual(<<"match">>, render(Source, #{x => <<"Z">>, y => <<"a">>, z => <<"z">>})),
  ?assertEqual(<<"no">>, render(Source, #{x => <<"q">>, y => <<"a">>, z => <<"z">>})).

case_stops_at_first_match_test() ->
  ?assertEqual(<<"first">>, render(<<"{{ case 1 }}{{ when 1 }}first{{ when 1 }}second{{ end }}">>, #{})).

case_when_values_are_lazy_test() ->
  ?assertEqual(<<"a">>, render(<<"{{ case x }}{{ when 1 }}a{{ when missing }}b{{ end }}">>, #{x => 1})).

include_test_() ->
  Partials = #{
    <<"header">> => <<"<h1>{{ title }}</h1>">>,
    row => <<"[{{ name }}]">>,
    "nested" => <<"({{ include \"row\" }})">>
  },
  Options = #{partials => Partials},
  [
    ?_assertEqual(<<"<h1>T</h1>">>, render(<<"{{ include \"header\" }}">>, #{title => <<"T">>}, Options)),
    ?_assertEqual(<<"[a][b]">>, render(<<"{{ for u in users }}{{ include \"row\" u }}{{ end }}">>, #{users => [#{name => a}, #{name => b}]}, Options)),
    ?_assertEqual(<<"([x])">>, render(<<"{{ include \"nested\" }}">>, #{name => x}, Options)),
    ?_assertEqual(<<"([y])">>, render(<<"{{ include \"nested\" item }}">>, #{item => #{name => y}}, Options))
  ].

include_compiled_partials_test() ->
  {ok, Row} = dew_tpl:compile(<<"<{{ v }}>">>),
  ?assertEqual(<<"<1><2>">>, render(<<"{{ for x in xs }}{{ include \"row\" x }}{{ end }}">>, #{xs => [#{v => 1}, #{v => 2}]}, #{partials => #{row => Row}})).

include_does_not_see_loop_variables_test() ->
  Options = #{partials => #{p => <<"{{ x }}">>}},
  ?assertEqual(<<"topi">>, render(<<"{{ for x in xs }}{{ include \"p\" }}{{ x }}{{ end }}">>, #{x => top, xs => [i]}, Options)).

include_with_literal_test() ->
  ?assertEqual(<<"5">>, render(<<"{{ include \"p\" 5 }}">>, #{}, #{partials => #{p => <<"{{ length(\"abcde\") }}">>}})).

recursive_include_test() ->
  Tree = #{name => root, children => [#{name => a, children => [#{name => a1, children => []}]}, #{name => b, children => []}]},
  Partials = #{node => <<"{{ name }}{{ if children }}({{ for c in children }}{{ include \"node\" c }}{{ end }}){{ end }}">>},
  ?assertEqual(<<"root(a(a1)b)">>, render(<<"{{ include \"node\" }}">>, Tree, #{partials => Partials})).

output_iodata_test() ->
  {ok, IoData} = dew_tpl:render(<<"a{{ x }}b{{ for i in xs }}{{ i }}{{ end }}">>, #{x => 1, xs => [2, 3]}, #{output => iodata}),
  ?assertEqual(<<"a1b23">>, iolist_to_binary(IoData)).

compiled_template_reuse_test() ->
  {ok, Template} = dew_tpl:compile(<<"Hello {{ name }}">>),
  ?assertEqual({ok, <<"Hello a">>}, dew_tpl:render(Template, #{name => a})),
  ?assertEqual({ok, <<"Hello b">>}, dew_tpl:render(Template, #{name => b})).

proplist_data_test() ->
  ?assertEqual(<<"bob 1">>, render(<<"{{ name }} {{ n }}">>, [{name, bob}, {n, 1}])).

nested_data_types_test() ->
  Data = #{user => [{profile, #{tags => {red, green}}}]},
  ?assertEqual(<<"green">>, render(<<"{{ user.profile.tags[1] }}">>, Data)).

mixed_template_test() ->
  Source = <<
    "Dear {{ user.name | upper }},\n"
    "{{ if user.orders }}\n"
    "Your orders:\n"
    "{{ for o in user.orders }}\n"
    "  {{ loop.index }}. {{ o.item }} x{{ o.qty }}{{ if o.qty > 1 }} (bulk){{ end }}\n"
    "{{ end }}\n"
    "{{ else }}\n"
    "No orders.\n"
    "{{ end }}\n"
    "{{ case user.tier }}\n"
    "{{ when \"gold\" }}\n"
    "Thanks for being gold!\n"
    "{{ end }}\n"
  >>,
  Data = #{user => #{name => <<"ann">>, tier => gold, orders => [#{item => pen, qty => 1}, #{item => ink, qty => 3}]}},
  ?assertEqual(
    <<"Dear ANN,\nYour orders:\n  1. pen x1\n  2. ink x3 (bulk)\nThanks for being gold!\n">>,
    render(Source, Data)
  ).
