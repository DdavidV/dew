-module(dew_pmap).

-type list_fun() :: fun((Element :: term()) -> term()).
-type map_fun() :: fun((Key :: term(), Value :: term()) -> term()).
-type pmap_fun() :: list_fun() | map_fun().

-type node_select_fun() :: fun((Key :: term()) -> node()).

-type iterator() :: none | {map, list()} | {list, list(), non_neg_integer()}.
-type worker() :: {reference(), none | term()}.

-type crash_handling() :: one_for_one | one_for_all.
-type timeout_handling() :: graceful | throw | exit.

-type options() :: #{
  max_worker_count => pos_integer(),
  node_select_fun => node_select_fun(),
  timeout => infinity | pos_integer(),
  crash_handling => crash_handling(),
  timeout_handling => timeout_handling()
}.

-record(pmap_state, {
  function :: pmap_fun(),
  node_select_fun :: node_select_fun(),
  max_worker_count :: pos_integer(),
  timeout :: infinity | pos_integer(),
  size :: non_neg_integer(),
  parent :: pid(),
  workers :: #{pid() => worker()},
  type :: map | list,
  iterator :: iterator(),
  remaining :: non_neg_integer(),
  crash_handling :: crash_handling(),
  timeout_handling :: timeout_handling()
}).

-export_type([
  list_fun/0,
  map_fun/0,
  pmap_fun/0,
  node_select_fun/0,
  iterator/0,
  worker/0,
  crash_handling/0,
  timeout_handling/0,
  options/0
]).

-export([
  map/2,
  map/3
]).

-spec map(Fun, Data) -> Result when
  Fun :: pmap_fun(),
  Data :: list() | map(),
  Result :: list() | map().
map(Fun, Data) ->
  map(Fun, Data, #{}).

-spec map(Fun, Data, Options) -> Result when
  Fun :: pmap_fun(),
  Data :: list() | map(),
  Options :: options(),
  Result :: list() | map().
map(Fun, Data, Options) ->
  {Size, Type, Iterator} = iterator(Data),
  State = #pmap_state{
    function = Fun,
    node_select_fun = maps:get(node_select_fun, Options, fun(_Key) -> node() end),
    max_worker_count = maps:get(max_worker_count, Options, 2),
    timeout = maps:get(timeout, Options, timer:seconds(60)),
    size = Size,
    parent = self(),
    workers = #{},
    type = Type,
    iterator = Iterator,
    remaining = Size,
    crash_handling = maps:get(crash_handling, Options, one_for_all),
    timeout_handling = maps:get(timeout_handling, Options, throw)
  },
  NewState = spawn_workers(State),
  Result = #{},
  receive_loop(Result, NewState).

receive_loop(Result, #pmap_state{remaining = 0,
                                 workers = Workers,
                                 type = Type,
                                 size = Size}) ->
  stop_workers(Workers),
  result(Type, Size, Result);
receive_loop(Result, #pmap_state{parent = Parent,
                                 timeout = Timeout,
                                 workers = Workers,
                                 remaining = Remaining,
                                 iterator = Iterator,
                                 type = Type,
                                 size = Size,
                                 timeout_handling = TimeoutHandling} = State) ->
  ReceiveResult =
    receive
      {'DOWN', _MonitorReference, process, WorkerPid, normal} ->
        %% The worker will stop when no tasks remain to execute and the others takes a long time
        {Result, State#pmap_state{workers = maps:remove(WorkerPid, Workers)}};
      {'DOWN', _MonitorReference, process, WorkerPid, Reason} ->
        %% Worker crashed
        {_StoredMonitorReference, Key} = maps:get(WorkerPid, Workers),
        WorkersAfterCrash = maps:remove(WorkerPid, Workers),
        case State#pmap_state.crash_handling of
          one_for_all ->
            %% Stop all workers and propagate the crash to the parent process
            kill_workers(Workers),
            erlang:error(Reason);
          one_for_one ->
            %% Spawn a new worker to replace the crashed one and continue processing
            StateAfterCrash = spawn_workers(State#pmap_state{
              workers = WorkersAfterCrash,
              remaining = remaining_after_crash(Key, Remaining)
            }),
            {handle_crash(Key, Reason, Result), StateAfterCrash}
        end;
      {result, Worker, Key, Data} ->
        %% A worker has finished processing a task, store the result and start the next task
        State0 = State#pmap_state{remaining = Remaining - 1},
        {MonitorReference, _CurrentKey} = maps:get(Worker, Workers),
        UpdatedState =
          case next(Type, Iterator) of
            none ->
              %% No more tasks to assign, mark the worker as idle
              State0#pmap_state{
                iterator = none,
                workers = Workers#{Worker => {MonitorReference, none}}
              };
            {NextKey, Argument, NextIterator} ->
              %% Assign the next task to the worker
              Worker ! {task, Parent, Type, NextKey, Argument},
              State0#pmap_state{
                iterator = NextIterator,
                workers = Workers#{Worker => {MonitorReference, NextKey}}
              }
          end,
        {handle_result(Key, Data, Result), UpdatedState}
    after Timeout ->
      %% Timeout occurred, handle according to the specified timeout handling strategy
      {done, handle_timeout(TimeoutHandling, Type, Size, Iterator, Workers, Result)}
    end,
  case ReceiveResult of
    {done, FinalResult} ->
      FinalResult;
    {NewResult, NewState} ->
      receive_loop(NewResult, NewState)
  end.

handle_result(Key, Data, Result) ->
  Result#{Key => Data}.

handle_crash(none, _Reason, Result) ->
  Result;
handle_crash(Key, Reason, Result) ->
  handle_result(Key, Reason, Result).

remaining_after_crash(none, Remaining) ->
  Remaining;
remaining_after_crash(_Key, Remaining) ->
  Remaining - 1.

handle_timeout(graceful, Type, Size, Iterator, Workers, Result) ->
  kill_workers(Workers),
  TimeoutResult =
    maps:fold(
      fun(_WorkerPid, {_MonitorReference, none}, Accumulator) ->
          Accumulator;
         (_WorkerPid, {_MonitorReference, Key}, Accumulator) ->
          handle_result(Key, timeout, Accumulator)
      end, Result, Workers),
  result(Type, Size, handle_timeout_iterator(Type, Iterator, TimeoutResult));
handle_timeout(throw, _Type, _Size, _Iterator, Workers, _Result) ->
  kill_workers(Workers),
  throw(timeout);
handle_timeout(exit, _Type, _Size, _Iterator, Workers, _Result) ->
  kill_workers(Workers),
  exit(timeout).

handle_timeout_iterator(_Type, none, Result) ->
  Result;
handle_timeout_iterator(Type, Iterator, Result) ->
  case next(Type, Iterator) of
    none ->
      Result;
    {Key, _Argument, NextIterator} ->
      handle_timeout_iterator(Type, NextIterator, handle_result(Key, timeout, Result))
  end.

result(map, _Size, Result) ->
  Result;
result(list, Size, Result) ->
  [maps:get(Index, Result) || Index <- lists:seq(1, Size)].

iterator(Map) when is_map(Map) ->
  {maps:size(Map), map, {map, maps:to_list(Map)}};
iterator(List) when is_list(List) ->
  {length(List), list, {list, List, 1}}.

next(_Type, none) ->
  none;
next(map, {map, Entries}) ->
  case Entries of
    [] ->
      none;
    [{Key, Value} | Tail] ->
      {Key, {Key, Value}, {map, Tail}}
  end;
next(list, {list, List, Index}) ->
  case List of
    [] ->
      none;
    [Value | Tail] ->
      {Index, Value, {list, Tail, Index + 1}}
  end.

spawn_workers(#pmap_state{node_select_fun = NodeSelectFun,
                          max_worker_count = MaxWorkerCount,
                          type = Type,
                          iterator = Iterator,
                          function = Function,
                          parent = Parent,
                          workers = Workers,
                          remaining = Remaining} = State) ->
  case maps:size(Workers) < MaxWorkerCount andalso Remaining > 0 of
    false ->
      State;
    true ->
      case next(Type, Iterator) of
        none ->
          State;
        {Key, Argument, NextIterator} ->
          {WorkerPid, MonitorRef} =
            erlang:spawn_monitor(NodeSelectFun(Key), fun() -> worker_loop(Parent, Function) end),
          WorkerPid ! {task, Parent, Type, Key, Argument},
          spawn_workers(State#pmap_state{
            iterator = NextIterator,
            workers = Workers#{WorkerPid => {MonitorRef, Key}}
          })
      end
  end.

worker_loop(Parent, Function) ->
  receive
    {task, Parent, Type, Key, Argument} ->
      Result = execute_function(Type, Function, Argument),
      Parent ! {result, self(), Key, Result},
      worker_loop(Parent, Function);
    stop ->
      ok
  after 1000 ->
    ok
  end.

execute_function(map, Function, {Key, Value}) ->
  Function(Key, Value);
execute_function(list, Function, Argument) ->
  Function(Argument).

stop_workers(Workers) ->
  lists:foreach(
    fun({WorkerPid, {MonitorRef, _Key}}) ->
      erlang:demonitor(MonitorRef, [flush]),
      WorkerPid ! stop
    end, maps:to_list(Workers)).

kill_workers(Workers) ->
  lists:foreach(
    fun({WorkerPid, {MonitorRef, _Key}}) ->
      erlang:demonitor(MonitorRef, [flush]),
      exit(WorkerPid, kill)
    end, maps:to_list(Workers)).
