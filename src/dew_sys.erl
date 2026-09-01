-module(dew_sys).

%% Utility module for inspecting the running Erlang VM.
%%
%% Provides functions to introspect and examine the state of the Erlang virtual machine,
%% useful for debugging and system monitoring.

-export([atoms/0]).

%% Returns all atoms currently present in the Erlang VM's atom table.
%% 
%% The atom table is enumerated using the VM's internal atom indices. Each index is encoded as an
%% Erlang External Term Format (ETF) value and decoded with `erlang:binary_to_term/1`.
%% 
%% The ETF representation starts with `131`, the external term format version magic.
%% The `75` byte identifies the atom representation used by the utility, with the atom table index
%% encoded in the following bytes.
%%
%% This function is intended as a debugging and inspection utility for examining which atoms
%% currently exist in the VM.
-spec atoms() -> Result when
  Result :: [atom()].
atoms() ->
  lists:map(
    fun(N) ->
      erlang:binary_to_term(<<131, 75, N:24>>)
    end, lists:seq(0, erlang:system_info(atom_count) - 1)).
