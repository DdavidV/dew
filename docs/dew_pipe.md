# dew_pipe

An Elixir-like pipe operator for Erlang, implemented as a parse transform.

`dew_pipe` lets you write a chain of calls as a list of stages instead of nested calls. The value
flows through the stages in order, and the result of each stage becomes the **first argument** of the
next one.

```erlang
%% Without the pipe
lists:sum(lists:reverse(lists:append([1, 2, 3], [4, 5]))).

%% With the pipe
pipe([1, 2, 3],
     lists:append([4, 5]),
     lists:reverse(),
     lists:sum()).
```

## Setup

Enable the parse transform in the module that uses the pipe:

```erlang
-compile({parse_transform, dew_pipe}).
```

`dew` must be compiled before the module that uses the transform, which is the case when `dew` is a
dependency of your project.

## Usage

```erlang
Result = pipe(Value, Stage1, Stage2, ...).
```

`pipe/N` and `dew_pipe:pipe/N` are equivalent, and both are rewritten at compile time. There is no
runtime `pipe` function: the transform turns

```erlang
pipe(Value, f(A), m:g(), h(B, C))
```

into

```erlang
h(m:g(f(Value, A)), B, C)
```

### Stages

Every stage must be a function call. The piped value is inserted in front of the call's own
arguments:

| Stage | Becomes |
| --- | --- |
| `lists:reverse()` | `lists:reverse(Value)` |
| `lists:append([4, 5])` | `lists:append(Value, [4, 5])` |
| `local_fun(X)` | `local_fun(Value, X)` |
| `Fun()` (a variable bound to a fun) | `Fun(Value)` |

### `tap/1` and `then/1`

Two helpers cover the cases where the value should not be the first argument of a call. Inside a
pipe they are written with one argument (the fun); the transform rewrites them to
`dew_pipe:tap/2` and `dew_pipe:then/2`.

- `tap(Fun)` calls `Fun(Value)` for side effects, ignores what it returns and passes `Value` on
  unchanged.
- `then(Fun)` calls `Fun(Value)` and passes its result on. Use it when the value has to go somewhere
  other than the first argument.

```erlang
pipe([1, 2, 3],
     lists:reverse(),
     tap(fun(List) -> logger:debug("reversed: ~p", [List]) end),
     then(fun(List) -> lists:map(fun(X) -> X * 2 end, List) end),
     lists:sum()).
%% 12
```

`dew_pipe:tap/2` and `dew_pipe:then/2` are also exported, so they can be called directly.

## Compile errors

The transform raises an error at compile time when:

- a pipe has fewer than two arguments: `{dew_pipe, {invalid_pipe_arity, N}}`
- a stage is not a function call, for example a variable or a literal:
  `{dew_pipe, {invalid_pipe_target, Stage}}`

## Notes

- Every call named `pipe` in a module that uses the transform is treated as a pipe. Do not define or
  import another `pipe` function in such a module.
- Only local `tap(...)` and `then(...)` stages are rewritten to `dew_pipe`. A remote call such as
  `my_mod:tap(Arg)` is left as a regular stage.
