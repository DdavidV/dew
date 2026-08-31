-module(dew_diff).

%% dew_diff compares Erlang terms and returns a compact list of structural operations describing
%% how to move from one value to another.
%%
%% The list diffing logic is based on the Longest Common Subsequence (LCS) algorithm.
%% For list inputs, a dynamic-programming matrix is built to measure how much of the old list still
%% matches the new list. The matrix is then backtracked to reconstruct a minimal edit script made of
%% add/remove/equal steps. Those steps are converted into the public diff entries.
%%
%% For maps, the implementation walks the old map entries and compares them to
%% the new map, emitting remove operations for keys that disappeared and add
%% operations for keys that were introduced. For non-list, non-map values, the
%% fallback is a single replace operation at the current path.

-type operation() :: add | remove | replace.

-type map_path() :: #{
  type := map,
  key := term()
}.

-type list_path() :: #{
  type := list,
  index := non_neg_integer()
}.

-type path() :: map_path() | list_path().

-type diff() :: #{
  path := [path()],
  operation := operation(),
  value := term(),
  old_value => term()
}.

-type diff_options() :: #{
  list => #{
    zero_based => boolean()
  }
}.

-type apply_diff_options() :: #{
  reverse => boolean()
}.

-export_type([
  operation/0,
  path/0,
  diff/0,
  diff_options/0,
  apply_diff_options/0
]).

%% Diff functions
-export([
  diff/2,
  diff/3,
  apply_diff/2,
  apply_diff/3,
  pretty_print/1
]).

%% Diff constructors
-export([
  %% Operation constructors
  make_add_op/2,
  make_remove_op/2,
  make_replace_op/3,
  %% Path constructors
  make_map_key/1,
  make_list_index/1
]).

-spec diff(Old, New) -> Diff when
  Old :: term(),
  New :: term(),
  Diff :: [diff()].
diff(Old, New) ->
  diff(Old, New, #{}).

-spec diff(Old, New, Options) -> Diff when
  Old :: term(),
  New :: term(),
  Options :: diff_options(),
  Diff :: [diff()].
diff(Old, New, Options) ->
  lists:reverse(diff(Old, New, Options, [], [])).

diff(Old, New, _Options, _Path, Diff) when Old =:= New ->
  Diff;
diff(Old, New, Options, Path, Diff) when is_map(Old) andalso is_map(New) ->
  AccDiff =
    maps:fold(
      fun(OldKey, OldValue, Acc) ->
        case maps:find(OldKey, New) of
          {ok, NewValue} ->
            diff(OldValue, NewValue, Options, Path ++ [#{type => map, key => OldKey}], Acc);
          error ->
            [make_remove_op(Path ++ [make_map_key(OldKey)], OldValue) | Acc]
        end
      end, Diff, Old),
  maps:fold(
    fun(NewKey, NewValue, Acc) ->
      [make_add_op(Path ++ [make_map_key(NewKey)], NewValue) | Acc]
    end, AccDiff, maps:without(maps:keys(Old), New));
diff(Old, New, Options, Path, Diff) when is_list(Old) andalso is_list(New) ->
  Matrix = lcs_matrix(Old, New),
  Edits = backtrack(Old, New, Matrix),
  ListOptions = maps:get(list, Options, #{}),
  FirstIndex =
    case maps:get(zero_based, ListOptions, true) of
      true -> 0;
      false -> 1
    end,
  edits_to_operations(Edits, Path, FirstIndex, Options, Diff);
diff(Old, New, _Options, Path, Diff) ->
  [make_replace_op(Path, Old, New) | Diff].

-spec make_add_op(Path, Value) -> DiffEntry when
  Path :: [path()],
  Value :: term(),
  DiffEntry :: diff().
make_add_op(Path, Value) ->
  #{operation => add, path => Path, value => Value}.

-spec make_remove_op(Path, Value) -> DiffEntry when
  Path :: [path()],
  Value :: term(),
  DiffEntry :: diff().
make_remove_op(Path, Value) ->
  #{operation => remove, path => Path, value => Value}.

-spec make_replace_op(Path, OldValue, NewValue) -> DiffEntry when
  Path :: [path()],
  OldValue :: term(),
  NewValue :: term(),
  DiffEntry :: diff().
make_replace_op(Path, OldValue, NewValue) ->
  #{operation => replace, path => Path, value => NewValue, old_value => OldValue}.

-spec make_map_key(Key) -> PathStep when
  Key :: term(),
  PathStep :: map_path().
make_map_key(Key) ->
  #{type => map, key => Key}.

-spec make_list_index(Index) -> PathStep when
  Index :: non_neg_integer(),
  PathStep :: list_path().
make_list_index(Index) ->
  #{type => list, index => Index}.

-spec apply_diff(From, Diff) -> Result when
  From :: term(),
  Diff :: [diff()],
  Result :: term().
apply_diff(From, Diff) ->
  apply_diff(From, Diff, #{}).

-spec apply_diff(From, Diff, Options) -> Result when
  From :: term(),
  Diff :: [diff()],
  Options :: apply_diff_options(),
  Result :: term().
apply_diff(From, Diff, Options) ->
  Reverse = maps:get(reverse, Options, false),
  Ops = case Reverse of
    true -> lists:reverse(Diff);
    false -> Diff
  end,
  lists:foldl(
    fun(Op, Acc) ->
      apply_diff_entry(Acc, Op, Reverse)
    end, From, Ops).

apply_diff_entry(Acc, #{operation := add, path := Path, value := Value}, true) ->
  apply_path(Acc, Path, remove, Value);
apply_diff_entry(Acc, #{operation := remove, path := Path, value := Value}, true) ->
  apply_path(Acc, Path, add, Value);
apply_diff_entry(Acc, #{operation := replace, path := Path} = Op, true) ->
  OldValue = maps:get(old_value, Op, maps:get(value, Op, undefined)),
  apply_path(Acc, Path, replace, OldValue);
apply_diff_entry(Acc, #{operation := Operation, path := Path, value := Value}, _Reverse) ->
  apply_path(Acc, Path, Operation, Value).

-spec pretty_print(Diff) -> Result when
  Diff :: [diff()],
  Result :: iolist().
pretty_print(Diff) ->
  Blocks = [pretty_print_entry(Entry) || Entry <- Diff],
  lists:flatten(lists:join("\n\n", Blocks) ++ "\n").

pretty_print_entry(#{operation := replace, path := Path, value := NewValue, old_value := OldValue}) ->
  io_lib:format("~~ ~s\n  ~s\n  ~s", [format_path(Path), pretty_value(OldValue), pretty_value(NewValue)]);
pretty_print_entry(#{operation := add, path := Path, value := Value}) ->
  io_lib:format("+ ~s\n  ~s", [format_path(Path), pretty_value(Value)]);
pretty_print_entry(#{operation := remove, path := Path, value := Value}) ->
  io_lib:format("- ~s\n  ~s", [format_path(Path), pretty_value(Value)]);
pretty_print_entry(_) ->
  "".

format_path([]) ->
  "";
format_path(Path) ->
  lists:join(".", [format_path_step(Step) || Step <- Path]).

format_path_step(#{type := map, key := Key}) ->
  atom_to_list(Key);
format_path_step(#{type := list, index := Index}) ->
  integer_to_list(Index).

pretty_value(Value) ->
  lists:flatten(io_lib:format("~p", [Value])).

apply_path(_Term, [], replace, Value) ->
  Value;
apply_path(Term, [], add, Value) ->
  case is_list(Term) of
    true -> Term ++ [Value];
    false -> Value
  end;
apply_path(Term, [], remove, _Value) ->
  Term;
apply_path(Term, [#{type := map, key := Key} | Rest], Operation, Value) ->
  case Rest of
    [] ->
      apply_map_step(Term, Key, Operation, Value);
    _ ->
      Current = maps:get(Key, Term),
      Updated = apply_path(Current, Rest, Operation, Value),
      maps:put(Key, Updated, Term)
  end;
apply_path(Term, [#{type := list, index := Index} | Rest], Operation, Value) ->
  case Rest of
    [] ->
      apply_list_step(Term, Index, Operation, Value);
    _ ->
      Current = lists:nth(Index + 1, Term),
      Updated = apply_path(Current, Rest, Operation, Value),
      replace_list_index(Term, Index, Updated)
  end.

apply_map_step(Map, Key, add, Value) ->
  maps:put(Key, Value, Map);
apply_map_step(Map, Key, remove, _Value) ->
  maps:remove(Key, Map);
apply_map_step(Map, Key, replace, Value) ->
  maps:update(Key, Value, Map).

apply_list_step(List, Index, add, Value) ->
  insert_list_index(List, Index, Value);
apply_list_step(List, Index, remove, _Value) ->
  remove_list_index(List, Index);
apply_list_step(List, Index, replace, Value) ->
  replace_list_index(List, Index, Value).

insert_list_index(List, Index, Value) ->
  {Prefix, Suffix} = lists:split(Index, List),
  Prefix ++ [Value | Suffix].

remove_list_index(List, Index) ->
  {Prefix, [_ | Suffix]} = lists:split(Index, List),
  Prefix ++ Suffix.

replace_list_index(List, Index, Value) ->
  {Prefix, [_ | Suffix]} = lists:split(Index, List),
  Prefix ++ [Value | Suffix].

lcs_matrix(Old, New) ->
  OldSize = length(Old),
  NewSize = length(New),
  OldTuple = list_to_tuple(Old),
  NewTuple = list_to_tuple(New),
  lists:foldl(
    fun(I, Matrix0) ->
      lists:foldl(
        fun(J, Matrix1) ->
          Value =
            case element(I, OldTuple) =:= element(J, NewTuple) of
              true ->
                get(Matrix1, I - 1, J - 1) + 1;
              false ->
                max(get(Matrix1, I - 1, J),
                    get(Matrix1, I, J - 1))
            end,
          Matrix1#{{I, J} => Value}
        end, Matrix0, lists:seq(1, NewSize))
    end, base_matrix(OldSize, NewSize), lists:seq(1, OldSize)).

base_matrix(OldSize, NewSize) ->
  Matrix0 = #{},
  Matrix1 =
    lists:foldl(
      fun(I, Acc) ->
        Acc#{{I, 0} => 0}
      end, Matrix0, lists:seq(0, OldSize)),
  lists:foldl(
    fun(J, Acc) ->
      Acc#{{0, J} => 0}
    end, Matrix1, lists:seq(0, NewSize)).

get(Matrix, I, J) ->
    maps:get({I, J}, Matrix, 0).

backtrack(Old, New, Matrix) ->
  OldTuple = list_to_tuple(Old),
  NewTuple = list_to_tuple(New),
  backtrack(OldTuple, NewTuple, Matrix, tuple_size(OldTuple), tuple_size(NewTuple), []).

backtrack(_Old, _New, _Matrix, 0, 0, Acc) ->
  Acc;
backtrack(Old, New, Matrix, I, 0, Acc) ->
  Value = element(I, Old),
  backtrack(Old, New, Matrix, I - 1, 0, [{remove, Value} | Acc]);
backtrack(Old, New, Matrix, 0, J, Acc) ->
  Value = element(J, New),
  backtrack(Old, New, Matrix, 0, J - 1, [{add, Value} | Acc]);

backtrack(Old, New, Matrix, I, J, Acc) ->
  OldValue = element(I, Old),
  NewValue = element(J, New),
  case OldValue =:= NewValue of
    true ->
      backtrack(Old, New, Matrix, I - 1, J - 1, [{equal, OldValue} | Acc]);
    false ->
      Up = get(Matrix, I - 1, J),
      Left = get(Matrix, I, J - 1),
      case Up >= Left of
        true ->
          backtrack(Old, New, Matrix, I - 1, J, [{remove, OldValue} | Acc]);
        false ->
          backtrack(Old, New, Matrix, I, J - 1, [{add, NewValue} | Acc])
      end
  end.

edits_to_operations([], _Path, _Index, _Options, Acc) ->
  Acc;
edits_to_operations([{equal, _Value} | Rest], Path, Index, Options, Acc) ->
  edits_to_operations(Rest, Path, Index + 1, Options, Acc);
edits_to_operations([{remove, OldValue} | Rest], Path, Index, Options, Acc) ->
  Operation = make_remove_op(Path ++ [make_list_index(Index)], OldValue),
  edits_to_operations(Rest, Path, Index, Options, [Operation | Acc]);
edits_to_operations(Edits, Path, Index, Options, Acc) ->
  {Adds, Rest1} = take_add_run(Edits, []),
  case Rest1 of
    [{remove, _OldValue} | _] ->
      {Removes, Tail} = take_remove_run(Rest1, []),
      NewAcc = emit_pair_replacements(Adds, Removes, Path, Index, Options, Acc),
      edits_to_operations(Tail, Path, Index + min(length(Adds), length(Removes)), Options, NewAcc);
    _ ->
      NewAcc = emit_adds(Adds, Path, Index, Acc),
      edits_to_operations(Rest1, Path, Index + length(Adds), Options, NewAcc)
  end.

emit_pair_replacements([], [], _Path, _Index, _Options, Acc) ->
  Acc;
emit_pair_replacements([NewValue | NewRest], [OldValue | OldRest], Path, Index, Options, Acc) ->
  NewAcc = diff(OldValue, NewValue, Options, Path ++ [#{type => list, index => Index}], Acc),
  emit_pair_replacements(NewRest, OldRest, Path, Index + 1, Options, NewAcc);
emit_pair_replacements(Adds, [], Path, Index, _Options, Acc) ->
  emit_adds(Adds, Path, Index, Acc);
emit_pair_replacements([], Removes, Path, Index, _Options, Acc) ->
  emit_removes(Removes, Path, Index, Acc).

emit_adds([], _Path, _Index, Acc) ->
  Acc;
emit_adds([NewValue | Rest], Path, Index, Acc) ->
  Operation = make_add_op(Path ++ [make_list_index(Index)], NewValue),
  emit_adds(Rest, Path, Index + 1, [Operation | Acc]).

emit_removes([], _Path, _Index, Acc) ->
  Acc;
emit_removes([OldValue | Rest], Path, Index, Acc) ->
  Operation = make_remove_op(Path ++ [make_list_index(Index)], OldValue),
  emit_removes(Rest, Path, Index, [Operation | Acc]).

take_add_run([{add, Value} | Rest], Acc) ->
  take_add_run(Rest, [Value | Acc]);
take_add_run(Other, Acc) ->
  {lists:reverse(Acc), Other}.

take_remove_run([{remove, Value} | Rest], Acc) ->
  take_remove_run(Rest, [Value | Acc]);
take_remove_run(Other, Acc) ->
  {lists:reverse(Acc), Other}.
