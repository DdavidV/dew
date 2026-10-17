# dew_diff

Structural diff for Erlang terms.

`dew_diff` compares two Erlang terms and returns a compact list of operations that describes how to
get from the old value to the new one. The diff can be applied to the old value to reproduce the new
one, applied in reverse to go back, and printed in a human readable form.

## Functions

| Function | Description |
| --- | --- |
| `diff(Old, New)` | Computes the diff with default options. |
| `diff(Old, New, Options)` | Computes the diff, see [Diff options](#diff-options). |
| `apply_diff(From, Diff)` | Applies a diff to a term. |
| `apply_diff(From, Diff, Options)` | Applies a diff, see [Apply options](#apply-options). |
| `pretty_print(Diff)` | Formats a diff as text. |
| `make_add_op/2`, `make_remove_op/2`, `make_replace_op/3` | Build diff entries by hand. |
| `make_map_key/1`, `make_list_index/1` | Build path steps by hand. |

## How terms are compared

- **Equal terms** (`=:=`) produce no operations.
- **Maps** are compared key by key. Keys only in the old map produce a `remove`, keys only in the new
  map produce an `add`, and keys in both maps are diffed recursively.
- **Lists** are compared with the Longest Common Subsequence (LCS) algorithm. A dynamic-programming
  matrix measures how much of the old list still matches the new list, then the matrix is
  backtracked to build a minimal edit script of add, remove and equal steps. Those steps become diff
  entries. If removed and added elements sit next to each other at the same position, they are
  paired and diffed recursively, so a changed element inside a list yields a nested diff, not a
  remove followed by an add.
- **Anything else** (numbers, atoms, tuples, binaries, or values of different types) produces a
  single `replace` at the current path.

## Diff format

A diff is a list of maps:

```erlang
-type diff() :: #{
  path := [path()],
  operation := add | remove | replace,
  value := term(),           % the added, removed or new value
  old_value => term()        % only for replace
}.

-type path() :: #{type := map, key := term()}
              | #{type := list, index := non_neg_integer()}.
```

`path` is the list of steps from the root of the term to the changed location. An empty path means
the root itself was replaced.

```erlang
1> dew_diff:diff(#{a => 1, b => [1, 2, 3]}, #{a => 2, b => [1, 3, 4], c => x}).
[#{operation => replace, path => [#{type => map, key => a}], value => 2, old_value => 1},
 #{operation => remove,  path => [#{type => map, key => b}, #{type => list, index => 1}], value => 2},
 #{operation => add,     path => [#{type => map, key => b}, #{type => list, index => 2}], value => 4},
 #{operation => add,     path => [#{type => map, key => c}], value => x}]
```

List indexes refer to the list as it looks while the operations are applied in order, so the diff
above is meant to be applied front to back.

## Diff options

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `list` | map | `#{}` | Options for list diffing. |
| `list.zero_based` | `boolean()` | `true` | When `false`, list indexes in the paths start at 1. |

```erlang
2> dew_diff:diff([1, 2, 3], [1, 3, 4], #{list => #{zero_based => false}}).
[#{operation => remove, path => [#{type => list, index => 2}], value => 2},
 #{operation => add,    path => [#{type => list, index => 3}], value => 4}]
```

`apply_diff` always treats indexes as zero based, so only diffs made with the default setting can be
applied. One-based indexes are meant for display.

## Applying a diff

```erlang
3> Diff = dew_diff:diff([1, 2, 3], [1, 3, 4]).
4> dew_diff:apply_diff([1, 2, 3], Diff).
[1, 3, 4]
5> dew_diff:apply_diff([1, 3, 4], Diff, #{reverse => true}).
[1, 2, 3]
```

Operations are applied one after the other:

- `add` inserts the value into a list at the index, or puts the key into a map.
- `remove` deletes the list element at the index, or the key from a map.
- `replace` replaces the list element or map value, or the whole term when the path is empty.

### Apply options

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `reverse` | `boolean()` | `false` | Undo the diff: walk the operations backwards, turn `add` into `remove`, `remove` into `add` and `replace` back to `old_value`. Use it to get the old term from the new one. |

## Pretty printing

`pretty_print/1` renders a diff as text. Each entry starts with `+` (add), `-` (remove) or `~`
(replace) and the dot-separated path, followed by the value (or the old and the new value for a
replace):

```erlang
6> io:format("~s", [dew_diff:pretty_print(
       dew_diff:diff(#{a => 1, b => [1, 2]}, #{a => 2, b => [1], c => x}))]).
~ a
  1
  2

- b.1
  2

+ c
  x
```

Map keys in the path are printed with `atom_to_list/1`, so pretty printing expects atom keys.

## Building diffs by hand

The constructors build entries in the same format `diff/2,3` returns, which is useful when a diff is
produced by something other than `diff/2,3` (for example, received over the network) or in tests:

```erlang
Path = [dew_diff:make_map_key(users), dew_diff:make_list_index(0)],
Diff = [dew_diff:make_replace_op(Path, <<"old">>, <<"new">>)],
dew_diff:apply_diff(#{users => [<<"old">>]}, Diff).
%% #{users => [<<"new">>]}
```
