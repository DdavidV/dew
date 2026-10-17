-module(dew_retry).

-type context() :: #{
  start_time := integer(),
  elapsed := integer(),
  attempt := integer(),
  retries := integer(),
  previous_delay := integer() | undefined,
  result := term()
}.

-type retry_eval_fun() :: fun((context()) -> stop | retry).
-type retry_logger_fun() :: fun((context()) -> ok).
-type backoff_fun() :: fun((context()) -> integer()).
-type jitter_fun() :: fun((integer(), context()) -> integer()).

-type options() :: #{
  max_retries => integer() | infinity,
  max_elapsed => integer() | infinity,
  retry_eval => retry_eval_fun(),
  retry_logger => retry_logger_fun(),
  backoff => backoff_fun(),
  jitter => jitter_fun()
}.

-type run_function() :: fun(() -> term()) | {module(), atom()} | {module(), atom(), list()}.

-export_type([
  retry_eval_fun/0,
  retry_logger_fun/0,
  backoff_fun/0,
  jitter_fun/0,
  context/0,
  options/0,
  run_function/0
]).

-export([run/2]).

-export([
  constant/1,
  linear/1,
  exponential/1,
  exponential/2
]).

-export([
  no_jitter/0,
  full_jitter/0,
  equal_jitter/0,
  percent_range_jitter/1
]).

-spec run(Function, Options) -> Result when
  Function :: run_function(),
  Options :: options(),
  Result :: term().
run(Function, Options) ->
  DefaultOptions = #{
    max_retries => 0,
    max_elapsed => infinity,
    retry_eval => default_retry_eval(),
    retry_logger => default_retry_logger(),
    backoff => constant(0),
    jitter => no_jitter()
  },
  Context = #{
    start_time => erlang:monotonic_time(millisecond),
    elapsed => 0,
    attempt => 1,
    retries => 0,
    previous_delay => undefined,
    result => undefined
  },
  loop(Function, Context, maps:merge(DefaultOptions, Options)).

default_retry_eval() ->
  fun(#{result := Result}) ->
    case Result of
      {error, _} ->
        retry;
      _ ->
        stop
    end
  end.

default_retry_logger() ->
  fun(_Context) ->
    ok
  end.

-spec loop(Function, Context, Options) -> term() when
  Function :: run_function(),
  Context :: context(),
  Options :: options().
loop(Function, #{attempt := Attempt} = Context, #{retry_eval := EvalFun,
                                                  retry_logger := RetryLogger} = Options) ->
  Result = execute(Function),
  Elapsed = elapsed(Context),
  ContextAfterExecute = Context#{
    result => Result,
    elapsed => Elapsed
  },
  case EvalFun(ContextAfterExecute) of
    stop ->
      Result;
    retry ->
      case retry_allowed(ContextAfterExecute, Options) of
        true ->
          RetryLogger(ContextAfterExecute),
          ContextAfterDelay = delay(ContextAfterExecute, Options),
          NewContext = ContextAfterDelay#{
            attempt => Attempt + 1,
            retries => Attempt + 1
          },
          loop(Function, NewContext, Options);
        false ->
          Result
      end
  end.

execute(Fun) when is_function(Fun, 0) ->
  Fun();
execute({Module, Function}) when is_atom(Module) andalso is_atom(Function) ->
  erlang:apply(Module, Function, []);
execute({Module, Function, Arguments}) when is_atom(Module) andalso
                                            is_atom(Function) andalso
                                            is_list(Arguments) ->
  erlang:apply(Module, Function, Arguments).

-spec elapsed(Context) -> integer() when
  Context :: context().
elapsed(#{start_time := Start}) ->
  erlang:monotonic_time(millisecond) - Start.

-spec retry_allowed(Context, Options) -> boolean() when
  Context :: context(),
  Options :: options().
retry_allowed(#{elapsed := Elapsed,
                retries := Retries},
              #{max_elapsed := MaxElapsed,
                max_retries := MaxRetries}) ->
  is_allowed(Retries, MaxRetries) andalso is_allowed(Elapsed, MaxElapsed).

-spec is_allowed(Current, Max) -> boolean() when
  Current :: integer(),
  Max :: integer() | infinity.
is_allowed(_, infinity) ->
  true;
is_allowed(Current, Max) ->
  Current =< Max.

-spec delay(Context, Options) -> context() when
  Context :: context(),
  Options :: options().
delay(Context, #{backoff := Backoff, jitter := Jitter}) ->
  BackoffDelay = Backoff(Context),
  Delay = Jitter(BackoffDelay, Context),
  timer:sleep(Delay),
  Context#{previous_delay => Delay}.

-spec constant(Delay) -> Result when
  Delay :: integer(),
  Result :: backoff_fun().
constant(Delay) ->
  fun(_Context) ->
    Delay
  end.

-spec linear(Base) -> Result when
  Base :: integer(),
  Result :: backoff_fun().
linear(Base) ->
  fun(#{attempt := Attempt}) ->
    Base * Attempt
  end.
exponential(Base) ->
  exponential(Base, infinity).

-spec exponential(Base, Max) -> Result when
  Base :: integer(),
  Max :: integer() | infinity,
  Result :: backoff_fun().
exponential(Base, Max) ->
  fun(#{attempt := Attempt}) ->
    Delay = Base * (1 bsl (Attempt - 1)),
    min_delay(Delay, Max)
  end.

min_delay(Delay, infinity) ->
  Delay;
min_delay(Delay, Max) ->
  erlang:min(Delay, Max).

-spec no_jitter() -> Result when
  Result :: jitter_fun().
no_jitter() ->
  fun(Delay, _Context) ->
    Delay
  end.

-spec full_jitter() -> Result when
  Result :: jitter_fun().
full_jitter() ->
  fun(0, _Context) ->
    0;
  (Delay, _Context) ->
    rand:uniform(Delay) - 1
  end.

-spec equal_jitter() -> Result when
  Result :: jitter_fun().
equal_jitter() ->
  fun(0, _Context) ->
    0;
  (Delay, _Context) ->
    Half = Delay div 2,
    Half + rand:uniform(Delay - Half + 1) - 1
  end.

-spec percent_range_jitter(Percentile) -> Result when
  Percentile :: integer(),
  Result :: jitter_fun().
percent_range_jitter(Percentile) ->
  fun(Delay, _Context) when Delay >= 0 ->
    Min = (Delay * Percentile + 99) div 100,
    Min + rand:uniform(Delay - Min + 1) - 1
  end.
