# dew_app

OTP application introspection utilities.

`dew_app` resolves the dependency structure of OTP applications. Given one or more applications it
walks their `applications` key (as declared in the `.app` file) recursively and returns the result
either as a nested tree or as a flat adjacency map (graph).

## Functions

| Function | Description |
| --- | --- |
| `deps/0` | Dependencies of every loaded application, as a tree. |
| `deps(Application)` | Dependencies of a single application. |
| `deps(Applications)` | Dependencies of a list of applications. |
| `deps(Options)` | Dependencies of every loaded application, using `Options`. |
| `deps(ApplicationOrApplications, Options)` | Dependencies of the given application(s), using `Options`. |

"Loaded applications" means the ones returned by `application:loaded_applications/0`.

## Result formats

### Tree (default)

A list with one tree per requested application. Every node is a map with the application name and
the list of its own dependency trees:

```erlang
1> dew_app:deps(stdlib).
[#{application => stdlib,
   dependencies => [#{application => kernel, dependencies => []}]}]
```

```erlang
-type dependency_tree() :: #{
  application := atom(),
  dependencies := [dependency_tree()]
}.
```

A shared dependency appears under every application that depends on it.

### Graph

A map from every application found while walking the tree to the list of its direct dependencies:

```erlang
2> dew_app:deps([stdlib], #{result_type => graph}).
#{kernel => [], stdlib => [kernel]}
```

```erlang
-type dependency_graph() :: #{atom() => [atom()]}.
```

## Options

Options are passed as a map. Every key is optional.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `result_type` | `tree \| graph` | `tree` | Shape of the result, see [Result formats](#result-formats). |
| `dep_resolver` | `fun((atom()) -> [atom()])` | reads `application:get_key(App, applications)` | Returns the direct dependencies of an application. |

### `dep_resolver`

The default resolver returns the `applications` key of the application, or `[]` if the application
is not loaded. A custom resolver lets you build the tree from any source, for example to include
`included_applications`, to filter out OTP applications, or to analyse a dependency structure that
is not loaded into the VM:

```erlang
3> Deps = #{a => [b, c], b => [c], c => []}.
4> dew_app:deps(a, #{dep_resolver => fun(App) -> maps:get(App, Deps) end}).
[#{application => a,
   dependencies =>
     [#{application => b,
        dependencies => [#{application => c, dependencies => []}]},
      #{application => c, dependencies => []}]}]
5> dew_app:deps(a, #{dep_resolver => fun(App) -> maps:get(App, Deps) end,
                     result_type => graph}).
#{a => [b, c], b => [c], c => []}
```

Each application is resolved only once per call: results are cached while the tree is built, which
also makes the walk terminate on cyclic dependencies.
