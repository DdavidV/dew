-module(dew_sys_tests).

-include_lib("eunit/include/eunit.hrl").

-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2]).

init(State) -> {ok, State}.
handle_call(_Request, _From, State) -> {reply, ok, State}.
handle_cast(_Request, State) -> {noreply, State}.

atoms_returns_list_test() ->
  Atoms = dew_sys:atoms(),
  ?assert(is_list(Atoms)),
  ?assert(lists:all(fun is_atom/1, Atoms)).

info_test() ->
  Info = dew_sys:info(),
  ?assertEqual(erlang:system_info(otp_release), maps:get(otp_release, Info)),
  ?assertEqual(erlang:system_info(process_limit), maps:get(processes, maps:get(limits, Info))).

metrics_test() ->
  Metrics = dew_sys:metrics(),
  ?assert(maps:get(process_count, Metrics) > 0),
  ?assert(maps:get(total, maps:get(memory, Metrics)) > 0).

processes_contains_self_test() ->
  Self = self(),
  ?assertMatch([#{pid := Self}], [P || P = #{pid := Pid} <- dew_sys:processes(), Pid =:= Self]).

process_by_name_test() ->
  Pid = whereis(code_server),
  ?assertMatch(#{pid := Pid, registered_name := code_server}, dew_sys:process_info(code_server)).

process_unnamed_test() ->
  ?assertMatch(#{registered_name := undefined, global_name := undefined}, dew_sys:process_info(self())).

process_memory_in_bytes_test() ->
  #{heap_size := Heap} = dew_sys:process_info(self()),
  {heap_size, Words} = erlang:process_info(self(), heap_size),
  ?assertEqual(Words * erlang:system_info(wordsize), Heap).

process_global_name_test() ->
  yes = global:register_name(dew_sys_test_global, self()),
  try
    ?assertMatch(#{global_name := dew_sys_test_global}, dew_sys:process_info({global, dew_sys_test_global}))
  after
    global:unregister_name(dew_sys_test_global)
  end.

process_dead_test() ->
  Pid = spawn(fun() -> ok end),
  Ref = monitor(process, Pid),
  receive {'DOWN', Ref, process, Pid, _} -> ok end,
  ?assertEqual(undefined, dew_sys:process_info(Pid)),
  ?assertEqual(undefined, dew_sys:process_info(no_such_registered_name)).

state_test() ->
  {ok, Pid} = gen_server:start(?MODULE, initial_state, []),
  try
    ?assertEqual({ok, initial_state}, dew_sys:process_state(Pid))
  after
    gen_server:stop(Pid)
  end.

state_errors_test() ->
  ?assertEqual({error, noproc}, dew_sys:process_state(no_such_registered_name)),
  Pid = spawn(fun() -> receive stop -> ok end end),
  try
    ?assertEqual({error, timeout}, dew_sys:process_state(Pid, 50))
  after
    Pid ! stop
  end.

ports_test() ->
  Port = open_port({spawn, "cat"}, []),
  try
    ?assertMatch(#{port := Port, connected := _}, dew_sys:port_info(Port)),
    ?assert(lists:any(fun(#{port := P}) -> P =:= Port end, dew_sys:ports()))
  after
    port_close(Port)
  end,
  ?assertEqual(undefined, dew_sys:port_info(Port)).
