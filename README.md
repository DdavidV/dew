# DEW (David's Erlang Workshop)

Welcome to the workshop!

DEW is a collection of dependency-free utilities for Erlang and the BEAM, built in the spirit of a
small workshop where the tools are useful, easy to reach for, and the sort of thing you expect to find
in a toolbox you keep coming back to. Think of DEW as a small library of focused utilities shaped by
real use and by the philosophy that the best tools are the ones that just make sense to keep around.

## Compatibility

This project targets Erlang/OTP 21 and newer.

## Modules

Every module has its own page in [`docs/`](docs/) that covers what it does, how to use it and every
option it accepts.

| Module | Description |
| --- | --- |
| [`dew_app`](docs/dew_app.md) | Resolves the dependencies of OTP applications as a tree or a graph. |
| [`dew_diff`](docs/dew_diff.md) | Computes a structural diff between two Erlang terms, applies it forwards or in reverse, and pretty prints it. |
| [`dew_pid`](docs/dew_pid.md) | Resolves process references (names, `{global, _}`, `{via, _, _}`, pid strings) to pids and folds over every process on the node. |
| [`dew_pipe`](docs/dew_pipe.md) | Elixir-like pipe operator for Erlang, implemented as a parse transform, with `tap` and `then` helpers. |
| [`dew_pmap`](docs/dew_pmap.md) | Applies a function to lists and maps in parallel with configurable worker count, node selection, crash and timeout handling. |
| [`dew_retry`](docs/dew_retry.md) | Runs functions with configurable retry limits, backoff strategies and jitter. |
| [`dew_sys`](docs/dew_sys.md) | Inspects the running Erlang VM: runtime info, metrics, atoms, processes, process state and ports. |
| [`dew_tpl`](docs/dew_tpl.md) | Compiles and renders text templates with conditionals, loops, case, partials and custom functions, returning descriptive errors instead of raising. |

## Build

```bash
rebar3 compile
```

## Test

```bash
rebar3 test
```

# License
[MIT](LICENSE.md)
