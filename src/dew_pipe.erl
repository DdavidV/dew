-module(dew_pipe).

-export([
  tap/2,
  then/2
]).

-export([parse_transform/2]).

-spec tap(Value, Fun) -> Value when
  Value :: term(),
  Fun :: fun((Value) -> term()).
tap(Value, Fun) when is_function(Fun, 1) ->
  Fun(Value),
  Value.

-spec then(Value, Fun) -> Value when
  Value :: term(),
  Fun :: fun((Value) -> term()).
then(Value, Fun) when is_function(Fun, 1) ->
  Fun(Value).

-spec parse_transform(Forms, Options) -> Forms when
  Forms :: [erl_syntax:syntaxTree()],
  Options :: term().
parse_transform(Forms, _Options) ->
  SyntaxTree = erl_syntax:form_list(Forms),
  UpdatedSyntaxTree = erl_syntax_lib:map(fun transform/1, SyntaxTree),
  erl_syntax:revert_forms(UpdatedSyntaxTree).

transform(Node) ->
  case erl_syntax:type(Node) of
    application ->
      do_transform(Node);
    _ ->
      Node
  end.

do_transform(Node) ->
  case {is_pipe_operator(Node), erl_syntax:application_arguments(Node)} of
  {true, [_Value, _PipedCall | _] = Arguments} ->
    pipe_application(Node, Arguments);
  {true, Arguments} ->
    erlang:error({dew_pipe, {invalid_pipe_arity, length(Arguments)}});
  _ ->
    Node
  end.

pipe_application(Node, [Value | PipedCalls]) ->
  lists:foldl(
    fun(PipeCall, PreviousValue) ->
      pipe_stage(Node, PreviousValue, PipeCall)
    end, Value, PipedCalls).

pipe_stage(Node, Value, PipeCall) ->
  case erl_syntax:type(PipeCall) of
    application ->
      Operator = stage_operator(erl_syntax:application_operator(PipeCall)),
      Arguments = erl_syntax:application_arguments(PipeCall),
      NewNode = erl_syntax:application(Operator, [Value | Arguments]),
      erl_syntax:set_pos(NewNode, erl_syntax:get_pos(Node));
    _ ->
      erlang:error({dew_pipe, {invalid_pipe_target, erl_syntax:revert(PipeCall)}})
  end.

stage_operator(Operator) ->
  case erl_syntax:revert(Operator) of
    {atom, _, tap} ->
      dew_pipe_operator(tap);
    {atom, _, then} ->
      dew_pipe_operator(then);
    _ ->
      Operator
  end.

dew_pipe_operator(Function) ->
  erl_syntax:module_qualifier(erl_syntax:atom(dew_pipe), erl_syntax:atom(Function)).

is_pipe_operator(Node) ->
  case erl_syntax:revert(erl_syntax:application_operator(Node)) of
    {atom, _, pipe} ->
      true;
    {remote, _, {atom, _, dew_pipe}, {atom, _, pipe}} ->
      true;
    _ ->
      false
  end.
