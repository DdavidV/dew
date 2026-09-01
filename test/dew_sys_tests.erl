-module(dew_sys_tests).

-include_lib("eunit/include/eunit.hrl").

atoms_returns_list_test() ->
  Atoms = dew_sys:atoms(),
  ?assert(is_list(Atoms)),
  ?assert(lists:all(fun is_atom/1, Atoms)).