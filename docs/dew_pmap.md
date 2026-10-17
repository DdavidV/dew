# dew_pmap

Parallel map over lists and maps.

`dew_pmap` applies a function to every element of a list or every entry of a map using a bounded
pool of worker processes. Results come back in the same shape as the input. You can configure
how many workers run, which node each one runs on, what happens when a worker crashes, and what
happens when results stop coming in.

## Functions

| Function | Description |
| --- | --- |
| `map(Fun, Data)` | Maps `Fun` over `Data` with default options. |
| `map(Fun, Data, Options)` | Maps `Fun` over `Data`, see [Options](#options). |

## Lists and maps

For a **list**, `Fun` takes one argument (the element), and the result is a list in the original
order:

```erlang
1> dew_pmap:map(fun(X) -> X * 2 end, [1, 2, 3]).
[2, 4, 6]
```

For a **map**, `Fun` takes two arguments (key and value), and the result is a map with the same keys
and the function results as values:

```erlang
2> dew_pmap:map(fun(_Key, Value) -> Value * 10 end, #{a => 1, b => 2}).
#{a => 10, b => 20}
```

## How it works

1. Up to `max_worker_count` workers are spawned and monitored, each with one element to process.
2. When a worker sends back a result, it gets the next unprocessed element. Workers are reused until
   no work is left.
3. When every element is done, the remaining workers are stopped and the result is assembled.

`timeout` is not a deadline for the whole call. It is the longest the caller waits for the next
event (a result or a worker exit). As long as results keep coming, the call keeps running.

## Options

Options are passed as a map. Every key is optional.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `max_worker_count` | `pos_integer()` | `2` | Maximum number of workers running at the same time. |
| `node_select_fun` | `fun((Key) -> node())` | `fun(_) -> node() end` | Picks the node a worker is spawned on. `Key` is the list index (starting at 1) or the map key of the first element given to that worker. |
| `timeout` | `pos_integer() \| infinity` | `60000` | Milliseconds to wait for the next result or worker exit. |
| `crash_handling` | `one_for_all \| one_for_one` | `one_for_all` | What to do when a worker crashes. |
| `timeout_handling` | `throw \| exit \| graceful` | `throw` | What to do when `timeout` passes without an event. |

### `crash_handling`

- `one_for_all` kills every worker and raises the crash reason with `erlang:error/1` in the caller.
- `one_for_one` puts the crash reason in place of the result for that element, starts a new worker
  and goes on with the other elements.

```erlang
3> dew_pmap:map(fun(1) -> error(boom); (X) -> X end, [1, 2, 3],
                #{crash_handling => one_for_one}).
[{boom, [...stacktrace...]}, 2, 3]
```

### `timeout_handling`

- `throw` kills every worker and calls `throw(timeout)`.
- `exit` kills every worker and calls `exit(timeout)`.
- `graceful` kills every worker and returns a full result where every unfinished element (in
  progress or not yet started) has the value `timeout`.

```erlang
4> dew_pmap:map(fun(1) -> timer:sleep(500); (X) -> X end, [1, 2, 3],
                #{timeout => 100, timeout_handling => graceful}).
[timeout, 2, 3]
```

### Running on other nodes

`node_select_fun` lets you spread the work across a cluster. The function must be available on the
target nodes (for example, a fun from a module loaded on all of them).

```erlang
Nodes = [node() | nodes()],
dew_pmap:map(fun heavy_work/1, Items, #{
  max_worker_count => 8,
  node_select_fun => fun(Index) -> lists:nth((Index rem length(Nodes)) + 1, Nodes) end
}).
```

## Notes

- Results are matched to elements by key, so the order of completion does not matter.
- Workers are linked to nothing, only monitored. If the caller is killed, idle workers exit on their
  own after one second without new work.
