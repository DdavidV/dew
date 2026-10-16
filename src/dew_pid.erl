-module(dew_pid).

%% Utility module for working with process identifiers.
%%
%% Provides functions to resolve process references to pids and to walk over every process on
%% the node.

-type pid_ref() :: pid() |
                   atom() |
                   {global, term()} |
                   {via, module(), term()} |
                   string() |
                   binary() |
                   {non_neg_integer(), non_neg_integer(), non_neg_integer()}.

-export_type([
  pid_ref/0
]).

-export([
  to_pid/1,
  fold/2
]).

%% Resolves a process reference to a pid.
%%
%% Accepts pids, locally registered names, `{global, Name}`, `{via, Module, Name}`, pid strings
%% and binaries like `"<0.42.0>"` and `{X, Y, Z}` triplets as used by `c:pid/3`.
%% Returns `undefined` if the reference can not be resolved.
-spec to_pid(PidRef) -> Result when
  PidRef :: pid_ref(),
  Result :: pid() | undefined.
to_pid(Pid) when is_pid(Pid) ->
  Pid;
to_pid(Name) when is_atom(Name) ->
  only_pid(erlang:whereis(Name));
to_pid({global, Name}) ->
  only_pid(global:whereis_name(Name));
to_pid({via, Module, Name}) ->
  only_pid(Module:whereis_name(Name));
to_pid({X, Y, Z}) when is_integer(X), is_integer(Y), is_integer(Z) ->
  to_pid(lists:flatten(io_lib:format("<~b.~b.~b>", [X, Y, Z])));
to_pid(Binary) when is_binary(Binary) ->
  to_pid(erlang:binary_to_list(Binary));
to_pid(String) when is_list(String) ->
  try
    erlang:list_to_pid(String)
  catch
    error:badarg -> undefined
  end;
to_pid(_) ->
  undefined.

only_pid(Pid) when is_pid(Pid) -> Pid;
only_pid(_) -> undefined.

%% Folds `Fun(Pid, Acc)` over every process on the node.
%%
%% Uses `erlang:processes_iterator/0` when available (OTP 28+), which avoids building the list of
%% every pid, and falls back to `erlang:processes/0` otherwise.
-spec fold(Fun, Acc) -> Result when
  Fun :: fun((pid(), Acc) -> Acc),
  Acc :: term(),
  Result :: term().
fold(Fun, Acc) ->
  case erlang:function_exported(erlang, processes_iterator, 0) of
    true ->
      fold_iterator(Fun, Acc, erlang:processes_iterator());
    false ->
      lists:foldl(Fun, Acc, erlang:processes())
  end.

fold_iterator(Fun, Acc, Iterator) ->
  case erlang:processes_next(Iterator) of
    {Pid, NextIterator} -> fold_iterator(Fun, Fun(Pid, Acc), NextIterator);
    none -> Acc
  end.
