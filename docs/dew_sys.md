# dew_sys

Inspection utilities for the running Erlang VM.

`dew_sys` collects runtime information about the node, its processes and its ports into plain maps.
It is meant for debugging and monitoring from a shell or a remote console.

## Functions

| Function | Description |
| --- | --- |
| `info()` | Static information about the runtime: versions, architecture and limits. |
| `metrics()` | Snapshot of runtime statistics: uptime, counts, run queues and memory. |
| `atoms()` | Every atom in the atom table. |
| `processes()` | Information about every alive process. |
| `process_info(PidRef)` | Information about one process. |
| `process_state(PidRef)` | Internal state of a process, with a 5 second timeout. |
| `process_state(PidRef, Timeout)` | Internal state of a process. |
| `ports()` | Information about every open port. |
| `port_info(Port)` | Information about one port. |

Functions that take a `PidRef` accept anything [`dew_pid:to_pid/1`](dew_pid.md#to_pid1) accepts:
pids, registered names, `{global, Name}`, `{via, Module, Name}`, pid strings and `{X, Y, Z}` triplets.

## `info/0`

Returns static information that does not change while the node runs:

```erlang
1> dew_sys:info().
#{otp_release => "27",
  erts_version => "15.0",
  system_version => "Erlang/OTP 27 [erts-15.0] ...",
  architecture => "x86_64-pc-linux-gnu",
  wordsize => 8,
  schedulers => 16,
  limits => #{atoms => 1048576, ports => 65536, processes => 1048576, ets => 8192}}
```

| Key | Source |
| --- | --- |
| `otp_release` | `erlang:system_info(otp_release)` |
| `erts_version` | `erlang:system_info(version)` |
| `system_version` | `erlang:system_info(system_version)` |
| `architecture` | `erlang:system_info(system_architecture)` |
| `wordsize` | `erlang:system_info(wordsize)`, in bytes |
| `schedulers` | `erlang:system_info(schedulers)` |
| `limits` | The atom, port, process and ETS table limits. |

## `metrics/0`

Returns a snapshot of the current state of the node:

| Key | Description |
| --- | --- |
| `uptime` | Milliseconds since the node started. |
| `atom_count` | Number of atoms. |
| `port_count` | Number of open ports. |
| `process_count` | Number of alive processes. |
| `ets_count` | Number of ETS tables. |
| `run_queue` | Length of the normal and dirty CPU run queues. |
| `run_queue_all` | Same as `run_queue`, plus the dirty IO run queue. |
| `memory` | Every entry of `erlang:memory/0` as a map, in bytes. |

Comparing `metrics/0` with the limits in `info/0` shows how close the node is to a system limit.

## `atoms/0`

Returns every atom currently in the VM's atom table. Use it to look for atom leaks, for example atoms
created from user input.

It walks the atom table by index. Each index is encoded as an Erlang External Term Format value
(`<<131, 75, Index:24>>`: `131` is the format version, `75` is the atom-by-index tag the function
relies on) and decoded with `erlang:binary_to_term/1`. This depends on VM internals and is meant for
debugging, not for production code paths. On a node with many atoms the result is a large list.

## `processes/0` and `process_info/1`

`process_info/1` returns information about a single process, or `undefined` if it cannot be resolved
or is not alive. `processes/0` returns the same map for every process on the node. Processes that
exit while the snapshot is being taken are skipped.

```erlang
2> dew_sys:process_info(code_server).
#{pid => <0.50.0>,
  registered_name => code_server,
  global_name => undefined,
  current_function => {code_server, loop, 1},
  status => waiting,
  message_queue_len => 0,
  reductions => 254879,
  memory => 142896,
  heap_size => 30360,
  stack_size => 40,
  total_heap_size => 137744}
```

| Key | Description |
| --- | --- |
| `pid` | The process. |
| `registered_name` | Locally registered name, or `undefined`. |
| `global_name` | Name registered with `global`, or `undefined`. |
| `current_function` | `{Module, Function, Arity}` the process is in. |
| `status` | `running`, `runnable`, `waiting`, `garbage_collecting`, … |
| `message_queue_len` | Number of messages in the mailbox. |
| `reductions` | Reductions executed so far. |
| `memory` | Total process memory, in bytes. |
| `heap_size`, `stack_size`, `total_heap_size` | Converted from words to bytes. |

Finding the processes with the longest mailboxes:

```erlang
3> lists:sublist(
     lists:reverse(lists:keysort(2,
       [{Pid, Len} || #{pid := Pid, message_queue_len := Len} <- dew_sys:processes()])),
     5).
```

## `process_state/1,2`

Returns the internal state of a process that handles system messages, such as a `gen_server`,
`gen_statem` or `gen_event`, using `sys:get_state/2`.

```erlang
4> dew_sys:process_state(my_server).
{ok, #state{...}}
5> dew_sys:process_state(no_such_name).
{error, noproc}
6> dew_sys:process_state(busy_server, 100).
{error, timeout}
```

| Argument | Default | Description |
| --- | --- | --- |
| `PidRef` | | The process to query. |
| `Timeout` | `5000` | Milliseconds to wait for the reply, or `infinity`. |

Returns `{ok, State}` on success, `{error, noproc}` if the reference cannot be resolved, and
`{error, Reason}` if `sys:get_state/2` exits, for example with `timeout`.

## `ports/0` and `port_info/1`

`port_info/1` returns the items of `erlang:port_info/1` as a map with an extra `port` key, or
`undefined` if the port is closed. `ports/0` returns that map for every open port. Ports that close
while the snapshot is being taken are skipped.

```erlang
7> dew_sys:port_info(hd(erlang:ports())).
#{port => #Port<0.0>,
  name => "forker",
  links => [<0.0.0>],
  id => 0,
  connected => <0.0.0>,
  input => 0,
  output => 0,
  os_pid => undefined}
```
