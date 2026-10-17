# dew_retry

Retry a function with configurable limits, backoff and jitter.

`dew_retry:run/2` runs a function, decides from its result whether to try again, and repeats while
the configured retry and elapsed-time limits allow it. Between attempts it waits for a delay
computed by a backoff function and adjusted by a jitter function. The value of the last attempt is
returned as is.

## Functions

| Function | Description |
| --- | --- |
| `run(Function, Options)` | Runs `Function` with retries. |
| `constant/1`, `linear/1`, `exponential/1`, `exponential/2` | Built-in backoff functions. |
| `no_jitter/0`, `full_jitter/0`, `equal_jitter/0`, `percent_range_jitter/1` | Built-in jitter functions. |

## Usage

`Function` can be a fun with no arguments, `{Module, Function}` or `{Module, Function, Args}`:

```erlang
dew_retry:run(fun() -> httpc:request(Url) end, #{max_retries => 3}).
dew_retry:run({my_client, connect}, #{max_retries => 3}).
dew_retry:run({my_client, fetch, [Id]}, #{max_retries => 3, backoff => dew_retry:exponential(100)}).
```

With the default evaluator, every `{error, _}` result is retried and any other result is returned
at once. Exceptions are not caught. If `Function` raises, the exception goes to the caller.

## How a run proceeds

1. `Function` is executed and the context is updated with its result and the elapsed time.
2. `retry_eval` decides between `stop` and `retry`. On `stop` the result is returned.
3. On `retry`, the limits (`max_retries`, `max_elapsed`) are checked. If no more attempts are
   allowed, the result of the last attempt is returned.
4. Otherwise `retry_logger` is called, the delay is computed as `jitter(backoff(Context), Context)`,
   the process sleeps for it with `timer:sleep/1`, and the next attempt starts.

## Options

Options are passed as a map. Every key is optional.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `max_retries` | `integer() \| infinity` | `0` | Upper limit on the number of retries. |
| `max_elapsed` | `integer() \| infinity` | `infinity` | Milliseconds since the first attempt after which no new retry is started. A running attempt is never interrupted. |
| `retry_eval` | `fun((Context) -> stop \| retry)` | retries `{error, _}` | Decides whether the last result should be retried. |
| `retry_logger` | `fun((Context) -> ok)` | does nothing | Called before every retry, for example to log it. |
| `backoff` | `fun((Context) -> integer())` | `constant(0)` | Computes the delay before the next attempt, in milliseconds. |
| `jitter` | `fun((Delay, Context) -> integer())` | `no_jitter()` | Adjusts the delay computed by `backoff`. |

### Context

Every callback receives a context map describing the state of the run:

| Key | Description |
| --- | --- |
| `start_time` | `erlang:monotonic_time(millisecond)` at the start of the run. |
| `elapsed` | Milliseconds since `start_time`, measured after the last attempt. |
| `attempt` | Number of the attempt that just finished, starting at 1. |
| `retries` | Number of retries already made. |
| `previous_delay` | The last delay slept, or `undefined` before the first retry. |
| `result` | Result of the last attempt. |

### Custom evaluator

```erlang
dew_retry:run(fun() -> gen_server:call(Server, get) end, #{
  max_retries => 5,
  retry_eval =>
    fun(#{result := {error, busy}}) -> retry;
       (#{result := {error, timeout}}) -> retry;
       (_) -> stop
    end
}).
```

### Logging retries

```erlang
dew_retry:run(Fun, #{
  max_retries => 3,
  retry_logger =>
    fun(#{attempt := Attempt, result := Result}) ->
      logger:warning("attempt ~b failed with ~p, retrying", [Attempt, Result])
    end
}).
```

## Backoff functions

Each built-in returns a `backoff_fun()`. `Attempt` is the number of the attempt that just failed.

| Function | Delay before the next attempt |
| --- | --- |
| `constant(Delay)` | `Delay` |
| `linear(Base)` | `Base * Attempt`: Base, 2·Base, 3·Base, … |
| `exponential(Base)` | `Base * 2^(Attempt - 1)`: Base, 2·Base, 4·Base, … |
| `exponential(Base, Max)` | Same as `exponential(Base)`, but never more than `Max`. |

A custom backoff is any `fun((Context) -> integer())`.

## Jitter functions

Jitter spreads retries from many clients over time so they do not all hit a recovering service at
the same moment. Each built-in returns a `jitter_fun()`. `Delay` is the value from the backoff
function.

| Function | Resulting delay |
| --- | --- |
| `no_jitter()` | Exactly `Delay`. |
| `full_jitter()` | Random in `[0, Delay - 1]` (`0` when `Delay` is `0`). |
| `equal_jitter()` | Random in `[Delay div 2, Delay]`. |
| `percent_range_jitter(P)` | Random in `[ceil(Delay * P / 100), Delay]`, so at least `P`% of the delay. |

```erlang
dew_retry:run(fun connect/0, #{
  max_retries => 10,
  max_elapsed => timer:seconds(30),
  backoff => dew_retry:exponential(100, 5000),
  jitter => dew_retry:equal_jitter()
}).
