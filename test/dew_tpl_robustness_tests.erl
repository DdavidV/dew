-module(dew_tpl_robustness_tests).

%% "Never raises" checks: random and mutated templates rendered against random data must always
%% return `{ok, _}' or `{error, #{}}', never crash and never hit an internal error.

-include_lib("eunit/include/eunit.hrl").

-define(SEED, {17, 42, 1234}).

valid_templates() ->
  [
    <<"Hello {{ name | upper }}!">>,
    <<"{{ if a and not b }}x{{ else if c > 1 }}y{{ else }}z{{ end }}">>,
    <<"{{ for i, x in xs }}{{ loop.index }}:{{ x.title | truncate(3) }}{{ else }}-{{ end }}">>,
    <<"{{ case role }}\n{{ when \"a\", \"b\" }}AB\n{{ else }}?\n{{ end }}\n">>,
    <<"{{ include \"p\" item }}{{ default(x.y, \"d\") }}{{ defined(q) }}">>,
    <<"{{# comment #}}{{ join(xs, \", \") }}{{ raw(h) }}{{ escape(h) }}{{ length(xs) }}">>,
    <<"{{ a[0][\"k\"].b }} {{ (a or b) == c }} {{ 1.5 }} {{ -2 }} {{ 'single' }}">>
  ].

random_data(0) ->
  lists:nth(rand:uniform(8), [1, 2.5, <<"s">>, atom, undefined, [], #{}, {t}]);
random_data(Depth) ->
  case rand:uniform(10) of
    1 -> [random_data(Depth - 1) || _ <- lists:seq(1, rand:uniform(3))];
    2 -> {random_data(Depth - 1)};
    3 -> [{name, random_data(Depth - 1)}];
    N when N > 6 ->
      maps:from_list([{Key, random_data(Depth - 1)} || Key <- [name, a, b, c, xs, x, y, item, role, h, q, title, k]]);
    _ ->
      random_data(0)
  end.

random_bytes(Length) ->
  Alphabet = <<"{}#\"'\\()[].,|=!<>- \n\tabcxyz019ifelsendforcasewhenincludeandornottruefalsenil", 255, 195>>,
  << <<(binary:at(Alphabet, rand:uniform(byte_size(Alphabet)) - 1))>> || _ <- lists:seq(1, Length) >>.

mutate(<<>>) ->
  random_bytes(1);
mutate(Template) ->
  Size = byte_size(Template),
  case rand:uniform(5) of
    1 ->
      binary:part(Template, 0, rand:uniform(Size + 1) - 1);
    2 ->
      Position = rand:uniform(Size) - 1,
      <<(binary:part(Template, 0, Position))/binary, (binary:part(Template, Position + 1, Size - Position - 1))/binary>>;
    3 ->
      Position = rand:uniform(Size + 1) - 1,
      <<(binary:part(Template, 0, Position))/binary, (random_bytes(rand:uniform(4)))/binary,
        (binary:part(Template, Position, Size - Position))/binary>>;
    4 ->
      binary:replace(Template, <<"}}">>, <<"}">>);
    5 ->
      Parts = binary:split(Template, <<" ">>, [global]),
      iolist_to_binary(lists:join(<<" ">>, shuffle(Parts)))
  end.

shuffle(List) ->
  [X || {_, X} <- lists:sort([{rand:uniform(), X} || X <- List])].

options() ->
  Functions = #{f => fun(X) -> X end, crash => fun(_) -> erlang:error(boom) end},
  Partials = #{p => <<"[{{ name }}]">>, self => <<"{{ include \"self\" }}">>, bad => <<"{{">>},
  Missing = lists:nth(rand:uniform(2), [error, empty]),
  Escape = lists:nth(rand:uniform(2), [none, fun dew_tpl:escape_html/1]),
  #{functions => Functions, partials => Partials, missing => Missing, escape_fun => Escape}.

check(Source, Data, Options) ->
  Result =
    try
      dew_tpl:render(Source, Data, Options)
    catch
      Class:Raised:Stacktrace ->
        erlang:error({raised, Source, Data, Class, Raised, Stacktrace})
    end,
  case Result of
    {ok, Output} when is_binary(Output) ->
      ok;
    {error, #{phase := Phase, reason := Reason} = Error} when Phase =:= compile; Phase =:= render ->
      case Reason of
        {internal_error, _, _} -> erlang:error({internal_error, Source, Data, Error});
        _ -> ok
      end,
      true = is_binary(dew_tpl:format_error(Error)),
      ok;
    Other ->
      erlang:error({unexpected_result, Source, Data, Other})
  end.

random_bytes_never_raise_test_() ->
  {timeout, 120, fun() ->
    rand:seed(exsss, ?SEED),
    lists:foreach(
      fun(_) -> check(random_bytes(rand:uniform(60)), random_data(3), options()) end,
      lists:seq(1, 3000)
    )
  end}.

mutated_templates_never_raise_test_() ->
  {timeout, 120, fun() ->
    rand:seed(exsss, ?SEED),
    lists:foreach(
      fun(_) ->
        Template = lists:nth(rand:uniform(length(valid_templates())), valid_templates()),
        Mutated = lists:foldl(fun(_, T) -> mutate(T) end, Template, lists:seq(1, rand:uniform(3))),
        check(Mutated, random_data(3), options())
      end,
      lists:seq(1, 5000)
    )
  end}.

valid_templates_with_random_data_never_raise_test_() ->
  {timeout, 120, fun() ->
    rand:seed(exsss, ?SEED),
    lists:foreach(
      fun(_) ->
        [check(Template, random_data(4), options()) || Template <- valid_templates()]
      end,
      lists:seq(1, 500)
    )
  end}.

random_options_never_raise_test() ->
  rand:seed(exsss, ?SEED),
  Values = [1, a, <<"b">>, "c", [], #{}, fun() -> ok end, fun(_) -> ok end, {x}, -1, infinity, error, empty],
  Keys = [name, keys, functions, escape_fun, missing, partials, output, max_include_depth, other],
  lists:foreach(
    fun(_) ->
      Options = maps:from_list([{lists:nth(rand:uniform(length(Keys)), Keys), lists:nth(rand:uniform(length(Values)), Values)}]),
      check(<<"{{ a }}">>, #{a => 1}, Options),
      case dew_tpl:compile(<<"{{ a }}">>, Options) of
        {ok, _} -> ok;
        {error, #{reason := {invalid_option, _, _}}} -> ok
      end
    end,
    lists:seq(1, 300)
  ).

deep_nesting_test() ->
  Depth = 500,
  Source = iolist_to_binary([
    lists:duplicate(Depth, <<"{{ if true }}">>), <<"deep">>, lists:duplicate(Depth, <<"{{ end }}">>)
  ]),
  ?assertEqual({ok, <<"deep">>}, dew_tpl:render(Source, #{})),
  Parens = iolist_to_binary([<<"{{ ">>, lists:duplicate(Depth, $(), <<"1">>, lists:duplicate(Depth, $)), <<" }}">>]),
  ?assertEqual({ok, <<"1">>}, dew_tpl:render(Parens, #{})).

concurrent_renders_test() ->
  {ok, Template} = dew_tpl:compile(<<"{{ for x in xs }}{{ x }}{{ end }}">>),
  Parent = self(),
  Pids = [spawn_link(fun() -> Parent ! {self(), dew_tpl:render(Template, #{xs => [N, N]})} end) || N <- lists:seq(1, 200)],
  Results = [receive {Pid, Result} -> Result end || Pid <- Pids],
  ?assertEqual([{ok, <<(integer_to_binary(N))/binary, (integer_to_binary(N))/binary>>} || N <- lists:seq(1, 200)], Results).
