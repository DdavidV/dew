-module(dew_tpl_error_tests).

-include_lib("eunit/include/eunit.hrl").

compile_error(Source) ->
  {error, Error} = dew_tpl:compile(Source),
  Error.

render_error(Source, Data) ->
  render_error(Source, Data, #{}).

render_error(Source, Data, Options) ->
  {error, Error} = dew_tpl:render(Source, Data, Options),
  Error.

%% Asserts phase, reason, line and column of a compile error.
-define(assertCompileError(Reason, Line, Column, Source),
  ?assertMatch(
    #{phase := compile, reason := Reason, line := Line, column := Column},
    compile_error(Source)
  )
).

-define(assertRenderError(Reason, Line, Column, Source, Data),
  ?assertMatch(
    #{phase := render, reason := Reason, line := Line, column := Column},
    render_error(Source, Data)
  )
).

%%% Compile errors

unclosed_tag_test() ->
  ?assertCompileError(unclosed_tag, 2, 3, <<"ok\nab{{ x ">>).

unclosed_comment_test() ->
  ?assertCompileError(unclosed_comment, 1, 2, <<"a{{# never closed">>).

unexpected_character_test() ->
  ?assertCompileError({unexpected_character, <<"$">>}, 1, 6, <<"{{ a $ }}">>).

unterminated_string_test() ->
  ?assertCompileError(unterminated_string, 1, 9, <<"{{ a == \"open }}">>).

unexpected_token_test_() ->
  [
    ?_test(?assertCompileError({unexpected_token, <<"b">>}, 1, 6, <<"{{ a b }}">>)),
    ?_test(?assertCompileError({unexpected_token, <<")">>}, 1, 7, <<"{{ (a)) }}">>)),
    ?_test(?assertCompileError({unexpected_token, <<"==">>}, 1, 11, <<"{{ a == b == c }}">>)),
    ?_test(?assertCompileError({unexpected_token, <<",">>}, 1, 4, <<"{{ , }}">>)),
    ?_test(?assertCompileError({unexpected_token, <<"x">>}, 1, 9, <<"{{ else x }}">>)),
    ?_test(?assertCompileError({unexpected_token, <<"5">>}, 1, 12, <<"{{ include 5 }}">>)),
    ?_test(?assertCompileError({unexpected_token, <<"5">>}, 1, 8, <<"{{ a | 5 }}">>)),
    ?_test(?assertCompileError({unexpected_token, <<"of">>}, 1, 10, <<"{{ for x of items }}{{ end }}">>)),
    ?_test(?assertCompileError({unexpected_token, <<"\"x\"">>}, 1, 8, <<"{{ for \"x\" in xs }}{{ end }}">>)),
    ?_test(?assertCompileError({unexpected_token, <<"1">>}, 1, 11, <<"{{ for a, 1 in xs }}{{ end }}">>)),
    ?_test(?assertCompileError({unexpected_token, <<"of">>}, 1, 13, <<"{{ for a, b of xs }}{{ end }}">>)),
    ?_test(?assertCompileError({unexpected_token, <<"b">>}, 1, 6, <<"{{ a[b] }}">>)),
    ?_test(?assertCompileError({unexpected_token, <<"2">>}, 1, 8, <<"{{ a[1 2] }}">>)),
    ?_test(?assertCompileError({unexpected_token, <<"1">>}, 1, 6, <<"{{ a.1 }}">>)),
    ?_test(?assertCompileError({unexpected_token, <<"b">>}, 1, 8, <<"{{ f(a b) }}">>)),
    ?_test(?assertCompileError({unexpected_token, <<"0.5">>}, 1, 6, <<"{{ a 0.5 }}">>))
  ].

unexpected_end_of_expression_test_() ->
  [
    ?_test(?assertCompileError(unexpected_end_of_expression, 1, 9, <<"{{ a == }}">>)),
    ?_test(?assertCompileError(unexpected_end_of_expression, 1, 10, <<"{{ a and }}">>)),
    ?_test(?assertCompileError(unexpected_end_of_expression, 1, 7, <<"{{ if }}{{ end }}">>)),
    ?_test(?assertCompileError(unexpected_end_of_expression, 1, 8, <<"{{ for }}">>)),
    ?_test(?assertCompileError(unexpected_end_of_expression, 1, 12, <<"{{ include }}">>)),
    ?_test(?assertCompileError(unexpected_end_of_expression, 1, 8, <<"{{ a | }}">>)),
    ?_test(?assertCompileError(unexpected_end_of_expression, 1, 9, <<"{{ f(a, }}">>)),
    ?_test(?assertCompileError(unexpected_end_of_expression, 1, 7, <<"{{ (a }}">>)),
    ?_test(?assertCompileError(unexpected_end_of_expression, 1, 7, <<"{{ a. }}">>)),
    ?_test(?assertCompileError(unexpected_end_of_expression, 1, 12, <<"{{ when 1, }}">>))
  ].

empty_tag_test() ->
  ?assertCompileError(empty_tag, 1, 4, <<"{{ }}">>),
  ?assertCompileError(empty_tag, 1, 3, <<"{{}}">>).

unclosed_block_test_() ->
  [
    ?_test(?assertCompileError({unclosed_block, 'if'}, 1, 1, <<"{{ if a }}x">>)),
    ?_test(?assertCompileError({unclosed_block, 'if'}, 2, 1, <<"x\n{{ if a }}{{ else }}y">>)),
    ?_test(?assertCompileError({unclosed_block, for}, 1, 3, <<"ab{{ for x in xs }}">>)),
    ?_test(?assertCompileError({unclosed_block, for}, 1, 1, <<"{{ for x in xs }}{{ else }}">>)),
    ?_test(?assertCompileError({unclosed_block, 'case'}, 1, 1, <<"{{ case x }}">>)),
    ?_test(?assertCompileError({unclosed_block, 'case'}, 1, 1, <<"{{ case x }}{{ when 1 }}">>)),
    ?_test(?assertCompileError({unclosed_block, 'case'}, 1, 1, <<"{{ case x }}{{ else }}">>)),
    ?_test(?assertCompileError({unclosed_block, for}, 1, 1, <<"{{ for x in xs }}{{ if x }}{{ end }}">>))
  ].

unexpected_tag_test_() ->
  [
    ?_test(?assertCompileError({unexpected_tag, 'end'}, 1, 2, <<"x{{ end }}">>)),
    ?_test(?assertCompileError({unexpected_tag, 'else'}, 1, 1, <<"{{ else }}">>)),
    ?_test(?assertCompileError({unexpected_tag, 'else if'}, 1, 1, <<"{{ else if a }}">>)),
    ?_test(?assertCompileError({unexpected_tag, 'when'}, 1, 1, <<"{{ when 1 }}">>)),
    ?_test(?assertCompileError({unexpected_tag, 'else'}, 1, 21, <<"{{ if a }}{{ else }}{{ else }}{{ end }}">>)),
    ?_test(?assertCompileError({unexpected_tag, 'else if'}, 1, 21, <<"{{ if a }}{{ else }}{{ else if b }}{{ end }}">>)),
    ?_test(?assertCompileError({unexpected_tag, 'when'}, 1, 11, <<"{{ if a }}{{ when 1 }}{{ end }}">>)),
    ?_test(?assertCompileError({unexpected_tag, 'else if'}, 1, 18, <<"{{ for x in xs }}{{ else if a }}{{ end }}">>)),
    ?_test(?assertCompileError({unexpected_tag, 'when'}, 1, 23, <<"{{ case a }}{{ else }}{{ when 1 }}{{ end }}">>)),
    ?_test(?assertCompileError({unexpected_tag, 'end'}, 1, 20, <<"{{ if a }}{{ end }}{{ end }}">>))
  ].

reserved_word_test_() ->
  [
    ?_test(?assertCompileError({reserved_word, in}, 1, 4, <<"{{ in }}">>)),
    ?_test(?assertCompileError({reserved_word, 'end'}, 1, 7, <<"{{ if end }}">>)),
    ?_test(?assertCompileError({reserved_word, 'case'}, 1, 9, <<"{{ a == case }}">>)),
    ?_test(?assertCompileError({reserved_word, 'or'}, 1, 4, <<"{{ or }}">>)),
    ?_test(?assertCompileError({reserved_word, 'if'}, 1, 13, <<"{{ for x in if }}{{ end }}">>))
  ].

unknown_function_test_() ->
  [
    ?_test(?assertCompileError({unknown_function, <<"uper">>}, 3, 11, <<"\n\n{{ name | uper }}">>)),
    ?_test(?assertCompileError({unknown_function, <<"nope">>}, 1, 4, <<"{{ nope() }}">>)),
    ?_test(?assertCompileError({unknown_function, <<"x">>}, 1, 23, <<"{{ if a }}{{ end }}{{ x(1) }}">>))
  ].

bad_arity_test() ->
  ?assertCompileError({bad_arity, <<"upper">>, 1, 2}, 1, 4, <<"{{ upper(1, 2) }}">>).

unknown_loop_field_test_() ->
  [
    ?_test(?assertCompileError({unknown_loop_field, <<"idx">>}, 1, 21, <<"{{ for x in xs }}{{ loop.idx }}{{ end }}">>)),
    ?_test(?assertCompileError({unknown_loop_field, <<>>}, 1, 21, <<"{{ for x in xs }}{{ loop }}{{ end }}">>)),
    ?_test(?assertCompileError({unknown_loop_field, <<>>}, 1, 21, <<"{{ for x in xs }}{{ loop[0] }}{{ end }}">>))
  ].

content_before_when_test_() ->
  [
    ?_test(?assertCompileError(content_before_when, 1, 13, <<"{{ case x }}text{{ when 1 }}{{ end }}">>)),
    ?_test(?assertCompileError(content_before_when, 2, 1, <<"{{ case x }}\n{{ y }}{{ when 1 }}{{ end }}">>)),
    ?_test(?assertCompileError(content_before_when, 1, 1, <<"{{ case x }}{{ if y }}{{ end }}{{ when 1 }}{{ end }}">>)),
    ?_test(?assertCompileError(content_before_when, 1, 13, <<"{{ case x }}{{ for y in z }}{{ end }}{{ end }}">>))
  ].

whitespace_before_when_is_allowed_test() ->
  ?assertMatch({ok, _}, dew_tpl:compile(<<"{{ case x }} \n\t\r\n {{ when 1 }}{{ end }}">>)),
  ?assertMatch({ok, _}, dew_tpl:compile(<<"{{ case x }}{{# comment #}}{{ when 1 }}{{ end }}">>)).

invalid_source_test_() ->
  [
    ?_assertMatch({error, #{phase := compile, reason := {invalid_source, 123}}}, dew_tpl:compile(123)),
    ?_assertMatch({error, #{phase := compile, reason := {invalid_source, [-1]}}}, dew_tpl:compile([-1])),
    ?_assertMatch({error, #{phase := compile, reason := {invalid_source, _}}}, dew_tpl:render([foo], #{}))
  ].

invalid_template_test() ->
  ?assertMatch({error, #{phase := render, reason := {invalid_template, {x}}}}, dew_tpl:render({x}, #{})).

compile_error_snippet_test() ->
  ?assertMatch(#{snippet := <<"  {{ a b }}">>}, compile_error(<<"first\n  {{ a b }}\nlast">>)),
  ?assertMatch(#{snippet := <<"{{ a b }}">>}, compile_error(<<"{{ a b }}\r\nnext">>)).

compile_error_without_position_has_no_snippet_test() ->
  {error, Error} = dew_tpl:compile(<<>>, #{bad => option}),
  ?assertNot(maps:is_key(snippet, Error)),
  ?assertNot(maps:is_key(line, Error)).

render_of_invalid_source_returns_compile_error_test() ->
  ?assertMatch({error, #{phase := compile, reason := unclosed_tag}}, dew_tpl:render(<<"{{">>, #{})).

%%% compile_file

file_fixture_test_() ->
  {setup,
    fun() ->
      Dir = filename:join([os:getenv("TMPDIR", "/tmp"), "dew_tpl_error_tests_" ++ os:getpid()]),
      ok = filelib:ensure_dir(filename:join(Dir, "x")),
      Good = filename:join(Dir, "good.tpl"),
      Bad = filename:join(Dir, "bad.tpl"),
      ok = file:write_file(Good, <<"hi {{ name }}">>),
      ok = file:write_file(Bad, <<"line\n{{ if }}">>),
      {Dir, Good, Bad}
    end,
    fun({Dir, Good, Bad}) ->
      file:delete(Good),
      file:delete(Bad),
      file:del_dir(Dir)
    end,
    fun({Dir, Good, Bad}) ->
      Missing = filename:join(Dir, "missing.tpl"),
      BadName = list_to_binary(Bad),
      [
        ?_assertMatch({ok, _}, dew_tpl:compile_file(Good)),
        ?_assertEqual({ok, <<"hi x">>}, dew_tpl:render(element(2, dew_tpl:compile_file(Good)), #{name => x})),
        ?_assertMatch({ok, _}, dew_tpl:compile_file(list_to_binary(Good))),
        ?_assertMatch(
          {error, #{phase := compile, reason := unexpected_end_of_expression, template := BadName, line := 2, column := 7}},
          dew_tpl:compile_file(Bad)
        ),
        ?_assertMatch({error, #{template := <<"custom">>}}, dew_tpl:compile_file(Bad, #{name => custom})),
        ?_assertMatch({error, #{reason := {file, enoent}}}, dew_tpl:compile_file(Missing)),
        ?_assertMatch({error, #{reason := {file, eisdir}}}, dew_tpl:compile_file(Dir)),
        ?_assertMatch({error, #{reason := {file, badarg}}}, dew_tpl:compile_file({not_a_path})),
        ?_assertMatch({error, #{reason := {invalid_option, a, b}}}, dew_tpl:compile_file(Good, #{a => b}))
      ]
    end
  }.

%%% Render errors

missing_key_test_() ->
  [
    ?_test(?assertRenderError({missing_key, <<"a">>}, 1, 4, <<"{{ a }}">>, #{})),
    ?_test(?assertRenderError({missing_key, <<"a.b.c">>}, 1, 4, <<"{{ a.b.c }}">>, #{a => #{b => #{}}})),
    ?_test(?assertRenderError({missing_key, <<"a[2]">>}, 1, 4, <<"{{ a[2] }}">>, #{a => [1]})),
    ?_test(?assertRenderError({missing_key, <<"a[-1]">>}, 1, 4, <<"{{ a[-1] }}">>, #{a => [1]})),
    ?_test(?assertRenderError({missing_key, <<"a[\"k\"]">>}, 1, 4, <<"{{ a[\"k\"] }}">>, #{a => #{}})),
    ?_test(?assertRenderError({missing_key, <<"t[5]">>}, 1, 4, <<"{{ t[5] }}">>, #{t => {a}})),
    ?_test(?assertRenderError({missing_key, <<"u.name">>}, 1, 4, <<"{{ u.name }}">>, #{u => undefined})),
    ?_test(?assertRenderError({missing_key, <<"x">>}, 2, 7, <<"\n{{ if x }}{{ end }}">>, #{})),
    ?_test(?assertRenderError({missing_key, <<"y">>}, 1, 21, <<"{{ for x in xs }}{{ y }}{{ end }}">>, #{xs => [1]})),
    ?_test(?assertRenderError({missing_key, <<"x.a">>}, 1, 21, <<"{{ for x in xs }}{{ x.a }}{{ end }}">>, #{xs => [#{}]})),
    ?_test(?assertRenderError({missing_key, <<"r">>}, 1, 9, <<"{{ case r }}{{ end }}">>, #{})),
    ?_test(?assertRenderError({missing_key, <<"v">>}, 1, 21, <<"{{ case 1 }}{{ when v }}{{ end }}">>, #{})),
    ?_test(?assertRenderError({missing_key, <<"a">>}, 1, 10, <<"{{ upper(a) }}">>, #{}))
  ].

not_accessible_test_() ->
  [
    ?_test(?assertRenderError({not_accessible, <<"a.b">>, 1}, 1, 4, <<"{{ a.b }}">>, #{a => 1})),
    ?_test(?assertRenderError({not_accessible, <<"a.b">>, <<"str">>}, 1, 4, <<"{{ a.b }}">>, #{a => <<"str">>})),
    ?_test(?assertRenderError({not_accessible, <<"a[0]">>, 7}, 1, 4, <<"{{ a[0] }}">>, #{a => 7})),
    ?_test(?assertRenderError({not_accessible, <<"a.b">>, [x | y]}, 1, 4, <<"{{ a.b }}">>, #{a => [x | y]}))
  ].

not_iterable_test() ->
  ?assertRenderError({not_iterable, 5}, 2, 1, <<"\n{{ for x in n }}{{ end }}">>, #{n => 5}).

unrenderable_value_test() ->
  ?assertRenderError({unrenderable_value, {a, b}}, 1, 3, <<"x {{ v }}">>, #{v => {a, b}}).

type_mismatch_test() ->
  ?assertRenderError({type_mismatch, '<', 1, <<"a">>}, 1, 9, <<"{{ if n < s }}{{ end }}">>, #{n => 1, s => <<"a">>}).

bad_argument_test() ->
  ?assertRenderError({bad_argument, <<"join">>, 5}, 1, 4, <<"{{ join(n, \",\") }}">>, #{n => 5}).

function_error_test() ->
  Options = #{functions => #{f => fun(_) -> {error, nope} end}},
  ?assertMatch(
    #{phase := render, reason := {function_error, <<"f">>, nope}, line := 1, column := 8},
    render_error(<<"{{ x | f }}">>, #{x => 1}, Options)
  ).

function_crashed_test() ->
  Options = #{functions => #{f => fun(X) -> 1 = X end}},
  ?assertMatch(
    #{phase := render, reason := {function_crashed, <<"f">>, error, {badmatch, 2}}, line := 1, column := 4},
    render_error(<<"{{ f(2) }}">>, #{}, Options)
  ).

partial_not_found_test() ->
  ?assertRenderError({partial_not_found, <<"nope">>}, 1, 2, <<"x{{ include \"nope\" }}">>, #{}).

include_depth_exceeded_test() ->
  Error = render_error(<<"{{ include \"p\" }}">>, #{}, #{partials => #{p => <<"{{ include \"p\" }}">>}}),
  ?assertMatch(#{reason := include_depth_exceeded, line := 1, column := 1, template := <<"p">>}, Error),
  ?assertEqual(32, length(maps:get(include_stack, Error))).

bad_data_test_() ->
  [
    ?_assertMatch({error, #{phase := render, reason := {bad_data, 1}}}, dew_tpl:render(<<"x">>, 1)),
    ?_assertMatch({error, #{phase := render, reason := {bad_data, <<"d">>}}}, dew_tpl:render(<<"x">>, <<"d">>)),
    ?_assertMatch({error, #{reason := {bad_data, undefined}, template := <<"t">>}}, dew_tpl:render(<<"x">>, undefined, #{name => t})),
    ?_assertEqual({ok, <<"x">>}, dew_tpl:render(<<"x">>, [])),
    ?_assertEqual({ok, <<"x">>}, dew_tpl:render(<<"x">>, #{}))
  ].

%%% Errors inside partials, using a fixture with precompiled partials

partials_fixture_test_() ->
  {setup,
    fun() ->
      {ok, Inner} = dew_tpl:compile(<<"\n  {{ missing }}">>, #{name => <<"ignored name">>}),
      #{
        partials => #{
          outer => <<"o{{ include \"inner\" }}">>,
          inner => Inner,
          broken => <<"{{ if }}">>,
          includes_broken => <<"{{ include \"broken\" }}">>,
          loop => <<"{{ for x in xs }}{{ include \"inner\" x }}{{ end }}">>
        }
      }
    end,
    fun(Options) ->
      [
        ?_assertMatch(
          #{phase := render, reason := {missing_key, <<"missing">>}, line := 2, column := 6,
            template := <<"inner">>, include_stack := [<<"outer">>, <<"inner">>]},
          render_error(<<"{{ include \"outer\" }}">>, #{}, Options)
        ),
        ?_assertMatch(
          #{phase := compile, reason := unexpected_end_of_expression, line := 1, column := 7,
            template := <<"broken">>, include_stack := [<<"includes_broken">>, <<"broken">>],
            snippet := <<"{{ if }}">>},
          render_error(<<"{{ include \"includes_broken\" }}">>, #{}, Options)
        ),
        ?_assertMatch(
          #{reason := {missing_key, <<"missing">>}, include_stack := [<<"loop">>, <<"inner">>]},
          render_error(<<"{{ include \"loop\" }}">>, #{xs => [#{}]}, Options)
        ),
        ?_assertEqual({ok, <<"fine">>}, dew_tpl:render(<<"fine">>, #{}, Options)),
        ?_assertEqual(
          <<"inner:2:6: missing key 'missing' (included via outer -> inner)">>,
          dew_tpl:format_error(render_error(<<"{{ include \"outer\" }}">>, #{}, Options))
        )
      ]
    end
  }.

%%% format_error

format_error_test_() ->
  Format = fun(Error) -> dew_tpl:format_error(Error) end,
  [
    ?_assertEqual(<<"1:4: missing key 'user.name'">>, Format(render_error(<<"{{ user.name }}">>, #{}))),
    ?_assertEqual(<<"page:1:4: missing key 'x'">>, Format(render_error(<<"{{ x }}">>, #{}, #{name => page}))),
    ?_assertEqual(
      <<"t:2:8: unknown function 'uper'\n    {{ x | uper }}\n           ^">>,
      Format(element(2, dew_tpl:compile(<<"\n{{ x | uper }}">>, #{name => t})))
    ),
    ?_assertEqual(
      <<"1:8: unexpected end of expression\n    \t{{ a. }}\n    \t      ^">>,
      Format(compile_error(<<"\t{{ a. }}">>))
    ),
    ?_assertEqual(
      <<"1:9: missing key 'x'\n    ">>,
      binary:part(Format((render_error(<<"árvíz{{ x }}"/utf8>>, #{}))#{snippet => <<>>}), 0, 25)
    ),
    ?_assertEqual(<<"invalid option unknown => 1">>, Format(element(2, dew_tpl:compile(<<>>, #{unknown => 1})))),
    ?_assertEqual(<<"something">>, Format(something)),
    ?_assertEqual(<<"#{weird => 1}">>, Format(#{weird => 1}))
  ].

format_error_messages_test_() ->
  Reasons = [
    unclosed_tag, unclosed_comment, {unexpected_character, <<"@">>}, {unexpected_character, <<255>>},
    unterminated_string, {unexpected_token, <<"x">>}, unexpected_end_of_expression, empty_tag,
    {unclosed_block, 'if'}, {unexpected_tag, 'else'}, {unexpected_tag, 'else if'}, {unexpected_tag, 'end'},
    {unexpected_tag, 'when'}, {reserved_word, in}, {unknown_function, <<"f">>}, {bad_arity, <<"f">>, 1, 2},
    {unknown_loop_field, <<>>}, {unknown_loop_field, <<"x">>}, content_before_when, {invalid_option, a, b},
    {invalid_source, 1}, {invalid_template, 1}, {file, enoent}, {missing_key, <<"a">>},
    {not_accessible, <<"a">>, 1}, {not_iterable, 1}, {unrenderable_value, {}}, {type_mismatch, '<', 1, a},
    {bad_argument, <<"f">>, 1}, {function_error, <<"f">>, x}, {function_crashed, <<"f">>, error, x},
    {function_crashed, keys, error, x}, {partial_not_found, <<"p">>}, include_depth_exceeded, {bad_data, 1},
    invalid_output, {internal_error, error, x}, {some, unknown, reason}
  ],
  [
    ?_assert(is_binary(dew_tpl:format_error(#{phase => render, reason => Reason, template => <<255>>})))
    || Reason <- Reasons
  ].

format_error_specific_messages_test_() ->
  Message = fun(Reason) -> dew_tpl:format_error(#{phase => render, reason => Reason}) end,
  [
    ?_assertEqual(<<"unclosed tag, missing '}}'">>, Message(unclosed_tag)),
    ?_assertEqual(<<"'if' block is never closed with {{ end }}">>, Message({unclosed_block, 'if'})),
    ?_assertEqual(<<"function 'f' expects 1 argument(s), got 2">>, Message({bad_arity, <<"f">>, 1, 2})),
    ?_assertEqual(<<"cannot compare 1 < a">>, Message({type_mismatch, '<', 1, a})),
    ?_assertEqual(<<"partial 'p' not found">>, Message({partial_not_found, <<"p">>})),
    ?_assertEqual(<<"cannot read file: no such file or directory">>, Message({file, enoent})),
    ?_assertEqual(<<"unexpected character '<<255>>'">>, Message({unexpected_character, <<255>>})),
    ?_assertEqual(<<"function 'f' crashed with error:badarith">>, Message({function_crashed, <<"f">>, error, badarith}))
  ].
