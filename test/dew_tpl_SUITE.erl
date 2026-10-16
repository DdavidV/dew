-module(dew_tpl_SUITE).

%% End-to-end tests for dew_tpl driven by fixture files in `dew_tpl_SUITE_data/'.
%%
%% render/<case>/   template.tpl, data.eterm, expected.txt and optional partials/*.tpl
%% error/<case>/    template.tpl, data.eterm, expected.eterm and optional partials/*.tpl
%%
%% data.eterm holds `{data, Term}.' and optionally `{options, Map}.' Funs can't be written in
%% data.eterm, so `escape_fun => html' means `fun dew_tpl:escape_html/1' and every case gets the
%% functions from `functions/0'. expected.eterm holds one map that must be a subset of the error.
%% Adding a case only needs a new directory.

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([
  all/0,
  groups/0,
  init_per_group/2,
  end_per_group/2
]).

-export([
  render_golden/1,
  error_golden/1,
  compiled_and_source_agree/1,
  iodata_output_agrees/1,
  large_loop/1,
  compile_file_names/1,
  compile_file_errors/1,
  shared_partials/1,
  shared_partial_errors/1,
  concurrent_renders/1,
  concurrent_compiles/1
]).

all() ->
  [
    {group, render},
    {group, errors},
    {group, files},
    {group, partials},
    {group, concurrency}
  ].

groups() ->
  [
    {render, [], [render_golden, compiled_and_source_agree, iodata_output_agrees, large_loop]},
    {errors, [], [error_golden]},
    {files, [], [compile_file_names, compile_file_errors]},
    {partials, [], [shared_partials, shared_partial_errors]},
    {concurrency, [parallel], [concurrent_renders, concurrent_compiles]}
  ].

init_per_group(partials, Config) ->
  Dir = filename:join(?config(data_dir, Config), "shared_partials"),
  Partials = maps:from_list([
    begin
      {ok, Template} = dew_tpl:compile_file(File),
      {list_to_binary(filename:basename(File, ".tpl")), Template}
    end
    || File <- filelib:wildcard(filename:join(Dir, "*.tpl")), filename:basename(File) =/= "broken.tpl"
  ]),
  {ok, Broken} = file:read_file(filename:join(Dir, "broken.tpl")),
  [{partials, Partials#{<<"broken">> => Broken}} | Config];
init_per_group(_, Config) ->
  Config.

end_per_group(_, _) ->
  ok.

%%%===================================================================
%%% Fixture helpers
%%%===================================================================

functions() ->
  #{
    money => fun(Cents) -> iolist_to_binary(io_lib:format("~b.~2..0b", [Cents div 100, Cents rem 100])) end,
    plural => fun(1, One, _) -> One; (_, _, Many) -> Many end,
    checked => fun(X) when X < 0 -> {error, {negative, X}}; (X) -> X end
  }.

cases(Config, Kind) ->
  Dir = filename:join(?config(data_dir, Config), Kind),
  {ok, Names} = file:list_dir(Dir),
  [filename:join(Dir, Name) || Name <- lists:sort(Names)].

load_case(CaseDir) ->
  {ok, Terms} = file:consult(filename:join(CaseDir, "data.eterm")),
  Data = proplists:get_value(data, Terms),
  Options0 = proplists:get_value(options, Terms, #{}),
  Options1 =
    case Options0 of
      #{escape_fun := html} -> Options0#{escape_fun => fun dew_tpl:escape_html/1};
      _ -> Options0
    end,
  Partials = maps:from_list([
    begin
      {ok, Source} = file:read_file(File),
      {list_to_binary(filename:basename(File, ".tpl")), Source}
    end
    || File <- filelib:wildcard(filename:join([CaseDir, "partials", "*.tpl"]))
  ]),
  Options = Options1#{functions => functions(), partials => Partials, name => <<"template.tpl">>},
  {filename:join(CaseDir, "template.tpl"), Data, Options}.

render_case(CaseDir) ->
  {TemplateFile, Data, Options} = load_case(CaseDir),
  case dew_tpl:compile_file(TemplateFile, Options) of
    {ok, Template} -> dew_tpl:render(Template, Data, Options);
    {error, Error} -> {error, Error}
  end.

%% Runs every case and fails once with all failing case names, so one broken fixture
%% doesn't hide the others.
run_all(Cases, Check) ->
  ?assertNotEqual([], Cases),
  Failures = lists:filtermap(
    fun(CaseDir) ->
      try Check(CaseDir) of
        ok -> false;
        {fail, Why} -> {true, {filename:basename(CaseDir), Why}}
      catch
        Class:Reason:Stacktrace -> {true, {filename:basename(CaseDir), {Class, Reason, Stacktrace}}}
      end
    end,
    Cases
  ),
  [ct:pal("fixture ~ts failed:~n~tp", [Name, Why]) || {Name, Why} <- Failures],
  case Failures of
    [] -> {comment, io_lib:format("~b fixtures", [length(Cases)])};
    _ -> ct:fail({failed_fixtures, [Name || {Name, _} <- Failures]})
  end.

%%%===================================================================
%%% render group
%%%===================================================================

render_golden(Config) ->
  run_all(cases(Config, "render"), fun(CaseDir) ->
    {ok, Expected} = file:read_file(filename:join(CaseDir, "expected.txt")),
    case render_case(CaseDir) of
      {ok, Expected} -> ok;
      {ok, Output} -> {fail, {output_mismatch, {expected, Expected}, {got, Output}}};
      {error, Error} -> {fail, {error, dew_tpl:format_error(Error)}}
    end
  end).

compiled_and_source_agree(Config) ->
  run_all(cases(Config, "render"), fun(CaseDir) ->
    {TemplateFile, Data, Options} = load_case(CaseDir),
    {ok, Source} = file:read_file(TemplateFile),
    case {render_case(CaseDir), dew_tpl:render(Source, Data, Options)} of
      {Same, Same} -> ok;
      Different -> {fail, Different}
    end
  end).

iodata_output_agrees(Config) ->
  run_all(cases(Config, "render"), fun(CaseDir) ->
    {TemplateFile, Data, Options} = load_case(CaseDir),
    {ok, Template} = dew_tpl:compile_file(TemplateFile, Options),
    {ok, IoData} = dew_tpl:render(Template, Data, Options#{output => iodata}),
    {ok, Binary} = dew_tpl:render(Template, Data, Options),
    case iolist_to_binary(IoData) of
      Binary -> ok;
      Other -> {fail, {iodata_mismatch, Other, Binary}}
    end
  end).

large_loop(_Config) ->
  Items = [#{id => I, name => <<"item", (integer_to_binary(I))/binary>>, even => I rem 2 =:= 0} || I <- lists:seq(1, 10000)],
  Source = <<"{{ for item in items }}{{ item.id }}:{{ item.name }}{{ if item.even }}*{{ end }}{{ if not loop.last }},{{ end }}{{ end }}">>,
  {ok, Template} = dew_tpl:compile(Source),
  {Micros, {ok, Output}} = timer:tc(dew_tpl, render, [Template, #{items => Items}]),
  Expected = iolist_to_binary(lists:join(",", [
    [integer_to_binary(I), ":item", integer_to_binary(I), case I rem 2 of 0 -> "*"; 1 -> "" end]
    || I <- lists:seq(1, 10000)
  ])),
  ?assertEqual(Expected, Output),
  {comment, io_lib:format("10k items rendered in ~b us", [Micros])}.

%%%===================================================================
%%% errors group
%%%===================================================================

error_golden(Config) ->
  run_all(cases(Config, "error"), fun(CaseDir) ->
    {ok, [Expected]} = file:consult(filename:join(CaseDir, "expected.eterm")),
    case render_case(CaseDir) of
      {error, Error} ->
        true = is_binary(dew_tpl:format_error(Error)),
        case maps:with(maps:keys(Expected), Error) of
          Expected -> ok;
          Actual -> {fail, {error_mismatch, {expected, Expected}, {got, Actual}}}
        end;
      {ok, Output} ->
        {fail, {unexpected_success, Output}}
    end
  end).

%%%===================================================================
%%% files group
%%%===================================================================

compile_file_names(Config) ->
  [
    begin
      File = filename:join(CaseDir, "template.tpl"),
      {ok, _} = dew_tpl:compile_file(File, #{functions => functions()})
    end
    || CaseDir <- cases(Config, "render")
  ],
  BadFile = filename:join([?config(data_dir, Config), "error", "unclosed_block", "template.tpl"]),
  BadName = list_to_binary(BadFile),
  {error, Error} = dew_tpl:compile_file(BadFile),
  ?assertMatch(#{template := BadName, line := 1, column := 1}, Error),
  Message = dew_tpl:format_error(Error),
  ?assertMatch(<<BadName:(byte_size(BadName))/binary, ":1:1: 'for' block is never closed", _/binary>>, Message),
  {error, Named} = dew_tpl:compile_file(BadFile, #{name => <<"pretty.tpl">>}),
  ?assertMatch(#{template := <<"pretty.tpl">>}, Named).

compile_file_errors(Config) ->
  DataDir = ?config(data_dir, Config),
  ?assertMatch({error, #{phase := compile, reason := {file, enoent}}}, dew_tpl:compile_file(filename:join(DataDir, "nope.tpl"))),
  ?assertMatch({error, #{phase := compile, reason := {file, eisdir}}}, dew_tpl:compile_file(DataDir)),
  {error, Error} = dew_tpl:compile_file(filename:join(DataDir, "nope.tpl")),
  ?assertMatch(<<_/binary>>, dew_tpl:format_error(Error)).

%%%===================================================================
%%% partials group
%%%===================================================================

shared_partials(Config) ->
  Options = #{partials => ?config(partials, Config)},
  Data = #{title => <<"Home">>, links => [#{href => <<"/">>, text => <<"Home">>}, #{href => <<"/about">>, text => <<"About">>}]},
  ?assertEqual(
    {ok, <<"<html><title>Home</title><body><nav><a href=\"/\">Home</a><a href=\"/about\">About</a></nav></body></html>">>},
    dew_tpl:render(<<"{{ include \"layout\" }}">>, Data, Options)
  ),
  ?assertEqual(
    {ok, <<"<nav></nav>">>},
    dew_tpl:render(<<"{{ include \"nav\" }}">>, #{links => []}, Options)
  ).

shared_partial_errors(Config) ->
  Options = #{partials => ?config(partials, Config)},
  ?assertMatch(
    {error, #{phase := render, reason := {missing_key, <<"links">>}, template := <<"nav">>,
              include_stack := [<<"layout">>, <<"nav">>]}},
    dew_tpl:render(<<"{{ include \"layout\" }}">>, #{title => t}, Options)
  ),
  ?assertMatch(
    {error, #{phase := compile, reason := unexpected_end_of_expression, template := <<"broken">>,
              include_stack := [<<"uses_broken">>, <<"broken">>]}},
    dew_tpl:render(<<"{{ include \"uses_broken\" }}">>, #{}, Options)
  ),
  ?assertEqual({ok, <<"fine">>}, dew_tpl:render(<<"fine">>, #{}, Options)).

%%%===================================================================
%%% concurrency group
%%%===================================================================

concurrent_renders(Config) ->
  CaseDir = filename:join([?config(data_dir, Config), "render", "markdown_report"]),
  {TemplateFile, Data, Options} = load_case(CaseDir),
  {ok, Expected} = file:read_file(filename:join(CaseDir, "expected.txt")),
  {ok, Template} = dew_tpl:compile_file(TemplateFile, Options),
  Parent = self(),
  Pids = [
    spawn_link(fun() -> Parent ! {self(), dew_tpl:render(Template, Data, Options)} end)
    || _ <- lists:seq(1, 1000)
  ],
  Results = [receive {Pid, Result} -> Result after 10000 -> timeout end || Pid <- Pids],
  ?assertEqual(lists:duplicate(1000, {ok, Expected}), Results).

concurrent_compiles(Config) ->
  Cases = cases(Config, "render"),
  Parent = self(),
  Pids = [
    spawn_link(fun() -> Parent ! {self(), CaseDir, render_case(CaseDir)} end)
    || _ <- lists:seq(1, 50), CaseDir <- Cases
  ],
  lists:foreach(
    fun(Pid) ->
      receive
        {Pid, CaseDir, Result} ->
          {ok, Expected} = file:read_file(filename:join(CaseDir, "expected.txt")),
          ?assertEqual({ok, Expected}, Result)
      after 10000 ->
        ct:fail(timeout)
      end
    end,
    Pids
  ).
