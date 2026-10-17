-module(dew_tpl).

-type keys() :: atom | binary | string | fun((binary()) -> term()).

-type options() :: #{
  name => binary() | string() | atom(),
  keys => keys(),
  functions => #{atom() | binary() => function()},
  escape_fun => none | fun((binary()) -> iodata()),
  missing => error | empty,
  partials => #{atom() | binary() | string() => template() | binary() | string()},
  output => binary | iodata,
  max_include_depth => non_neg_integer()
}.

-type error() :: #{
  phase := compile | render,
  reason := term(),
  line => pos_integer(),
  column => pos_integer(),
  template => binary(),
  snippet => binary(),
  include_stack => [binary()]
}.

-type source() :: binary() | string().

-record(cfg, {
  name = undefined :: binary() | undefined,
  keys = atom :: keys(),
  functions = #{} :: #{binary() => {builtin | special, atom(), arity()} | {user, function(), arity()}},
  escape = none :: none | fun((binary()) -> iodata())
}).

-record(ropts, {
  missing = error :: error | empty,
  partials = #{} :: map(),
  output = binary :: binary | iodata,
  max_depth = 32 :: non_neg_integer()
}).

-record(env, {
  data :: term(),
  vars = #{} :: #{binary() => term()},
  loop = undefined :: {non_neg_integer(), non_neg_integer() | undefined} | undefined,
  missing = error :: error | empty,
  partials = #{} :: #{binary() => template() | {error, error()}},
  depth = 0 :: non_neg_integer(),
  max_depth = 32 :: non_neg_integer()
}).

-opaque template() :: {dew_tpl, binary() | undefined, #cfg{}, binary() | fun((#env{}) -> iodata())}.

-export_type([
  keys/0,
  options/0,
  error/0,
  source/0,
  template/0
]).

-export([
  compile/1,
  compile/2,
  compile_file/1,
  compile_file/2,
  render/2,
  render/3
]).

-export([
  format_error/1,
  escape_html/1
]).

-define(THROW(Reason, Pos), throw({dew_tpl, Reason, Pos})).

-spec compile(Source) -> Result when
  Source :: source(),
  Result :: {ok, template()} | {error, error()}.
compile(Source) ->
  compile(Source, #{}).

-spec compile(Source, Options) -> Result when
  Source :: source(),
  Options :: options(),
  Result :: {ok, template()} | {error, error()}.
compile(Source, Options) ->
  case validate_options(Options, compile) of
    {ok, Cfg, _} -> compile_source(Source, Cfg);
    {error, Error} -> {error, Error}
  end.

-spec compile_file(Path) -> Result when
  Path :: file:filename_all(),
  Result :: {ok, template()} | {error, error()}.
compile_file(Path) ->
  compile_file(Path, #{}).

-spec compile_file(Path, Options) -> Result when
  Path :: file:filename_all(),
  Options :: options(),
  Result :: {ok, template()} | {error, error()}.
compile_file(Path, Options) ->
  case validate_options(Options, compile) of
    {ok, Cfg0, _} ->
      Cfg =
        case Cfg0#cfg.name of
          undefined -> Cfg0#cfg{name = path_name(Path)};
          _ -> Cfg0
        end,
      case read_file(Path) of
        {ok, Source} -> compile_source(Source, Cfg);
        {error, Posix} -> {error, make_error(compile, {file, Posix}, nopos, Cfg#cfg.name)}
      end;
    {error, Error} ->
      {error, Error}
  end.

-spec render(Template, Data) -> Result when
  Template :: template() | source(),
  Data :: map() | list(),
  Result :: {ok, binary() | iodata()} | {error, error()}.
render(Template, Data) ->
  render(Template, Data, #{}).

-spec render(Template, Data, Options) -> Result when
  Template :: template() | source(),
  Data :: map() | list(),
  Options :: options(),
  Result :: {ok, binary() | iodata()} | {error, error()}.
render(Source, Data, Options) when is_binary(Source); is_list(Source) ->
  case compile(Source, Options) of
    {ok, Template} -> render(Template, Data, Options);
    {error, Error} -> {error, Error}
  end;
render({dew_tpl, Name, Cfg, Fun}, Data, Options) ->
  case validate_options(Options, render) of
    {ok, _, _} when not is_map(Data), not is_list(Data) ->
      {error, make_error(render, {bad_data, Data}, nopos, Name)};
    {ok, _, Ropts} ->
      Env = #env{
        data = Data,
        missing = Ropts#ropts.missing,
        partials = normalize_partials(Ropts#ropts.partials, Cfg),
        max_depth = Ropts#ropts.max_depth
      },
      try run(Fun, Env) of
        IoData -> output(IoData, Ropts#ropts.output, Name)
      catch
        throw:{dew_tpl, Reason, Pos} ->
          {error, make_error(render, Reason, Pos, Name)};
        throw:{dew_tpl_error, Error} ->
          {error, Error};
        Class:Reason ->
          {error, make_error(render, {internal_error, Class, Reason}, nopos, Name)}
      end;
    {error, Error} ->
      {error, Error}
  end;
render(Other, _Data, _Options) ->
  {error, make_error(render, {invalid_template, Other}, nopos, undefined)}.

-spec format_error(Error) -> Message when
  Error :: error(),
  Message :: binary().
format_error(#{reason := Reason} = Error) ->
  Stack =
    case maps:get(include_stack, Error, []) of
      [] -> [];
      Names -> [" (included via ", lists:join(" -> ", [text(N) || N <- Names]), ")"]
    end,
  Snippet =
    case Error of
      #{snippet := Line, column := Column} ->
        ["\n    ", text(Line), "\n    ", caret_padding(Line, Column - 1), "^"];
      _ ->
        []
    end,
  to_binary([location(Error), message(Reason), Stack, Snippet], Error);
format_error(Other) ->
  to_binary(io_lib:format("~tP", [Other, 20]), Other).

-spec escape_html(Value) -> Escaped when
  Value :: binary() | string() | number() | atom(),
  Escaped :: binary().
escape_html(Value) when is_binary(Value) ->
  case binary:matches(Value, [<<"&">>, <<"<">>, <<">">>, <<"\"">>, <<"'">>]) of
    [] -> Value;
    Matches -> iolist_to_binary(escape_parts(Value, 0, Matches))
  end;
escape_html(Value) ->
  try to_text(Value, nopos) of
    Text -> escape_html(Text)
  catch
    throw:{dew_tpl, _, _} -> erlang:error(badarg, [Value])
  end.

%%%===================================================================
%%% Options
%%%===================================================================

validate_options(Options, Phase) when is_map(Options) ->
  try maps:fold(fun validate_option/3, {#cfg{}, #ropts{}}, Options) of
    {Cfg, Ropts} ->
      Functions = maps:merge(builtins(), Cfg#cfg.functions),
      {ok, Cfg#cfg{functions = Functions}, Ropts}
  catch
    throw:{invalid_option, Key, Value} ->
      {error, make_error(Phase, {invalid_option, Key, Value}, nopos, undefined)}
  end;
validate_options(Options, Phase) ->
  {error, make_error(Phase, {invalid_option, options, Options}, nopos, undefined)}.

validate_option(name, Value, {Cfg, Ropts}) when is_binary(Value) ->
  {Cfg#cfg{name = Value}, Ropts};
validate_option(name, Value, {Cfg, Ropts}) when is_atom(Value) ->
  {Cfg#cfg{name = atom_to_binary(Value, utf8)}, Ropts};
validate_option(name, Value, {Cfg, Ropts}) when is_list(Value) ->
  case chars_to_binary(Value) of
    {ok, Name} -> {Cfg#cfg{name = Name}, Ropts};
    error -> throw({invalid_option, name, Value})
  end;
validate_option(keys, Value, {Cfg, Ropts}) when Value =:= atom; Value =:= binary; Value =:= string ->
  {Cfg#cfg{keys = Value}, Ropts};
validate_option(keys, Value, {Cfg, Ropts}) when is_function(Value, 1) ->
  {Cfg#cfg{keys = Value}, Ropts};
validate_option(functions, Value, {Cfg, Ropts}) when is_map(Value) ->
  {Cfg#cfg{functions = maps:fold(fun validate_function/3, #{}, Value)}, Ropts};
validate_option(escape_fun, none, {Cfg, Ropts}) ->
  {Cfg#cfg{escape = none}, Ropts};
validate_option(escape_fun, Value, {Cfg, Ropts}) when is_function(Value, 1) ->
  {Cfg#cfg{escape = Value}, Ropts};
validate_option(missing, Value, {Cfg, Ropts}) when Value =:= error; Value =:= empty ->
  {Cfg, Ropts#ropts{missing = Value}};
validate_option(partials, Value, {Cfg, Ropts}) when is_map(Value) ->
  maps:fold(fun validate_partial/3, ok, Value),
  {Cfg, Ropts#ropts{partials = Value}};
validate_option(output, Value, {Cfg, Ropts}) when Value =:= binary; Value =:= iodata ->
  {Cfg, Ropts#ropts{output = Value}};
validate_option(max_include_depth, Value, {Cfg, Ropts}) when is_integer(Value), Value >= 0 ->
  {Cfg, Ropts#ropts{max_depth = Value}};
validate_option(Key, Value, _) ->
  throw({invalid_option, Key, Value}).

validate_function(Name, Fun, Functions) when is_function(Fun), is_atom(Name) ->
  validate_function(atom_to_binary(Name, utf8), Fun, Functions);
validate_function(Name, Fun, Functions) when is_function(Fun), is_binary(Name) ->
  {arity, Arity} = erlang:fun_info(Fun, arity),
  Functions#{Name => {user, Fun, Arity}};
validate_function(Name, Fun, _) ->
  throw({invalid_option, {functions, Name}, Fun}).

validate_partial(_, Value, ok) when is_binary(Value); is_list(Value) ->
  ok;
validate_partial(_, {dew_tpl, _, _, _}, ok) ->
  ok;
validate_partial(Name, Value, ok) ->
  throw({invalid_option, {partials, Name}, Value}).

builtins() ->
  #{
    <<"upper">> => {builtin, upper, 1},
    <<"lower">> => {builtin, lower, 1},
    <<"trim">> => {builtin, trim, 1},
    <<"length">> => {builtin, length, 1},
    <<"join">> => {builtin, join, 2},
    <<"truncate">> => {builtin, truncate, 2},
    <<"escape">> => {builtin, escape, 1},
    <<"raw">> => {special, raw, 1},
    <<"default">> => {special, default, 2},
    <<"defined">> => {special, defined, 1}
  }.

normalize_partials(Partials, _) when map_size(Partials) =:= 0 ->
  Partials;
normalize_partials(Partials, Cfg) ->
  maps:fold(
    fun(Key, Value, Accumulator) ->
      Name = partial_name(Key),
      Accumulator#{Name => partial_template(Name, Value, Cfg)}
    end,
    #{},
    Partials
  ).

partial_name(Name) when is_binary(Name) -> Name;
partial_name(Name) when is_atom(Name) -> atom_to_binary(Name, utf8);
partial_name(Name) ->
  case chars_to_binary(Name) of
    {ok, Binary} -> Binary;
    error -> Name
  end.

partial_template(_, {dew_tpl, _, _, _} = Template, _) ->
  Template;
partial_template(Name, Source, Cfg) ->
  case compile_source(Source, Cfg#cfg{name = Name}) of
    {ok, Template} -> Template;
    {error, Error} -> {error, Error}
  end.

%%%===================================================================
%%% Compilation
%%%===================================================================

compile_source(Source, #cfg{name = Name} = Cfg) ->
  case source_binary(Source) of
    {ok, Binary} ->
      try
        Items = standalone(tokenize(Binary)),
        Nodes = parse(Items, Cfg),
        {ok, {dew_tpl, Name, Cfg, gen_seq(Nodes, Cfg)}}
      catch
        throw:{dew_tpl, Reason, Pos} ->
          {error, compile_error(Reason, Pos, Name, Binary)};
        Class:Reason ->
          {error, make_error(compile, {internal_error, Class, Reason}, nopos, Name)}
      end;
    error ->
      {error, make_error(compile, {invalid_source, Source}, nopos, Name)}
  end.

source_binary(Source) when is_binary(Source) -> {ok, Source};
source_binary(Source) when is_list(Source) -> chars_to_binary(Source);
source_binary(_) -> error.

chars_to_binary(Chars) ->
  try unicode:characters_to_binary(Chars) of
    Binary when is_binary(Binary) -> {ok, Binary};
    _ -> error
  catch
    error:_ -> error
  end.

read_file(Path) ->
  try
    file:read_file(Path)
  catch
    error:_ -> {error, badarg}
  end.

path_name(Path) when is_binary(Path) ->
  Path;
path_name(Path) ->
  try chars_to_binary(filename:flatten(Path)) of
    {ok, Name} -> Name;
    error -> undefined
  catch
    error:_ -> undefined
  end.

%%%===================================================================
%%% Lexer
%%%===================================================================

%% Splits the source into `{text, Bin, Pos}', `{tag, Tokens, Pos}' and `{comment, Pos}' items.
tokenize(Source) ->
  scan(Source, 1, 1, []).

scan(Source, Line, Column, Accumulator) ->
  case binary:match(Source, <<"{{">>) of
    nomatch ->
      lists:reverse(add_text(Source, {Line, Column}, Accumulator));
    {Start, 2} ->
      Text = binary:part(Source, 0, Start),
      {TagLine, TagColumn} = advance(Text, Line, Column),
      Rest = binary:part(Source, Start + 2, byte_size(Source) - Start - 2),
      scan_tag(Rest, TagLine, TagColumn, add_text(Text, {Line, Column}, Accumulator))
  end.

add_text(<<>>, _, Accumulator) -> Accumulator;
add_text(Text, Pos, Accumulator) -> [{text, Text, Pos} | Accumulator].

scan_tag(<<"#", Rest/binary>>, Line, Column, Accumulator) ->
  case binary:match(Rest, <<"#}}">>) of
    nomatch ->
      ?THROW(unclosed_comment, {Line, Column});
    {Start, 3} ->
      Comment = binary:part(Rest, 0, Start),
      {EndLine, EndColumn} = advance(Comment, Line, Column + 3),
      After = binary:part(Rest, Start + 3, byte_size(Rest) - Start - 3),
      scan(After, EndLine, EndColumn + 3, [{comment, {Line, Column}} | Accumulator])
  end;
scan_tag(Rest, Line, Column, Accumulator) ->
  {Tokens, After, EndLine, EndColumn} = tag_tokens(Rest, Line, Column + 2, [], {Line, Column}),
  scan(After, EndLine, EndColumn, [{tag, Tokens, {Line, Column}} | Accumulator]).

advance(Text, Line, Column) ->
  case binary:matches(Text, <<"\n">>) of
    [] ->
      {Line, Column + char_count(Text)};
    Matches ->
      {Last, 1} = lists:last(Matches),
      Tail = binary:part(Text, Last + 1, byte_size(Text) - Last - 1),
      {Line + length(Matches), 1 + char_count(Tail)}
  end.

%% Counts UTF-8 characters without failing on invalid UTF-8.
char_count(Binary) ->
  char_count(Binary, 0).

char_count(<<Byte, Rest/binary>>, Count) when Byte band 16#C0 =:= 16#80 ->
  char_count(Rest, Count);
char_count(<<_, Rest/binary>>, Count) ->
  char_count(Rest, Count + 1);
char_count(<<>>, Count) ->
  Count.

tag_tokens(<<"}}", Rest/binary>>, Line, Column, Accumulator, _) ->
  {lists:reverse([{eot, '}}', {Line, Column}} | Accumulator]), Rest, Line, Column + 2};
tag_tokens(<<$\n, Rest/binary>>, Line, _, Accumulator, TagPos) ->
  tag_tokens(Rest, Line + 1, 1, Accumulator, TagPos);
tag_tokens(<<Space, Rest/binary>>, Line, Column, Accumulator, TagPos)
    when Space =:= $\s; Space =:= $\t; Space =:= $\r ->
  tag_tokens(Rest, Line, Column + 1, Accumulator, TagPos);
tag_tokens(<<Operator:2/binary, Rest/binary>>, Line, Column, Accumulator, TagPos)
    when Operator =:= <<"==">>; Operator =:= <<"!=">>; Operator =:= <<"<=">>; Operator =:= <<">=">> ->
  Token = {punct, punct(Operator), {Line, Column}},
  tag_tokens(Rest, Line, Column + 2, [Token | Accumulator], TagPos);
tag_tokens(<<Char, Rest/binary>>, Line, Column, Accumulator, TagPos)
    when Char =:= $.; Char =:= $,; Char =:= $(; Char =:= $); Char =:= $[; Char =:= $];
         Char =:= $|; Char =:= $<; Char =:= $> ->
  Token = {punct, punct(<<Char>>), {Line, Column}},
  tag_tokens(Rest, Line, Column + 1, [Token | Accumulator], TagPos);
tag_tokens(<<Quote, Rest/binary>>, Line, Column, Accumulator, TagPos) when Quote =:= $"; Quote =:= $' ->
  {String, After, EndLine, EndColumn} = string(Rest, Quote, Line, Column + 1, [], {Line, Column}),
  tag_tokens(After, EndLine, EndColumn, [{str, String, {Line, Column}} | Accumulator], TagPos);
tag_tokens(<<Char, _/binary>> = Binary, Line, Column, Accumulator, TagPos)
    when Char >= $0, Char =< $9 ->
  number(Binary, Line, Column, Accumulator, TagPos);
tag_tokens(<<$-, Char, _/binary>> = Binary, Line, Column, Accumulator, TagPos)
    when Char >= $0, Char =< $9 ->
  number(Binary, Line, Column, Accumulator, TagPos);
tag_tokens(<<Char, _/binary>> = Binary, Line, Column, Accumulator, TagPos)
    when Char >= $a, Char =< $z; Char >= $A, Char =< $Z; Char =:= $_ ->
  Length = ident_length(Binary, 1),
  <<Name:Length/binary, Rest/binary>> = Binary,
  Token =
    case keyword(Name) of
      undefined -> {ident, Name, {Line, Column}};
      Keyword -> {kw, Keyword, {Line, Column}}
    end,
  tag_tokens(Rest, Line, Column + Length, [Token | Accumulator], TagPos);
tag_tokens(<<>>, _, _, _, TagPos) ->
  ?THROW(unclosed_tag, TagPos);
tag_tokens(<<Char/utf8, _/binary>>, Line, Column, _, _) ->
  ?THROW({unexpected_character, <<Char/utf8>>}, {Line, Column});
tag_tokens(<<Byte, _/binary>>, Line, Column, _, _) ->
  ?THROW({unexpected_character, <<Byte>>}, {Line, Column}).

punct(<<"==">>) -> '==';
punct(<<"!=">>) -> '!=';
punct(<<"<=">>) -> '<=';
punct(<<">=">>) -> '>=';
punct(<<".">>) -> '.';
punct(<<",">>) -> ',';
punct(<<"(">>) -> '(';
punct(<<")">>) -> ')';
punct(<<"[">>) -> '[';
punct(<<"]">>) -> ']';
punct(<<"|">>) -> '|';
punct(<<"<">>) -> '<';
punct(<<">">>) -> '>'.

ident_length(Binary, Length) ->
  case Binary of
    <<_:Length/binary, Char, _/binary>>
        when Char >= $a, Char =< $z; Char >= $A, Char =< $Z; Char >= $0, Char =< $9; Char =:= $_ ->
      ident_length(Binary, Length + 1);
    _ ->
      Length
  end.

keyword(<<"if">>) -> 'if';
keyword(<<"else">>) -> 'else';
keyword(<<"end">>) -> 'end';
keyword(<<"for">>) -> 'for';
keyword(<<"in">>) -> 'in';
keyword(<<"case">>) -> 'case';
keyword(<<"when">>) -> 'when';
keyword(<<"include">>) -> include;
keyword(<<"and">>) -> 'and';
keyword(<<"or">>) -> 'or';
keyword(<<"not">>) -> 'not';
keyword(<<"true">>) -> true;
keyword(<<"false">>) -> false;
keyword(<<"nil">>) -> nil;
keyword(_) -> undefined.

number(Binary, Line, Column, Accumulator, TagPos) ->
  Sign = case Binary of <<$-, _/binary>> -> 1; _ -> 0 end,
  IntegerLength = digits_length(Binary, Sign),
  {Token, Length} =
    case Binary of
      <<_:IntegerLength/binary, $., Digit, _/binary>> when Digit >= $0, Digit =< $9 ->
        FloatLength = digits_length(Binary, IntegerLength + 1),
        {{float, binary_to_float(binary:part(Binary, 0, FloatLength)), {Line, Column}}, FloatLength};
      _ ->
        {{int, binary_to_integer(binary:part(Binary, 0, IntegerLength)), {Line, Column}}, IntegerLength}
    end,
  Rest = binary:part(Binary, Length, byte_size(Binary) - Length),
  tag_tokens(Rest, Line, Column + Length, [Token | Accumulator], TagPos).

digits_length(Binary, Length) ->
  case Binary of
    <<_:Length/binary, Digit, _/binary>> when Digit >= $0, Digit =< $9 -> digits_length(Binary, Length + 1);
    _ -> Length
  end.

string(<<Quote, Rest/binary>>, Quote, Line, Column, Accumulator, _) ->
  {list_to_binary(lists:reverse(Accumulator)), Rest, Line, Column + 1};
string(<<$\\, Char, Rest/binary>>, Quote, Line, Column, Accumulator, StartPos) ->
  string(Rest, Quote, Line, Column + 2, [unescape(Char) | Accumulator], StartPos);
string(<<$\n, Rest/binary>>, Quote, Line, _, Accumulator, StartPos) ->
  string(Rest, Quote, Line + 1, 1, [$\n | Accumulator], StartPos);
string(<<Byte, Rest/binary>>, Quote, Line, Column, Accumulator, StartPos) when Byte band 16#C0 =:= 16#80 ->
  string(Rest, Quote, Line, Column, [Byte | Accumulator], StartPos);
string(<<Byte, Rest/binary>>, Quote, Line, Column, Accumulator, StartPos) ->
  string(Rest, Quote, Line, Column + 1, [Byte | Accumulator], StartPos);
string(<<>>, _, _, _, _, StartPos) ->
  ?THROW(unterminated_string, StartPos).

unescape($n) -> $\n;
unescape($t) -> $\t;
unescape($r) -> $\r;
unescape(Char) -> Char.

%% Removes lines that only contain block tags and whitespace (mustache "standalone" lines),
%% then drops comments and empty text.
standalone(Items) ->
  Groups = list_to_tuple(group(Items, [], [])),
  Size = tuple_size(Groups),
  {Leading, Trailing} = standalone_marks(1, Size, Groups, [], []),
  lists:append([
    apply_trim(Index, element(Index, Groups), Leading, Trailing) || Index <- lists:seq(1, Size)
  ]).

group([{text, _, _} = Text | Rest], [], Accumulator) ->
  group(Rest, [], [Text | Accumulator]);
group([{text, _, _} = Text | Rest], Run, Accumulator) ->
  group(Rest, [], [Text, {run, lists:reverse(Run)} | Accumulator]);
group([Tag | Rest], Run, Accumulator) ->
  group(Rest, [Tag | Run], Accumulator);
group([], [], Accumulator) ->
  lists:reverse(Accumulator);
group([], Run, Accumulator) ->
  lists:reverse([{run, lists:reverse(Run)} | Accumulator]).

standalone_marks(Index, Size, _, Leading, Trailing) when Index > Size ->
  {Leading, Trailing};
standalone_marks(Index, Size, Groups, Leading, Trailing) ->
  case element(Index, Groups) of
    {run, Tags} ->
      case
        lists:all(fun block_item/1, Tags) andalso
        left_standalone(Index, Groups) andalso
        right_standalone(Index, Size, Groups)
      of
        true -> standalone_marks(Index + 1, Size, Groups, [Index + 1 | Leading], [Index - 1 | Trailing]);
        false -> standalone_marks(Index + 1, Size, Groups, Leading, Trailing)
      end;
    _ ->
      standalone_marks(Index + 1, Size, Groups, Leading, Trailing)
  end.

block_item({comment, _}) -> true;
block_item({tag, [{kw, Keyword, _} | _], _}) ->
  lists:member(Keyword, ['if', 'else', 'end', 'for', 'case', 'when', include]);
block_item(_) -> false.

left_standalone(1, _) ->
  true;
left_standalone(Index, Groups) ->
  {text, Text, _} = element(Index - 1, Groups),
  case last_newline(Text) of
    nomatch -> Index - 1 =:= 1 andalso blank(Text);
    Last -> blank(binary:part(Text, Last + 1, byte_size(Text) - Last - 1))
  end.

right_standalone(Size, Size, _) ->
  true;
right_standalone(Index, Size, Groups) ->
  {text, Text, _} = element(Index + 1, Groups),
  case binary:match(Text, <<"\n">>) of
    nomatch -> Index + 1 =:= Size andalso blank(Text);
    {First, 1} -> blank(binary:part(Text, 0, First))
  end.

last_newline(Text) ->
  case binary:matches(Text, <<"\n">>) of
    [] -> nomatch;
    Matches -> element(1, lists:last(Matches))
  end.

blank(<<Char, Rest/binary>>) when Char =:= $\s; Char =:= $\t; Char =:= $\r -> blank(Rest);
blank(<<>>) -> true;
blank(_) -> false.

apply_trim(_, {run, Tags}, _, _) ->
  [Tag || {tag, _, _} = Tag <- Tags];
apply_trim(Index, {text, Text, {Line, Column}}, Leading, Trailing) ->
  From =
    case lists:member(Index, Leading) of
      true ->
        case binary:match(Text, <<"\n">>) of
          {First, 1} -> First + 1;
          nomatch -> byte_size(Text)
        end;
      false ->
        0
    end,
  To =
    case lists:member(Index, Trailing) of
      true ->
        case last_newline(Text) of
          nomatch -> 0;
          Last -> Last + 1
        end;
      false ->
        byte_size(Text)
    end,
  case To > From of
    true ->
      Pos = advance(binary:part(Text, 0, From), Line, Column),
      [{text, binary:part(Text, From, To - From), Pos}];
    false ->
      []
  end.

%%%===================================================================
%%% Parser
%%%===================================================================

parse(Items, Cfg) ->
  case parse_block(Items, #{}, Cfg, []) of
    {Nodes, eof, []} -> Nodes;
    {_, {Stop, Pos}, _} -> ?THROW({unexpected_tag, stop_name(Stop)}, Pos)
  end.

parse_block([], _, _, Accumulator) ->
  {lists:reverse(Accumulator), eof, []};
parse_block([{text, Text, Pos} | Rest], Scope, Cfg, Accumulator) ->
  parse_block(Rest, Scope, Cfg, [{text, Text, Pos} | Accumulator]);
parse_block([{tag, Tokens, Pos} | Rest], Scope, Cfg, Accumulator) ->
  case statement(Tokens, Scope, Cfg) of
    {output, Expression} ->
      parse_block(Rest, Scope, Cfg, [{output, Expression, Pos} | Accumulator]);
    {include, Name, Argument} ->
      parse_block(Rest, Scope, Cfg, [{include, Name, Argument, Pos} | Accumulator]);
    {'if', Condition} ->
      {Node, Rest1} = parse_if(Rest, [], Condition, Pos, Scope, Cfg),
      parse_block(Rest1, Scope, Cfg, [Node | Accumulator]);
    {for, Key, Value, Expression} ->
      {Node, Rest1} = parse_for(Rest, Key, Value, Expression, Pos, Scope, Cfg),
      parse_block(Rest1, Scope, Cfg, [Node | Accumulator]);
    {'case', Expression} ->
      {Node, Rest1} = parse_case(Rest, Expression, Pos, Scope, Cfg),
      parse_block(Rest1, Scope, Cfg, [Node | Accumulator]);
    Stop ->
      {lists:reverse(Accumulator), {Stop, Pos}, Rest}
  end.

parse_if(Items, Clauses, Condition, OpenPos, Scope, Cfg) ->
  {Body, Stop, Rest} = parse_block(Items, Scope, Cfg, []),
  Clauses1 = [{Condition, Body} | Clauses],
  case Stop of
    {{else_if, Condition1}, _} ->
      parse_if(Rest, Clauses1, Condition1, OpenPos, Scope, Cfg);
    {'else', _} ->
      {Else, Stop1, Rest1} = parse_block(Rest, Scope, Cfg, []),
      expect_end(Stop1, 'if', OpenPos),
      {{'if', lists:reverse(Clauses1), Else}, Rest1};
    _ ->
      expect_end(Stop, 'if', OpenPos),
      {{'if', lists:reverse(Clauses1), []}, Rest}
  end.

parse_for(Items, Key, Value, Expression, OpenPos, Scope, Cfg) ->
  Scope1 = Scope#{<<"loop">> => loop},
  Scope2 =
    case Key of
      undefined -> Scope1#{Value => var};
      _ -> Scope1#{Key => var, Value => var}
    end,
  {Body, Stop, Rest} = parse_block(Items, Scope2, Cfg, []),
  {Else, Rest2} =
    case Stop of
      {'else', _} ->
        {Else1, Stop1, Rest1} = parse_block(Rest, Scope, Cfg, []),
        expect_end(Stop1, for, OpenPos),
        {Else1, Rest1};
      _ ->
        expect_end(Stop, for, OpenPos),
        {[], Rest}
    end,
  {{for, Key, Value, Expression, Body, Else, uses_loop(Body), OpenPos}, Rest2}.

parse_case(Items, Expression, OpenPos, Scope, Cfg) ->
  {Before, Stop, Rest} = parse_block(Items, Scope, Cfg, []),
  lists:foreach(
    fun
      ({text, Text, Pos}) ->
        case whitespace(Text) of
          true -> ok;
          false -> ?THROW(content_before_when, Pos)
        end;
      (Node) ->
        ?THROW(content_before_when, node_pos(Node, OpenPos))
    end,
    Before
  ),
  case Stop of
    {{'when', Values}, _} ->
      parse_when(Rest, Values, [], Expression, OpenPos, Scope, Cfg);
    {'else', _} ->
      {Else, Stop1, Rest1} = parse_block(Rest, Scope, Cfg, []),
      expect_end(Stop1, 'case', OpenPos),
      {{'case', Expression, [], Else}, Rest1};
    _ ->
      expect_end(Stop, 'case', OpenPos),
      {{'case', Expression, [], []}, Rest}
  end.

parse_when(Items, Values, Whens, Expression, OpenPos, Scope, Cfg) ->
  {Body, Stop, Rest} = parse_block(Items, Scope, Cfg, []),
  Whens1 = [{Values, Body} | Whens],
  case Stop of
    {{'when', Values1}, _} ->
      parse_when(Rest, Values1, Whens1, Expression, OpenPos, Scope, Cfg);
    {'else', _} ->
      {Else, Stop1, Rest1} = parse_block(Rest, Scope, Cfg, []),
      expect_end(Stop1, 'case', OpenPos),
      {{'case', Expression, lists:reverse(Whens1), Else}, Rest1};
    _ ->
      expect_end(Stop, 'case', OpenPos),
      {{'case', Expression, lists:reverse(Whens1), []}, Rest}
  end.

node_pos({output, _, Pos}, _) -> Pos;
node_pos({include, _, _, Pos}, _) -> Pos;
node_pos({for, _, _, _, _, _, _, Pos}, _) -> Pos;
node_pos(_, Default) -> Default.

whitespace(<<Char, Rest/binary>>) when Char =:= $\s; Char =:= $\t; Char =:= $\r; Char =:= $\n ->
  whitespace(Rest);
whitespace(<<>>) -> true;
whitespace(_) -> false.

expect_end({'end', _}, _, _) -> ok;
expect_end(eof, Block, OpenPos) -> ?THROW({unclosed_block, Block}, OpenPos);
expect_end({Stop, Pos}, _, _) -> ?THROW({unexpected_tag, stop_name(Stop)}, Pos).

stop_name({else_if, _}) -> 'else if';
stop_name({'when', _}) -> 'when';
stop_name(Stop) -> Stop.

statement([{eot, _, Pos}], _, _) ->
  ?THROW(empty_tag, Pos);
statement([{kw, 'if', _} | Tokens], Scope, Cfg) ->
  {'if', expression(Tokens, Scope, Cfg)};
statement([{kw, 'else', _}, {kw, 'if', _} | Tokens], Scope, Cfg) ->
  {else_if, expression(Tokens, Scope, Cfg)};
statement([{kw, 'else', _}, {eot, _, _}], _, _) ->
  'else';
statement([{kw, 'end', _}, {eot, _, _}], _, _) ->
  'end';
statement([{kw, Keyword, _}, Token | _], _, _) when Keyword =:= 'else'; Keyword =:= 'end' ->
  unexpected(Token);
statement([{kw, for, _} | Tokens], Scope, Cfg) ->
  for_header(Tokens, Scope, Cfg);
statement([{kw, 'case', _} | Tokens], Scope, Cfg) ->
  {'case', expression(Tokens, Scope, Cfg)};
statement([{kw, 'when', _} | Tokens], Scope, Cfg) ->
  {'when', expression_list(Tokens, Scope, Cfg, [])};
statement([{kw, include, _}, {str, Name, _}, {eot, _, _}], _, _) ->
  {include, Name, none};
statement([{kw, include, _}, {str, Name, _} | Tokens], Scope, Cfg) ->
  {include, Name, expression(Tokens, Scope, Cfg)};
statement([{kw, include, _}, Token | _], _, _) ->
  unexpected(Token);
statement(Tokens, Scope, Cfg) ->
  {output, expression(Tokens, Scope, Cfg)}.

for_header([{ident, First, _} | Tokens], Scope, Cfg) ->
  case Tokens of
    [{kw, in, _} | Rest] ->
      {for, undefined, First, expression(Rest, Scope, Cfg)};
    [{punct, ',', _}, {ident, Second, _}, {kw, in, _} | Rest] ->
      {for, First, Second, expression(Rest, Scope, Cfg)};
    [{punct, ',', _}, {ident, _, _}, Token | _] ->
      unexpected(Token);
    [{punct, ',', _}, Token | _] ->
      unexpected(Token);
    [Token | _] ->
      unexpected(Token)
  end;
for_header([Token | _], _, _) ->
  unexpected(Token).

expression(Tokens, Scope, Cfg) ->
  case parse_or(Tokens, Scope, Cfg) of
    {Expression, [{eot, _, _}]} -> Expression;
    {_, [Token | _]} -> unexpected(Token)
  end.

expression_list(Tokens, Scope, Cfg, Accumulator) ->
  case parse_or(Tokens, Scope, Cfg) of
    {Expression, [{eot, _, _}]} -> lists:reverse([Expression | Accumulator]);
    {Expression, [{punct, ',', _} | Rest]} -> expression_list(Rest, Scope, Cfg, [Expression | Accumulator]);
    {_, [Token | _]} -> unexpected(Token)
  end.

unexpected({eot, _, Pos}) -> ?THROW(unexpected_end_of_expression, Pos);
unexpected({_, _, Pos} = Token) -> ?THROW({unexpected_token, token_text(Token)}, Pos).

token_text({ident, Name, _}) -> Name;
token_text({str, String, _}) -> <<"\"", String/binary, "\"">>;
token_text({int, Integer, _}) -> integer_to_binary(Integer);
token_text({float, Float, _}) -> float_text(Float);
token_text({_, Atom, _}) -> atom_to_binary(Atom, utf8).

parse_or(Tokens, Scope, Cfg) ->
  {Left, Rest} = parse_and(Tokens, Scope, Cfg),
  parse_or_rest(Left, Rest, Scope, Cfg).

parse_or_rest(Left, [{kw, 'or', _} | Tokens], Scope, Cfg) ->
  {Right, Rest} = parse_and(Tokens, Scope, Cfg),
  parse_or_rest({'or', Left, Right}, Rest, Scope, Cfg);
parse_or_rest(Left, Tokens, _, _) ->
  {Left, Tokens}.

parse_and(Tokens, Scope, Cfg) ->
  {Left, Rest} = parse_not(Tokens, Scope, Cfg),
  parse_and_rest(Left, Rest, Scope, Cfg).

parse_and_rest(Left, [{kw, 'and', _} | Tokens], Scope, Cfg) ->
  {Right, Rest} = parse_not(Tokens, Scope, Cfg),
  parse_and_rest({'and', Left, Right}, Rest, Scope, Cfg);
parse_and_rest(Left, Tokens, _, _) ->
  {Left, Tokens}.

parse_not([{kw, 'not', _} | Tokens], Scope, Cfg) ->
  {Expression, Rest} = parse_not(Tokens, Scope, Cfg),
  {{'not', Expression}, Rest};
parse_not(Tokens, Scope, Cfg) ->
  parse_compare(Tokens, Scope, Cfg).

parse_compare(Tokens, Scope, Cfg) ->
  {Left, Rest} = parse_postfix(Tokens, Scope, Cfg),
  case Rest of
    [{punct, Operator, Pos} | Rest1]
        when Operator =:= '=='; Operator =:= '!='; Operator =:= '<';
             Operator =:= '<='; Operator =:= '>'; Operator =:= '>=' ->
      {Right, Rest2} = parse_postfix(Rest1, Scope, Cfg),
      {{compare, Operator, Left, Right, Pos}, Rest2};
    _ ->
      {Left, Rest}
  end.

parse_postfix(Tokens, Scope, Cfg) ->
  {Expression, Rest} = parse_primary(Tokens, Scope, Cfg),
  parse_pipes(Expression, Rest, Scope, Cfg).

parse_pipes(Expression, [{punct, '|', _}, {ident, Name, Pos}, {punct, '(', _} | Tokens], Scope, Cfg) ->
  {Arguments, Rest} = arguments(Tokens, Scope, Cfg),
  parse_pipes(make_call(Name, [Expression | Arguments], Pos, Cfg), Rest, Scope, Cfg);
parse_pipes(Expression, [{punct, '|', _}, {ident, Name, Pos} | Tokens], Scope, Cfg) ->
  parse_pipes(make_call(Name, [Expression], Pos, Cfg), Tokens, Scope, Cfg);
parse_pipes(_, [{punct, '|', _}, Token | _], _, _) ->
  unexpected(Token);
parse_pipes(Expression, Tokens, _, _) ->
  {Expression, Tokens}.

arguments([{punct, ')', _} | Rest], _, _) ->
  {[], Rest};
arguments(Tokens, Scope, Cfg) ->
  arguments(Tokens, Scope, Cfg, []).

arguments(Tokens, Scope, Cfg, Accumulator) ->
  case parse_or(Tokens, Scope, Cfg) of
    {Expression, [{punct, ',', _} | Rest]} -> arguments(Rest, Scope, Cfg, [Expression | Accumulator]);
    {Expression, [{punct, ')', _} | Rest]} -> {lists:reverse([Expression | Accumulator]), Rest};
    {_, [Token | _]} -> unexpected(Token)
  end.

parse_primary([{str, String, _} | Rest], _, _) ->
  {{literal, String}, Rest};
parse_primary([{Type, Number, _} | Rest], _, _) when Type =:= int; Type =:= float ->
  {{literal, Number}, Rest};
parse_primary([{kw, Boolean, _} | Rest], _, _) when Boolean =:= true; Boolean =:= false ->
  {{literal, Boolean}, Rest};
parse_primary([{kw, nil, _} | Rest], _, _) ->
  {{literal, undefined}, Rest};
parse_primary([{punct, '(', _} | Tokens], Scope, Cfg) ->
  case parse_or(Tokens, Scope, Cfg) of
    {Expression, [{punct, ')', _} | Rest]} -> {Expression, Rest};
    {_, [Token | _]} -> unexpected(Token)
  end;
parse_primary([{ident, Name, Pos}, {punct, '(', _} | Tokens], Scope, Cfg) ->
  {Arguments, Rest} = arguments(Tokens, Scope, Cfg),
  {make_call(Name, Arguments, Pos, Cfg), Rest};
parse_primary([{ident, Name, Pos} | Tokens], Scope, Cfg) ->
  parse_path(Name, Pos, Tokens, Scope, Cfg);
parse_primary([{kw, Keyword, Pos} | _], _, _) ->
  ?THROW({reserved_word, Keyword}, Pos);
parse_primary([Token | _], _, _) ->
  unexpected(Token).

parse_path(Name, Pos, Tokens, Scope, Cfg) ->
  {Segments, Rest} = segments(Tokens, []),
  Text = iolist_to_binary([Name | [segment_text(Segment) || Segment <- Segments]]),
  Path =
    case maps:find(Name, Scope) of
      {ok, var} ->
        {path, {local, Name}, convert_segments(Segments, Pos, Cfg), Text, Pos};
      {ok, loop} ->
        case Segments of
          [{name, Field, dot} | More] ->
            case loop_field(Field) of
              undefined -> ?THROW({unknown_loop_field, Field}, Pos);
              Atom -> {path, {loop, Atom}, convert_segments(More, Pos, Cfg), Text, Pos}
            end;
          _ ->
            ?THROW({unknown_loop_field, <<>>}, Pos)
        end;
      error ->
        {path, data, convert_segments([{name, Name, dot} | Segments], Pos, Cfg), Text, Pos}
    end,
  {Path, Rest}.

segments([{punct, '.', _}, {ident, Name, _} | Rest], Accumulator) ->
  segments(Rest, [{name, Name, dot} | Accumulator]);
segments([{punct, '.', _}, {kw, Keyword, _} | Rest], Accumulator) ->
  segments(Rest, [{name, atom_to_binary(Keyword, utf8), dot} | Accumulator]);
segments([{punct, '.', _}, Token | _], _) ->
  unexpected(Token);
segments([{punct, '[', _}, {str, Key, _}, {punct, ']', _} | Rest], Accumulator) ->
  segments(Rest, [{name, Key, bracket} | Accumulator]);
segments([{punct, '[', _}, {int, Index, _}, {punct, ']', _} | Rest], Accumulator) ->
  segments(Rest, [{index, Index} | Accumulator]);
segments([{punct, '[', _}, {Type, _, _}, Token | _], _) when Type =:= str; Type =:= int ->
  unexpected(Token);
segments([{punct, '[', _}, Token | _], _) ->
  unexpected(Token);
segments(Tokens, Accumulator) ->
  {lists:reverse(Accumulator), Tokens}.

segment_text({name, Name, dot}) -> [$., Name];
segment_text({name, Name, bracket}) -> ["[\"", Name, "\"]"];
segment_text({index, Index}) -> [$[, integer_to_binary(Index), $]].

loop_field(<<"index">>) -> index;
loop_field(<<"index0">>) -> index0;
loop_field(<<"first">>) -> first;
loop_field(<<"last">>) -> last;
loop_field(<<"length">>) -> length;
loop_field(_) -> undefined.

convert_segments(Segments, Pos, Cfg) ->
  [convert_segment(Segment, Pos, Cfg) || Segment <- Segments].

convert_segment({index, Index}, _, _) ->
  {index, Index};
convert_segment({name, Name, _}, _, #cfg{keys = atom}) ->
  try binary_to_existing_atom(Name, utf8) of
    Atom -> {key, Atom}
  catch
    error:badarg -> {late_atom, Name}
  end;
convert_segment({name, Name, _}, _, #cfg{keys = binary}) ->
  {key, Name};
convert_segment({name, Name, _}, _, #cfg{keys = string}) ->
  case unicode:characters_to_list(Name) of
    String when is_list(String) -> {key, String};
    _ -> {key, binary_to_list(Name)}
  end;
convert_segment({name, Name, _}, Pos, #cfg{keys = Fun}) ->
  try Fun(Name) of
    Key -> {key, Key}
  catch
    Class:Reason -> ?THROW({function_crashed, keys, Class, Reason}, Pos)
  end.

make_call(Name, Arguments, Pos, #cfg{functions = Functions}) ->
  Count = length(Arguments),
  case maps:find(Name, Functions) of
    {ok, {_, _, Arity}} when Arity =/= Count ->
      ?THROW({bad_arity, Name, Arity, Count}, Pos);
    {ok, {special, raw, _}} ->
      {raw, hd(Arguments)};
    {ok, {special, default, _}} ->
      [Value, Default] = Arguments,
      {default, Value, Default};
    {ok, {special, defined, _}} ->
      {defined, hd(Arguments)};
    {ok, {builtin, Function, _}} ->
      {builtin, Name, Function, Arguments, Pos};
    {ok, {user, Fun, _}} ->
      {call, Name, Fun, Arguments, Pos};
    error ->
      ?THROW({unknown_function, Name}, Pos)
  end.

%% Whether a loop body reads `loop.*' of its own loop (nested loop bodies have their own).
uses_loop(Nodes) ->
  lists:any(fun node_uses_loop/1, Nodes).

node_uses_loop({output, Expression, _}) ->
  expression_uses_loop(Expression);
node_uses_loop({'if', Clauses, Else}) ->
  lists:any(fun({Condition, Body}) -> expression_uses_loop(Condition) orelse uses_loop(Body) end, Clauses)
    orelse uses_loop(Else);
node_uses_loop({for, _, _, Expression, _, Else, _, _}) ->
  expression_uses_loop(Expression) orelse uses_loop(Else);
node_uses_loop({'case', Expression, Whens, Else}) ->
  expression_uses_loop(Expression) orelse
    lists:any(
      fun({Values, Body}) -> lists:any(fun expression_uses_loop/1, Values) orelse uses_loop(Body) end,
      Whens
    ) orelse
    uses_loop(Else);
node_uses_loop({include, _, none, _}) ->
  false;
node_uses_loop({include, _, Argument, _}) ->
  expression_uses_loop(Argument);
node_uses_loop({text, _, _}) ->
  false.

expression_uses_loop({path, {loop, _}, _, _, _}) -> true;
expression_uses_loop({'not', Expression}) -> expression_uses_loop(Expression);
expression_uses_loop({'and', Left, Right}) -> expression_uses_loop(Left) orelse expression_uses_loop(Right);
expression_uses_loop({'or', Left, Right}) -> expression_uses_loop(Left) orelse expression_uses_loop(Right);
expression_uses_loop({compare, _, Left, Right, _}) -> expression_uses_loop(Left) orelse expression_uses_loop(Right);
expression_uses_loop({raw, Expression}) -> expression_uses_loop(Expression);
expression_uses_loop({default, Value, Default}) -> expression_uses_loop(Value) orelse expression_uses_loop(Default);
expression_uses_loop({defined, Expression}) -> expression_uses_loop(Expression);
expression_uses_loop({builtin, _, _, Arguments, _}) -> lists:any(fun expression_uses_loop/1, Arguments);
expression_uses_loop({call, _, _, Arguments, _}) -> lists:any(fun expression_uses_loop/1, Arguments);
expression_uses_loop(_) -> false.

%%%===================================================================
%%% Code generation
%%%===================================================================

%% A compiled node is either a constant binary or a `fun(Env) -> iodata()'.
gen_seq(Nodes, Cfg) ->
  case merge_parts([gen_node(Node, Cfg) || Node <- Nodes]) of
    [] -> <<>>;
    [Part] -> Part;
    Parts -> fun(Env) -> run_parts(Parts, Env) end
  end.

merge_parts([<<>> | Rest]) ->
  merge_parts(Rest);
merge_parts([Left, Right | Rest]) when is_binary(Left), is_binary(Right) ->
  merge_parts([<<Left/binary, Right/binary>> | Rest]);
merge_parts([Part | Rest]) ->
  [Part | merge_parts(Rest)];
merge_parts([]) ->
  [].

run_parts([Part | Rest], Env) when is_binary(Part) -> [Part | run_parts(Rest, Env)];
run_parts([Part | Rest], Env) -> [Part(Env) | run_parts(Rest, Env)];
run_parts([], _) -> [].

run(Part, _) when is_binary(Part) -> Part;
run(Part, Env) -> Part(Env).

gen_node({text, Text, _}, _) ->
  Text;
gen_node({output, {raw, Expression}, Pos}, Cfg) ->
  gen_text(Expression, Pos, Cfg);
gen_node({output, Expression, Pos}, #cfg{escape = none} = Cfg) ->
  gen_text(Expression, Pos, Cfg);
gen_node({output, Expression, Pos}, #cfg{escape = Escape} = Cfg) ->
  case gen_text(Expression, Pos, Cfg) of
    Text when is_binary(Text) -> fun(_) -> escape(Escape, Text, Pos) end;
    Fun -> fun(Env) -> escape(Escape, Fun(Env), Pos) end
  end;
gen_node({'if', Clauses, Else}, Cfg) ->
  case fold_if(Clauses, []) of
    {static, Body} ->
      gen_seq(Body, Cfg);
    {[], keep} ->
      gen_seq(Else, Cfg);
    {Dynamic, Else1} ->
      Compiled = [{gen_expr(Condition, Cfg), gen_seq(Body, Cfg)} || {Condition, Body} <- Dynamic],
      ElseFun =
        case Else1 of
          keep -> gen_seq(Else, Cfg);
          {replace, Body} -> gen_seq(Body, Cfg)
        end,
      fun(Env) -> run_if(Compiled, ElseFun, Env) end
  end;
gen_node({for, Key, Value, Expression, Body, Else, UsesLoop, Pos}, Cfg) ->
  Collection = gen_expr(Expression, Cfg),
  Loop = {Key, Value, gen_seq(Body, Cfg), UsesLoop},
  ElseFun = gen_seq(Else, Cfg),
  fun(Env) -> run_for(Collection(Env), Loop, ElseFun, Pos, Env) end;
gen_node({'case', Expression, Whens, Else}, Cfg) ->
  Subject = gen_expr(Expression, Cfg),
  Compiled = [{[gen_expr(V, Cfg) || V <- Values], gen_seq(Body, Cfg)} || {Values, Body} <- Whens],
  ElseFun = gen_seq(Else, Cfg),
  fun(Env) -> run_case(Subject(Env), Compiled, ElseFun, Env) end;
gen_node({include, Name, none, Pos}, _) ->
  fun(Env) -> run_include(Name, none, Pos, Env) end;
gen_node({include, Name, Argument, Pos}, Cfg) ->
  Fun = gen_expr(Argument, Cfg),
  fun(Env) -> run_include(Name, Fun, Pos, Env) end.

gen_text({literal, Value}, Pos, _) ->
  to_text(Value, Pos);
gen_text(Expression, Pos, Cfg) ->
  Fun = gen_expr(Expression, Cfg),
  fun(Env) -> to_text(Fun(Env), Pos) end.

%% Drops `if' clauses with a literal condition that is falsy; a literal truthy condition
%% becomes the else branch (or the whole node when it is the first clause).
fold_if([{{literal, Value}, Body} | Rest], Dynamic) ->
  case {truthy(Value), Dynamic} of
    {true, []} -> {static, Body};
    {true, _} -> {lists:reverse(Dynamic), {replace, Body}};
    {false, _} -> fold_if(Rest, Dynamic)
  end;
fold_if([Clause | Rest], Dynamic) ->
  fold_if(Rest, [Clause | Dynamic]);
fold_if([], Dynamic) ->
  {lists:reverse(Dynamic), keep}.

gen_expr({literal, Value}, _) ->
  fun(_) -> Value end;
gen_expr({path, data, [{key, Key}] = Segments, Text, Pos}, _) ->
  fun(#env{data = Data} = Env) ->
    case Data of
      #{Key := Value} -> Value;
      _ -> walk(Data, Segments, Text, Pos, Env)
    end
  end;
gen_expr({path, data, Segments, Text, Pos}, _) ->
  fun(#env{data = Data} = Env) -> walk(Data, Segments, Text, Pos, Env) end;
gen_expr({path, {local, Name}, Segments, Text, Pos}, _) ->
  fun(#env{vars = Vars} = Env) -> walk(maps:get(Name, Vars), Segments, Text, Pos, Env) end;
gen_expr({path, {loop, Field}, Segments, Text, Pos}, _) ->
  fun(#env{loop = Loop} = Env) -> walk(loop_value(Field, Loop), Segments, Text, Pos, Env) end;
gen_expr({'not', Expression}, Cfg) ->
  Fun = gen_expr(Expression, Cfg),
  fun(Env) -> not truthy(Fun(Env)) end;
gen_expr({'and', Left, Right}, Cfg) ->
  LeftFun = gen_expr(Left, Cfg),
  RightFun = gen_expr(Right, Cfg),
  fun(Env) ->
    Value = LeftFun(Env),
    case truthy(Value) of
      true -> RightFun(Env);
      false -> Value
    end
  end;
gen_expr({'or', Left, Right}, Cfg) ->
  LeftFun = gen_expr(Left, Cfg),
  RightFun = gen_expr(Right, Cfg),
  fun(Env) ->
    Value = LeftFun(Env),
    case truthy(Value) of
      true -> Value;
      false -> RightFun(Env)
    end
  end;
gen_expr({compare, Operator, Left, Right, Pos}, Cfg) ->
  LeftFun = gen_expr(Left, Cfg),
  RightFun = gen_expr(Right, Cfg),
  fun(Env) -> compare(Operator, LeftFun(Env), RightFun(Env), Pos) end;
gen_expr({raw, Expression}, Cfg) ->
  gen_expr(Expression, Cfg);
gen_expr({default, Value, Default}, Cfg) ->
  ValueFun = gen_expr(Value, Cfg),
  DefaultFun = gen_expr(Default, Cfg),
  fun(Env) ->
    try ValueFun(Env#env{missing = error}) of
      Result ->
        case nil(Result) of
          true -> DefaultFun(Env);
          false -> Result
        end
    catch
      throw:{dew_tpl, {missing_key, _}, _} -> DefaultFun(Env)
    end
  end;
gen_expr({defined, Expression}, Cfg) ->
  Fun = gen_expr(Expression, Cfg),
  fun(Env) ->
    try Fun(Env#env{missing = error}) of
      _ -> true
    catch
      throw:{dew_tpl, {missing_key, _}, _} -> false
    end
  end;
gen_expr({builtin, Name, Function, Arguments, Pos}, Cfg) ->
  Funs = [gen_expr(Argument, Cfg) || Argument <- Arguments],
  fun(Env) -> call_builtin(Function, Name, [Fun(Env) || Fun <- Funs], Pos) end;
gen_expr({call, Name, UserFun, Arguments, Pos}, Cfg) ->
  Funs = [gen_expr(Argument, Cfg) || Argument <- Arguments],
  fun(Env) -> call_user(Name, UserFun, [Fun(Env) || Fun <- Funs], Pos) end.

%%%===================================================================
%%% Runtime
%%%===================================================================

output(IoData, iodata, _) ->
  {ok, IoData};
output(IoData, binary, Name) ->
  try iolist_to_binary(IoData) of
    Binary -> {ok, Binary}
  catch
    error:badarg ->
      case chars_to_binary(IoData) of
        {ok, Binary} -> {ok, Binary};
        error -> {error, make_error(render, invalid_output, nopos, Name)}
      end
  end.

escape(Escape, Text, Pos) ->
  try
    Escape(Text)
  catch
    Class:Reason -> ?THROW({function_crashed, escape_fun, Class, Reason}, Pos)
  end.

run_if([{Condition, Body} | Rest], Else, Env) ->
  case truthy(Condition(Env)) of
    true -> run(Body, Env);
    false -> run_if(Rest, Else, Env)
  end;
run_if([], Else, Env) ->
  run(Else, Env).

run_for([_ | _] = List, {_, _, _, UsesLoop} = Loop, _, _, Env) ->
  Length =
    case UsesLoop of
      true -> length(List);
      false -> undefined
    end,
  for_list(List, 0, Length, Loop, Env);
run_for(Map, Loop, _, _, Env) when is_map(Map), map_size(Map) > 0 ->
  for_map(lists:sort(maps:to_list(Map)), 0, map_size(Map), Loop, Env);
run_for(Collection, _, Else, Pos, Env) ->
  case Collection =:= [] orelse is_map(Collection) orelse nil(Collection) of
    true -> run(Else, Env);
    false -> ?THROW({not_iterable, Collection}, Pos)
  end.

for_list([Item | Rest], Index, Length, Loop, Env) ->
  [iteration(Index, Item, Index, Length, Loop, Env) | for_list(Rest, Index + 1, Length, Loop, Env)];
for_list(_, _, _, _, _) ->
  [].

for_map([{Key, Value} | Rest], Index, Length, Loop, Env) ->
  [iteration(Key, Value, Index, Length, Loop, Env) | for_map(Rest, Index + 1, Length, Loop, Env)];
for_map([], _, _, _, _) ->
  [].

iteration(KeyValue, Item, Index, Length, {Key, Value, Body, UsesLoop}, #env{vars = Vars} = Env) ->
  Vars1 =
    case Key of
      undefined -> Vars#{Value => Item};
      _ -> Vars#{Key => KeyValue, Value => Item}
    end,
  Env1 =
    case UsesLoop of
      true -> Env#env{vars = Vars1, loop = {Index, Length}};
      false -> Env#env{vars = Vars1}
    end,
  run(Body, Env1).

loop_value(index, {Index, _}) -> Index + 1;
loop_value(index0, {Index, _}) -> Index;
loop_value(first, {Index, _}) -> Index =:= 0;
loop_value(last, {Index, Length}) -> Index =:= Length - 1;
loop_value(length, {_, Length}) -> Length.

run_case(Subject, [{Values, Body} | Rest], Else, Env) ->
  case lists:any(fun(Value) -> equal(Subject, Value(Env)) end, Values) of
    true -> run(Body, Env);
    false -> run_case(Subject, Rest, Else, Env)
  end;
run_case(_, [], Else, Env) ->
  run(Else, Env).

run_include(_, _, Pos, #env{depth = Depth, max_depth = Max}) when Depth >= Max ->
  ?THROW(include_depth_exceeded, Pos);
run_include(Name, Argument, Pos, #env{partials = Partials} = Env) ->
  case maps:find(Name, Partials) of
    {ok, {dew_tpl, _, _, Fun}} ->
      Data =
        case Argument of
          none -> Env#env.data;
          _ -> Argument(Env)
        end,
      Env1 = Env#env{data = Data, vars = #{}, loop = undefined, depth = Env#env.depth + 1},
      try
        run(Fun, Env1)
      catch
        throw:{dew_tpl, Reason, ErrorPos} ->
          throw({dew_tpl_error, push_include(Name, make_error(render, Reason, ErrorPos, Name))});
        throw:{dew_tpl_error, Error} ->
          throw({dew_tpl_error, push_include(Name, Error)})
      end;
    {ok, {error, Error}} ->
      throw({dew_tpl_error, push_include(Name, Error)});
    error ->
      ?THROW({partial_not_found, Name}, Pos)
  end.

push_include(Name, Error) ->
  Error#{include_stack => [Name | maps:get(include_stack, Error, [])]}.

walk(Value, [], _, _, _) ->
  Value;
walk(Value, [Segment | Rest], Text, Pos, Env) ->
  case step(Value, Segment) of
    {ok, Next} -> walk(Next, Rest, Text, Pos, Env);
    missing -> missing(Text, Pos, Env);
    inaccessible -> ?THROW({not_accessible, Text, Value}, Pos)
  end.

missing(_, _, #env{missing = empty}) -> undefined;
missing(Text, Pos, _) -> ?THROW({missing_key, Text}, Pos).

step(Map, {key, Key}) when is_map(Map) ->
  case Map of
    #{Key := Value} -> {ok, Value};
    _ -> missing
  end;
step(List, {key, Key}) when is_list(List) ->
  try lists:keyfind(Key, 1, List) of
    {_, Value} -> {ok, Value};
    _ -> missing
  catch
    error:_ -> inaccessible
  end;
step(Value, {late_atom, Name}) ->
  try binary_to_existing_atom(Name, utf8) of
    Atom -> step(Value, {key, Atom})
  catch
    error:badarg when is_map(Value); is_list(Value) -> missing;
    error:badarg -> step(Value, nothing)
  end;
step(List, {index, Index}) when is_list(List) ->
  nth(List, Index);
step(Map, {index, Index}) when is_map(Map) ->
  case Map of
    #{Index := Value} -> {ok, Value};
    _ -> missing
  end;
step(Tuple, {index, Index}) when is_tuple(Tuple), Index >= 0, Index < tuple_size(Tuple) ->
  {ok, element(Index + 1, Tuple)};
step(Tuple, {index, _}) when is_tuple(Tuple) ->
  missing;
step(Value, _) ->
  case nil(Value) of
    true -> missing;
    false -> inaccessible
  end.

nth(_, Index) when Index < 0 -> missing;
nth([Value | _], 0) -> {ok, Value};
nth([_ | Rest], Index) -> nth(Rest, Index - 1);
nth(_, _) -> missing.

nil(undefined) -> true;
nil(nil) -> true;
nil(null) -> true;
nil(_) -> false.

truthy(false) -> false;
truthy(undefined) -> false;
truthy(nil) -> false;
truthy(null) -> false;
truthy([]) -> false;
truthy(<<>>) -> false;
truthy(Map) when is_map(Map), map_size(Map) =:= 0 -> false;
truthy(_) -> true.

to_text(Value, _) when is_binary(Value) -> Value;
to_text(Value, _) when is_integer(Value) -> integer_to_binary(Value);
to_text(Value, _) when is_float(Value) -> float_text(Value);
to_text(Value, _) when Value =:= undefined; Value =:= nil; Value =:= null -> <<>>;
to_text(Value, _) when is_atom(Value) -> atom_to_binary(Value, utf8);
to_text(Value, Pos) when is_list(Value) ->
  case chars_to_binary(Value) of
    {ok, Binary} -> Binary;
    error -> ?THROW({unrenderable_value, Value}, Pos)
  end;
to_text(Value, Pos) ->
  ?THROW({unrenderable_value, Value}, Pos).

float_text(Float) ->
  list_to_binary(io_lib_format:fwrite_g(Float)).

%% Text form used by comparisons: binaries, charlists and atoms other than booleans and nil.
text_value(Value) when is_binary(Value) -> {ok, Value};
text_value(Value) when is_boolean(Value) -> error;
text_value(Value) when is_atom(Value) ->
  case nil(Value) of
    true -> error;
    false -> {ok, atom_to_binary(Value, utf8)}
  end;
text_value(Value) when is_list(Value) -> chars_to_binary(Value);
text_value(_) -> error.

equal(Value, Value) ->
  true;
equal(Left, Right) when is_number(Left), is_number(Right) ->
  Left == Right;
equal(Left, Right) ->
  case nil(Left) orelse nil(Right) of
    true ->
      nil(Left) andalso nil(Right);
    false ->
      case {text_value(Left), text_value(Right)} of
        {{ok, Text}, {ok, Text}} -> true;
        _ -> false
      end
  end.

compare('==', Left, Right, _) ->
  equal(Left, Right);
compare('!=', Left, Right, _) ->
  not equal(Left, Right);
compare(Operator, Left, Right, _) when is_number(Left), is_number(Right) ->
  order(Operator, Left, Right);
compare(Operator, Left, Right, Pos) ->
  case {text_value(Left), text_value(Right)} of
    {{ok, LeftText}, {ok, RightText}} -> order(Operator, LeftText, RightText);
    _ -> ?THROW({type_mismatch, Operator, Left, Right}, Pos)
  end.

order('<', Left, Right) -> Left < Right;
order('<=', Left, Right) -> Left =< Right;
order('>', Left, Right) -> Left > Right;
order('>=', Left, Right) -> Left >= Right.

call_user(Name, Fun, Arguments, Pos) ->
  try erlang:apply(Fun, Arguments) of
    {error, Reason} -> ?THROW({function_error, Name, Reason}, Pos);
    Value -> Value
  catch
    Class:Reason -> ?THROW({function_crashed, Name, Class, Reason}, Pos)
  end.

call_builtin(Function, Name, Arguments, Pos) ->
  try
    builtin(Function, Arguments)
  catch
    throw:{bad_argument, Value} -> ?THROW({bad_argument, Name, Value}, Pos);
    throw:{dew_tpl, Reason, nopos} -> ?THROW(Reason, Pos);
    error:_ -> ?THROW({bad_argument, Name, Arguments}, Pos)
  end.

builtin(upper, [Value]) ->
  chars(string:uppercase(to_text(Value, nopos)));
builtin(lower, [Value]) ->
  chars(string:lowercase(to_text(Value, nopos)));
builtin(trim, [Value]) ->
  chars(string:trim(to_text(Value, nopos)));
builtin(length, [Value]) when is_binary(Value) ->
  string:length(Value);
builtin(length, [Value]) when is_list(Value) ->
  length(Value);
builtin(length, [Value]) when is_map(Value) ->
  map_size(Value);
builtin(length, [Value]) when is_tuple(Value) ->
  tuple_size(Value);
builtin(length, [Value]) ->
  case nil(Value) of
    true -> 0;
    false -> throw({bad_argument, Value})
  end;
builtin(join, [List, Separator]) when is_list(List) ->
  Texts = [to_text(Item, nopos) || Item <- List],
  iolist_to_binary(lists:join(to_text(Separator, nopos), Texts));
builtin(join, [Value, _]) ->
  throw({bad_argument, Value});
builtin(truncate, [Value, Length]) when is_integer(Length), Length >= 0 ->
  Text = to_text(Value, nopos),
  case string:length(Text) =< Length of
    true -> Text;
    false -> chars(string:slice(Text, 0, Length))
  end;
builtin(truncate, [_, Length]) ->
  throw({bad_argument, Length});
builtin(escape, [Value]) ->
  escape_html(to_text(Value, nopos)).

chars(Chars) ->
  case chars_to_binary(Chars) of
    {ok, Binary} -> Binary;
    error -> erlang:error(badarg)
  end.

escape_parts(Binary, From, [{Pos, 1} | Rest]) ->
  [binary:part(Binary, From, Pos - From), entity(binary:at(Binary, Pos)) | escape_parts(Binary, Pos + 1, Rest)];
escape_parts(Binary, From, []) ->
  [binary:part(Binary, From, byte_size(Binary) - From)].

entity($&) -> <<"&amp;">>;
entity($<) -> <<"&lt;">>;
entity($>) -> <<"&gt;">>;
entity($") -> <<"&quot;">>;
entity($') -> <<"&#39;">>.

%%%===================================================================
%%% Errors
%%%===================================================================

make_error(Phase, Reason, Pos, Name) ->
  Error0 = #{phase => Phase, reason => Reason},
  Error1 =
    case Pos of
      {Line, Column} -> Error0#{line => Line, column => Column};
      nopos -> Error0
    end,
  case Name of
    undefined -> Error1;
    _ -> Error1#{template => Name}
  end.

compile_error(Reason, Pos, Name, Source) ->
  Error = make_error(compile, Reason, Pos, Name),
  case Pos of
    {Line, _} ->
      case source_line(Source, Line) of
        undefined -> Error;
        Snippet -> Error#{snippet => Snippet}
      end;
    nopos ->
      Error
  end.

source_line(Source, Line) ->
  Lines = binary:split(Source, <<"\n">>, [global]),
  case Line =< length(Lines) of
    true ->
      Text = lists:nth(Line, Lines),
      case Text of
        <<Before:(byte_size(Text) - 1)/binary, "\r">> -> Before;
        _ -> Text
      end;
    false ->
      undefined
  end.

location(Error) ->
  Name =
    case Error of
      #{template := Template} -> [text(Template), ":"];
      _ -> []
    end,
  Position =
    case Error of
      #{line := Line, column := Column} -> [integer_to_list(Line), ":", integer_to_list(Column), ":"];
      _ -> []
    end,
  case [Name, Position] of
    [[], []] -> [];
    Location -> [Location, " "]
  end.

caret_padding(Line, Count) ->
  caret_padding(Line, Count, []).

caret_padding(_, Count, Accumulator) when Count =< 0 ->
  lists:reverse(Accumulator);
caret_padding(<<$\t, Rest/binary>>, Count, Accumulator) ->
  caret_padding(Rest, Count - 1, [$\t | Accumulator]);
caret_padding(<<Byte, Rest/binary>>, Count, Accumulator) when Byte band 16#C0 =:= 16#80 ->
  caret_padding(Rest, Count, Accumulator);
caret_padding(<<_, Rest/binary>>, Count, Accumulator) ->
  caret_padding(Rest, Count - 1, [$\s | Accumulator]);
caret_padding(<<>>, Count, Accumulator) ->
  caret_padding(<<>>, Count - 1, [$\s | Accumulator]).

message(unclosed_tag) ->
  "unclosed tag, missing '}}'";
message(unclosed_comment) ->
  "unclosed comment, missing '#}}'";
message({unexpected_character, Char}) ->
  ["unexpected character '", text(Char), "'"];
message(unterminated_string) ->
  "unterminated string literal";
message({unexpected_token, Token}) ->
  ["unexpected '", text(Token), "'"];
message(unexpected_end_of_expression) ->
  "unexpected end of expression";
message(empty_tag) ->
  "empty tag";
message({unclosed_block, Block}) ->
  ["'", atom_to_list(Block), "' block is never closed with {{ end }}"];
message({unexpected_tag, 'else'}) ->
  "'else' outside of an if, for or case block";
message({unexpected_tag, 'else if'}) ->
  "'else if' outside of an if block or after 'else'";
message({unexpected_tag, 'end'}) ->
  "'end' without an open block";
message({unexpected_tag, 'when'}) ->
  "'when' outside of a case block or after 'else'";
message({reserved_word, Word}) ->
  ["'", atom_to_list(Word), "' is a reserved word and cannot be used here"];
message({unknown_function, Name}) ->
  ["unknown function '", text(Name), "'"];
message({bad_arity, Name, Expected, Got}) ->
  io_lib:format("function '~ts' expects ~b argument(s), got ~b", [text(Name), Expected, Got]);
message({unknown_loop_field, <<>>}) ->
  "'loop' must be followed by a field: index, index0, first, last or length";
message({unknown_loop_field, Field}) ->
  ["unknown loop field '", text(Field), "', expected index, index0, first, last or length"];
message(content_before_when) ->
  "only whitespace is allowed between 'case' and the first 'when'";
message({invalid_option, Key, Value}) ->
  io_lib:format("invalid option ~tp => ~tP", [Key, Value, 10]);
message({invalid_source, Source}) ->
  io_lib:format("template source must be a binary or a string, got ~tP", [Source, 10]);
message({invalid_template, Template}) ->
  io_lib:format("not a template or template source: ~tP", [Template, 10]);
message({file, Posix}) ->
  ["cannot read file: ", file:format_error(Posix)];
message({missing_key, Path}) ->
  ["missing key '", text(Path), "'"];
message({not_accessible, Path, Value}) ->
  io_lib:format("cannot access '~ts' on ~tP", [text(Path), Value, 10]);
message({not_iterable, Value}) ->
  io_lib:format("cannot iterate over ~tP", [Value, 10]);
message({unrenderable_value, Value}) ->
  io_lib:format("cannot render ~tP as text", [Value, 10]);
message({type_mismatch, Operator, Left, Right}) ->
  io_lib:format("cannot compare ~tP ~s ~tP", [Left, 10, Operator, Right, 10]);
message({bad_argument, Name, Value}) ->
  io_lib:format("invalid argument for '~ts': ~tP", [text(Name), Value, 10]);
message({function_error, Name, Reason}) ->
  io_lib:format("function '~ts' returned an error: ~tP", [text(Name), Reason, 10]);
message({function_crashed, Name, Class, Reason}) ->
  io_lib:format("function '~ts' crashed with ~p:~tP", [text(Name), Class, Reason, 10]);
message({partial_not_found, Name}) ->
  ["partial '", text(Name), "' not found"];
message(include_depth_exceeded) ->
  "maximum include depth exceeded, is a partial including itself?";
message({bad_data, Data}) ->
  io_lib:format("data must be a map or a list, got ~tP", [Data, 10]);
message(invalid_output) ->
  "the escape function returned invalid iodata";
message({internal_error, Class, Reason}) ->
  io_lib:format("internal error ~p:~tP, please report this", [Class, Reason, 10]);
message(Reason) ->
  io_lib:format("~tP", [Reason, 10]).

%% Printable form of a binary or atom, falling back to the term form for invalid UTF-8.
text(Value) when is_atom(Value) ->
  atom_to_list(Value);
text(Value) when is_binary(Value) ->
  case unicode:characters_to_list(Value) of
    List when is_list(List) -> List;
    _ -> io_lib:format("~w", [Value])
  end;
text(Value) ->
  io_lib:format("~tP", [Value, 10]).

to_binary(Chars, Term) ->
  case chars_to_binary(Chars) of
    {ok, Binary} -> Binary;
    error -> list_to_binary(io_lib:format("~w", [Term]))
  end.
