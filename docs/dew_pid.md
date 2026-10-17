# dew_pid

Utilities for working with process identifiers.

`dew_pid` resolves the many ways a process can be referred to into a pid, and folds over every
process on the node. Other DEW modules, such as [`dew_sys`](dew_sys.md), use it to accept any kind of
process reference.

## Functions

| Function | Description |
| --- | --- |
| `to_pid(PidRef)` | Resolves a process reference to a pid, or returns `undefined`. |
| `fold(Fun, Acc)` | Folds `Fun(Pid, Acc)` over every process on the node. |

## `to_pid/1`

Accepted references (`dew_pid:pid_ref()`):

| Reference | Example | Resolved with |
| --- | --- | --- |
| Pid | `self()` | Returned as is. |
| Locally registered name | `code_server` | `erlang:whereis/1` |
| Global name | `{global, my_server}` | `global:whereis_name/1` |
| Via name | `{via, gproc, {n, l, key}}` | `Module:whereis_name/1` |
| Pid string | `"<0.42.0>"` | `erlang:list_to_pid/1` |
| Pid binary | `<<"<0.42.0>">>` | Converted to a string first. |
| Triplet | `{0, 42, 0}` | Same as `c:pid(0, 42, 0)`. |

`to_pid/1` returns `undefined` when the reference cannot be resolved: an unregistered name, a
malformed pid string, a name that is registered to a port, or any other term.

```erlang
1> dew_pid:to_pid(code_server).
<0.50.0>
2> dew_pid:to_pid("<0.1.0>").
<0.1.0>
3> dew_pid:to_pid({0, 1, 0}).
<0.1.0>
4> dew_pid:to_pid(no_such_name).
undefined
```

A pid that `to_pid/1` returns is not guaranteed to be alive. It only means the reference could be
resolved.

## `fold/2`

Calls `Fun(Pid, Acc)` for every process on the node and returns the final accumulator:

```erlang
5> dew_pid:fold(fun(_Pid, Count) -> Count + 1 end, 0).
57
6> dew_pid:fold(
     fun(Pid, Acc) ->
       case erlang:process_info(Pid, message_queue_len) of
         {message_queue_len, Len} when Len > 1000 -> [Pid | Acc];
         _ -> Acc
       end
     end, []).
[]
```

On OTP 28 and newer it uses `erlang:processes_iterator/0`, which walks the process table without
building a list of every pid first. On older releases it falls back to `erlang:processes/0`.

Processes can start and exit while the fold runs, so `Fun` should expect pids that are no longer
alive.
