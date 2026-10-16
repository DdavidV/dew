-module(dew_tpl_lexer_tests).

-include_lib("eunit/include/eunit.hrl").

render(Source) ->
  render(Source, #{}).

render(Source, Data) ->
  {ok, Binary} = dew_tpl:render(Source, Data),
  Binary.

error_at(Source) ->
  {error, #{reason := Reason, line := Line, column := Column}} = dew_tpl:compile(Source),
  {Reason, Line, Column}.

text_only_test_() ->
  [
    ?_assertEqual(<<>>, render(<<>>)),
    ?_assertEqual(<<"plain text">>, render(<<"plain text">>)),
    ?_assertEqual(<<"line1\nline2\n">>, render(<<"line1\nline2\n">>)),
    ?_assertEqual(<<"single { brace } and }} closing">>, render(<<"single { brace } and }} closing">>)),
    ?_assertEqual(<<"{ {">>, render(<<"{ {">>))
  ].

charlist_source_test() ->
  ?assertEqual({ok, <<"hi bob">>}, dew_tpl:render("hi {{ name }}", #{name => bob})).

tag_positions_test_() ->
  Data = #{a => <<"A">>, b => <<"B">>},
  [
    ?_assertEqual(<<"A">>, render(<<"{{ a }}">>, Data)),
    ?_assertEqual(<<"xAy">>, render(<<"x{{ a }}y">>, Data)),
    ?_assertEqual(<<"xA">>, render(<<"x{{ a }}">>, Data)),
    ?_assertEqual(<<"AB">>, render(<<"{{ a }}{{ b }}">>, Data)),
    ?_assertEqual(<<"A">>, render(<<"{{a}}">>, Data)),
    ?_assertEqual(<<"A">>, render(<<"{{\n  a\n}}">>, Data)),
    ?_assertEqual(<<"A">>, render(<<"{{\ta\r\n}}">>, Data))
  ].

comments_test_() ->
  [
    ?_assertEqual(<<"ab">>, render(<<"a{{# comment #}}b">>)),
    ?_assertEqual(<<"ab">>, render(<<"a{{# {{ not a tag }} #}}b">>)),
    ?_assertEqual(<<"ab">>, render(<<"a{{#\nmulti\nline\n#}}b">>)),
    ?_assertEqual(<<"a">>, render(<<"a{{##}}">>))
  ].

comment_keeps_line_numbers_test() ->
  ?assertMatch({missing_key, _}, element(1, render_error(<<"{{# one\ntwo #}}\n{{ x }}">>))),
  ?assertEqual({4, 4}, element(2, render_error(<<"{{# one\ntwo #}}\nx\n{{ x }}">>))).

render_error(Source) ->
  {error, #{reason := Reason, line := Line, column := Column}} = dew_tpl:render(Source, #{}),
  {Reason, {Line, Column}}.

string_literals_test_() ->
  [
    ?_assertEqual(<<"hello">>, render(<<"{{ \"hello\" }}">>)),
    ?_assertEqual(<<"hello">>, render(<<"{{ 'hello' }}">>)),
    ?_assertEqual(<<"{{">>, render(<<"{{ \"{{\" }}">>)),
    ?_assertEqual(<<"}}">>, render(<<"{{ \"}}\" }}">>)),
    ?_assertEqual(<<"a\"b">>, render(<<"{{ \"a\\\"b\" }}">>)),
    ?_assertEqual(<<"it's">>, render(<<"{{ 'it\\'s' }}">>)),
    ?_assertEqual(<<"it's">>, render(<<"{{ \"it's\" }}">>)),
    ?_assertEqual(<<"a\nb\tc\rd">>, render(<<"{{ \"a\\nb\\tc\\rd\" }}">>)),
    ?_assertEqual(<<"a\\b">>, render(<<"{{ \"a\\\\b\" }}">>)),
    ?_assertEqual(<<"multi\nline">>, render(<<"{{ \"multi\nline\" }}">>)),
    ?_assertEqual(<<>>, render(<<"{{ \"\" }}">>)),
    ?_assertEqual(<<"árvíztűrő 🎉"/utf8>>, render(<<"{{ \"árvíztűrő 🎉\" }}"/utf8>>))
  ].

number_literals_test_() ->
  [
    ?_assertEqual(<<"0">>, render(<<"{{ 0 }}">>)),
    ?_assertEqual(<<"42">>, render(<<"{{ 42 }}">>)),
    ?_assertEqual(<<"-7">>, render(<<"{{ -7 }}">>)),
    ?_assertEqual(<<"1.5">>, render(<<"{{ 1.5 }}">>)),
    ?_assertEqual(<<"-0.25">>, render(<<"{{ -0.25 }}">>)),
    ?_assertEqual(<<"123456789012345678901234567890">>, render(<<"{{ 123456789012345678901234567890 }}">>))
  ].

keyword_literals_test_() ->
  [
    ?_assertEqual(<<"true">>, render(<<"{{ true }}">>)),
    ?_assertEqual(<<"false">>, render(<<"{{ false }}">>)),
    ?_assertEqual(<<>>, render(<<"{{ nil }}">>))
  ].

operators_test_() ->
  [
    ?_assertEqual(<<"true">>, render(<<"{{ 1 == 1 }}">>)),
    ?_assertEqual(<<"true">>, render(<<"{{ 1 != 2 }}">>)),
    ?_assertEqual(<<"true">>, render(<<"{{ 1 < 2 }}">>)),
    ?_assertEqual(<<"true">>, render(<<"{{ 2 <= 2 }}">>)),
    ?_assertEqual(<<"true">>, render(<<"{{ 3 > 2 }}">>)),
    ?_assertEqual(<<"true">>, render(<<"{{ 2 >= 2 }}">>)),
    ?_assertEqual(<<"true">>, render(<<"{{1==1}}">>)),
    ?_assertEqual(<<"x">>, render(<<"{{ true and \"x\" }}">>)),
    ?_assertEqual(<<"x">>, render(<<"{{ false or \"x\" }}">>)),
    ?_assertEqual(<<"false">>, render(<<"{{ not true }}">>))
  ].

identifiers_test_() ->
  Data = #{'_private' => 1, camelCase => 2, with_9_digits => 3, 'if_x' => 4, ends => 5},
  [
    ?_assertEqual(<<"1">>, render(<<"{{ _private }}">>, Data)),
    ?_assertEqual(<<"2">>, render(<<"{{ camelCase }}">>, Data)),
    ?_assertEqual(<<"3">>, render(<<"{{ with_9_digits }}">>, Data)),
    ?_assertEqual(<<"4">>, render(<<"{{ if_x }}">>, Data)),
    ?_assertEqual(<<"5">>, render(<<"{{ ends }}">>, Data))
  ].

keywords_after_dot_are_keys_test() ->
  ?assertEqual(<<"1">>, render(<<"{{ x.end }}">>, #{x => #{'end' => 1}})),
  ?assertEqual(<<"2">>, render(<<"{{ x.if.in }}">>, #{x => #{'if' => #{in => 2}}})).

utf8_text_test() ->
  Source = <<"árvíz {{ name }} tűrő\n"/utf8>>,
  ?assertEqual(<<"árvíz Bob tűrő\n"/utf8>>, render(Source, #{name => <<"Bob">>})).

utf8_columns_test() ->
  ?assertEqual({{missing_key, <<"x">>}, {1, 9}}, render_error(<<"árvíz{{ x }}"/utf8>>)),
  ?assertEqual({{missing_key, <<"x">>}, {2, 5}}, render_error(<<"á\n🎉{{ x }}"/utf8>>)).

invalid_utf8_text_is_passed_through_test() ->
  ?assertEqual(<<255, 254, "1">>, render(<<255, 254, "{{ x }}">>, #{x => 1})).

line_and_column_test_() ->
  [
    ?_assertEqual({{missing_key, <<"x">>}, {1, 4}}, render_error(<<"{{ x }}">>)),
    ?_assertEqual({{missing_key, <<"x">>}, {1, 7}}, render_error(<<"abc{{ x }}">>)),
    ?_assertEqual({{missing_key, <<"x">>}, {3, 4}}, render_error(<<"a\nb\nc{{x}}">>)),
    ?_assertEqual({{missing_key, <<"x">>}, {2, 3}}, render_error(<<"{{\n  x }}">>)),
    ?_assertEqual({{missing_key, <<"y">>}, {1, 14}}, render_error(<<"{{ \"a\" }}{{  y }}">>))
  ].

lexer_errors_test_() ->
  [
    ?_assertEqual({unclosed_tag, 1, 1}, error_at(<<"{{ x">>)),
    ?_assertEqual({unclosed_tag, 1, 4}, error_at(<<"ab {{">>)),
    ?_assertEqual({{unexpected_character, <<"}">>}, 2, 6}, error_at(<<"ok\n{{ x }">>)),
    ?_assertEqual({unclosed_tag, 2, 1}, error_at(<<"ok\n{{ x ">>)),
    ?_assertEqual({unclosed_comment, 1, 1}, error_at(<<"{{# comment">>)),
    ?_assertEqual({unclosed_comment, 1, 1}, error_at(<<"{{# comment }}">>)),
    ?_assertEqual({unterminated_string, 1, 4}, error_at(<<"{{ \"abc }}">>)),
    ?_assertEqual({unterminated_string, 1, 4}, error_at(<<"{{ 'abc">>)),
    ?_assertEqual({{unexpected_character, <<"@">>}, 1, 4}, error_at(<<"{{ @ }}">>)),
    ?_assertEqual({{unexpected_character, <<"=">>}, 1, 6}, error_at(<<"{{ a = b }}">>)),
    ?_assertEqual({{unexpected_character, <<"!">>}, 1, 4}, error_at(<<"{{ !a }}">>)),
    ?_assertEqual({{unexpected_character, <<"-">>}, 1, 6}, error_at(<<"{{ a - b }}">>)),
    ?_assertEqual({{unexpected_character, <<"{">>}, 1, 3}, error_at(<<"{{{ a }}}">>)),
    ?_assertEqual({{unexpected_character, <<"é"/utf8>>}, 1, 4}, error_at(<<"{{ é }}"/utf8>>)),
    ?_assertEqual({{unexpected_character, <<255>>}, 1, 4}, error_at(<<"{{ ", 255, " }}">>))
  ].

standalone_lines_test_() ->
  Data = #{x => true, items => [1, 2]},
  [
    ?_assertEqual(<<"a\nb\n">>, render(<<"a\n{{ if x }}\nb\n{{ end }}\n">>, Data)),
    ?_assertEqual(<<"b\n">>, render(<<"{{ if x }}\nb\n{{ end }}\n">>, Data)),
    ?_assertEqual(<<"b\n">>, render(<<"{{ if x }}\nb\n{{ end }}">>, Data)),
    ?_assertEqual(<<"a\nb\n">>, render(<<"a\n  {{ if x }}  \nb\n\t{{ end }}\n">>, Data)),
    ?_assertEqual(<<"a\r\nb\r\n">>, render(<<"a\r\n{{ if x }}\r\nb\r\n{{ end }}\r\n">>, Data)),
    ?_assertEqual(<<"a\nb\n">>, render(<<"a\n{{# comment #}}\nb\n">>, Data)),
    ?_assertEqual(<<"1\n2\n">>, render(<<"{{ for i in items }}\n{{ i }}\n{{ end }}\n">>, Data)),
    ?_assertEqual(<<"a\nb\n">>, render(<<"a\n{{ if x }}{{ if x }}\nb\n{{ end }}{{ end }}\n">>, Data))
  ].

not_standalone_test_() ->
  Data = #{x => true, v => <<"V">>},
  [
    ?_assertEqual(<<"a b\n">>, render(<<"a {{ if x }}b{{ end }}\n">>, Data)),
    ?_assertEqual(<<"V\nb\n">>, render(<<"{{ v }}{{ if x }}\nb\n{{ end }}\n">>, Data)),
    ?_assertEqual(<<"x \ny\n">>, render(<<"x {{# c #}}\ny\n">>, Data)),
    ?_assertEqual(<<"V\n">>, render(<<"{{ v }}\n">>, Data)),
    ?_assertEqual(<<"  V  \n">>, render(<<"  {{ v }}  \n">>, Data))
  ].

standalone_include_test() ->
  Partials = #{p => <<"P\n">>},
  ?assertEqual(
    {ok, <<"a\nP\nb\n">>},
    dew_tpl:render(<<"a\n{{ include \"p\" }}\nb\n">>, #{}, #{partials => Partials})
  ).
