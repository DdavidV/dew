# DEW (David's Erlang Workshop)

Welcome to the workshop!

DEW is a collection of dependency-free utilities for Erlang and the BEAM, built in the spirit of a
small workshop where the tools are useful, easy to reach for, and the sort of thing you expect to find
in a toolbox you keep coming back to. Think of DEW as a small library of focused utilities shaped by
real use and by the philosophy that the best tools are the ones that just make sense to keep around.

## Compatibility

This project targets Erlang/OTP 21 and newer.

## Module overview

- `dew_diff` computes a structural diff between two Erlang terms and can apply that diff back to the
original value.

## Build

```bash
rebar3 compile
```

# License
[MIT](LICENSE)
