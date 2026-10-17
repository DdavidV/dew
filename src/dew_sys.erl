-module(dew_sys).

-compile({no_auto_import, [
  processes/0,
  process_info/1,
  port_info/1
]}).

-type info() :: #{
  otp_release := string(),
  erts_version := string(),
  system_version := string(),
  architecture := string(),
  wordsize := pos_integer(),
  schedulers := pos_integer(),
  limits := #{
    atoms := pos_integer(),
    ports := pos_integer(),
    processes := pos_integer(),
    ets := pos_integer()
  }
}.

-type metrics() :: #{
  uptime := non_neg_integer(),
  atom_count := non_neg_integer(),
  port_count := non_neg_integer(),
  process_count := non_neg_integer(),
  ets_count := non_neg_integer(),
  run_queue := non_neg_integer(),
  run_queue_all := non_neg_integer(),
  memory := #{atom() => non_neg_integer()}
}.

-type process_info() :: #{
  pid := pid(),
  registered_name := atom() | undefined,
  global_name := term() | undefined,
  current_function := mfa() | undefined,
  status := atom(),
  message_queue_len := non_neg_integer(),
  reductions := non_neg_integer(),
  memory := non_neg_integer(),
  heap_size := non_neg_integer(),
  stack_size := non_neg_integer(),
  total_heap_size := non_neg_integer()
}.

-type port_info() :: #{atom() => term()}.

-export_type([
  info/0,
  metrics/0,
  process_info/0,
  port_info/0
]).

-export([
  atoms/0,
  info/0,
  metrics/0,
  processes/0,
  process_info/1,
  process_state/1,
  process_state/2,
  ports/0,
  port_info/1
]).

-define(PROCESS_KEYS, [
  registered_name,
  current_function,
  status,
  message_queue_len,
  reductions,
  memory,
  heap_size,
  stack_size,
  total_heap_size
]).

-define(WORD_SIZED_KEYS, [heap_size, stack_size, total_heap_size]).

-define(DEFAULT_STATE_TIMEOUT, 5000).

-spec atoms() -> Result when
  Result :: [atom()].
atoms() ->
  lists:map(
    fun(N) ->
      erlang:binary_to_term(<<131, 75, N:24>>)
    end, lists:seq(0, erlang:system_info(atom_count) - 1)).

-spec info() -> Result when
  Result :: info().
info() ->
  #{otp_release => erlang:system_info(otp_release),
    erts_version => erlang:system_info(version),
    system_version => erlang:system_info(system_version),
    architecture => erlang:system_info(system_architecture),
    wordsize => erlang:system_info(wordsize),
    schedulers => erlang:system_info(schedulers),
    limits => #{
      atoms => erlang:system_info(atom_limit),
      ports => erlang:system_info(port_limit),
      processes => erlang:system_info(process_limit),
      ets => erlang:system_info(ets_limit)
    }}.

-spec metrics() -> Result when
  Result :: metrics().
metrics() ->
  {Uptime, _} = erlang:statistics(wall_clock),
  #{uptime => Uptime,
    atom_count => erlang:system_info(atom_count),
    port_count => erlang:system_info(port_count),
    process_count => erlang:system_info(process_count),
    ets_count => length(ets:all()),
    run_queue => erlang:statistics(total_run_queue_lengths),
    run_queue_all => erlang:statistics(total_run_queue_lengths_all),
    memory => maps:from_list(erlang:memory())}.

-spec processes() -> Result when
  Result :: [process_info()].
processes() ->
  GlobalNames = global_names(),
  dew_pid:fold(
    fun(Pid, Acc) ->
      case build_process_info(Pid, GlobalNames) of
        undefined -> Acc;
        Info -> [Info | Acc]
      end
    end, []).

-spec process_info(PidRef) -> Result when
  PidRef :: dew_pid:pid_ref(),
  Result :: process_info() | undefined.
process_info(PidRef) ->
  case dew_pid:to_pid(PidRef) of
    undefined -> undefined;
    Pid -> build_process_info(Pid, global_names())
  end.

build_process_info(Pid, GlobalNames) ->
  case erlang:process_info(Pid, ?PROCESS_KEYS) of
    undefined ->
      undefined;
    Info ->
      WordSize = erlang:system_info(wordsize),
      maps:from_list(
        [{pid, Pid},
         {global_name, maps:get(Pid, GlobalNames, undefined)} |
         [format_process_info(Item, WordSize) || Item <- Info]])
  end.

format_process_info({registered_name, []}, _WordSize) ->
  {registered_name, undefined};
format_process_info({Key, Words}, WordSize) ->
  case lists:member(Key, ?WORD_SIZED_KEYS) of
    true -> {Key, Words * WordSize};
    false -> {Key, Words}
  end.

%% Returns a map from pid to the name it is registered under in `global`.
global_names() ->
  lists:foldl(
    fun(Name, Acc) ->
      case global:whereis_name(Name) of
        Pid when is_pid(Pid) -> Acc#{Pid => Name};
        undefined -> Acc
      end
    end, #{}, global:registered_names()).

-spec process_state(PidRef) -> Result when
  PidRef :: dew_pid:pid_ref(),
  Result :: {ok, term()} | {error, term()}.
process_state(PidRef) ->
  process_state(PidRef, ?DEFAULT_STATE_TIMEOUT).

-spec process_state(PidRef, Timeout) -> Result when
  PidRef :: dew_pid:pid_ref(),
  Timeout :: timeout(),
  Result :: {ok, term()} | {error, term()}.
process_state(PidRef, Timeout) ->
  case dew_pid:to_pid(PidRef) of
    undefined ->
      {error, noproc};
    Pid ->
      try
        {ok, sys:get_state(Pid, Timeout)}
      catch
        exit:{Reason, {sys, get_state, _}} ->
          {error, Reason};
        exit:Reason ->
          {error, Reason}
      end
  end.

-spec ports() -> Result when
  Result :: [port_info()].
ports() ->
  lists:foldl(
    fun(Port, Acc) ->
      case port_info(Port) of
        undefined -> Acc;
        Info -> [Info | Acc]
      end
    end, [], erlang:ports()).

-spec port_info(Port) -> Result when
  Port :: port(),
  Result :: port_info() | undefined.
port_info(Port) ->
  case erlang:port_info(Port) of
    undefined -> undefined;
    Info -> maps:from_list([{port, Port} | Info])
  end.
