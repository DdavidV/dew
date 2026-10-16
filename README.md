# DEW (David's Erlang Workshop)

Welcome to the workshop!

DEW is a collection of dependency-free utilities for Erlang and the BEAM, built in the spirit of a
small workshop where the tools are useful, easy to reach for, and the sort of thing you expect to find
in a toolbox you keep coming back to. Think of DEW as a small library of focused utilities shaped by
real use and by the philosophy that the best tools are the ones that just make sense to keep around.

## Compatibility

This project targets Erlang/OTP 21 and newer.

## Module overview

TODO: write docs for every module in a md file

- `dew_diff` computes a structural diff between two Erlang terms and can apply that diff back to the
original value.
- `dew_app` provides OTP application introspection utilities.
- `dew_pipe` is an Elixir-like pipe operator implementation for Erlang using parse transforms,
enabling fluent function chaining.
- `dew_sys` is a utility module for inspecting the running Erlang VM, useful for
debugging and system monitoring.
- `dew_pid` resolves process references (names, `{global, _}`, `{via, _, _}`, pid strings) to pids
and folds over every process on the node.
- `dew_retry` runs functions with configurable retry limits, backoff strategies, and jitter.
- `dew_pmap` applies functions to lists and maps in parallel with configurable worker, crash, and
timeout handling.

## Build

```bash
rebar3 compile
```

## Test

```bash
rebar3 test
```

# License
[MIT](LICENSE)
