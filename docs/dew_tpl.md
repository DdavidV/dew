# dew_tpl

A small, fast text templating engine with conditionals, loops, case, partials and custom functions.

Templates are compiled once into a tree of closures and can then be rendered many times with
different data. The engine is not tied to any output format: it works for HTML, emails, Markdown,
configuration files or generated source code.

Every public function returns `{ok, Value}` or `{error, Error}`. Errors are maps that describe what
went wrong and where (line, column, template name), and `format_error/1` turns them into readable
messages. Rendering never raises, not even when a user supplied function crashes.

## Functions

| Function | Description |
| --- | --- |
| `compile(Source)` | Compiles a template source (binary or string). |
| `compile(Source, Options)` | Compiles with [compile options](#compile-options). |
| `compile_file(Path)` | Reads and compiles a template file. |
| `compile_file(Path, Options)` | Reads and compiles a file with compile options. |
| `render(Template, Data)` | Renders a compiled template, or compiles and renders a source. |
| `render(Template, Data, Options)` | Renders with [render options](#render-options) (and compile options when given a source). |
| `format_error(Error)` | Formats an error from this module as a binary message. |
| `escape_html(Value)` | Escapes `&`, `<`, `>`, `"` and `'` for HTML. |

## Quick start

```erlang
1> dew_tpl:render(<<"Hello {{ user.name | upper }}!">>, #{user => #{name => <<"david">>}}).
{ok, <<"Hello DAVID!">>}

2> {ok, Tpl} = dew_tpl:compile(<<"{{ for item in items }}- {{ item }}\n{{ end }}">>).
3> dew_tpl:render(Tpl, #{items => [apple, pear]}).
{ok, <<"- apple\n- pear\n">>}
```

`Data` must be a map or a proplist. Compile a template once and render it many times when you can:
`render/2,3` with a source compiles it on every call.

## Syntax

Everything outside `{{ ... }}` is copied to the output as is.

| Syntax | Meaning |
| --- | --- |
| `{{ expr }}` | Output the value of an expression. |
| `{{ if cond }} … {{ else if cond }} … {{ else }} … {{ end }}` | Conditional. |
| `{{ for item in list }} … {{ else }} … {{ end }}` | Loop, `else` runs when the collection is empty. |
| `{{ for index, item in list }} … {{ end }}` | Loop with the zero-based index. |
| `{{ for key, value in map }} … {{ end }}` | Loop over a map, sorted by key. |
| `{{ case expr }}{{ when a, b }} … {{ when c }} … {{ else }} … {{ end }}` | Match a value against alternatives. |
| `{{ include "name" }}` | Render a partial with the current data. |
| `{{ include "name" expr }}` | Render a partial with `expr` as its data. |
| `{{# comment #}}` | Comment, produces no output. Can span lines. |

### Values and paths

| Expression | Meaning |
| --- | --- |
| `name` | Top level key of the data. |
| `user.name` | Nested key in maps and proplists. |
| `items[0]` | Zero-based index into a list or a tuple, or an integer key of a map. |
| `map["some key"]` | Key that is not a valid identifier. |
| `"text"`, `'text'` | String literal. Supports `\n`, `\t`, `\r` and `\` before any other character (`\"`). |
| `42`, `-1`, `1.5` | Integer and float literals. |
| `true`, `false`, `nil` | Literals. |
| `( expr )` | Grouping. |

How keys are looked up in the data (atoms, binaries, …) is set by the [`keys`](#keys) option.

Values are rendered as text like this: binaries as is, charlists as UTF-8, integers and floats in
their shortest form, atoms by name, and `undefined`, `nil` and `null` as nothing. Any other value
(tuples, maps, non-text lists, pids, …) is an `unrenderable_value` error.

### Operators

| Operator | Description |
| --- | --- |
| `==`, `!=` | Equality. Numbers compare by value (`1 == 1.0`). Atoms, binaries and charlists with the same text are equal, so `role == "admin"` matches the atom `admin`. `nil`, `undefined` and `null` are equal to each other. |
| `<`, `<=`, `>`, `>=` | Ordering of two numbers or two text values. Anything else is a `type_mismatch` error. |
| `and`, `or` | Return one of their operands, like in Lua or JavaScript: `{{ nickname or name }}` outputs `nickname` if it is truthy, `name` otherwise. |
| `not` | Negation. |
| `x \| f(y)` | Pipe, the same as `f(x, y)`. |

**Falsy values** are `false`, `undefined`, `nil`, `null`, `[]`, `<<>>` and `#{}`. Everything else is
truthy.

### Loops

Inside a `for` body the `loop` variable describes the current iteration:

| Field | Description |
| --- | --- |
| `loop.index` | Position, starting at 1. |
| `loop.index0` | Position, starting at 0. |
| `loop.first` | `true` on the first iteration. |
| `loop.last` | `true` on the last iteration. |
| `loop.length` | Number of elements. |

```
{{ for name in names }}{{ name }}{{ if not loop.last }}, {{ end }}{{ end }}
```

Maps are iterated in key order. Looping over `nil`, `undefined` or `null` runs the `else` branch.
Looping over anything else that is not a list or a map is a `not_iterable` error. In nested loops,
`loop` always refers to the innermost loop.

### Case

```
{{ case role }}
{{ when "dev", "ops" }}
Technical staff
{{ when "pm" }}
Product
{{ else }}
Other
{{ end }}
```

`when` alternatives use the same equality as `==`. Only whitespace is allowed between `case` and the
first `when`.

### Standalone lines

A line that contains only a block tag (`if`, `else`, `else if`, `end`, `for`, `case`, `when`,
`include` or a comment) and whitespace is removed from the output entirely, including its line
break. This means you can put block tags on their own lines without leaving blank lines in the
output, as in the `case` example above.

### Partials

Partials are other templates included by name. They are passed with the `partials` render option:

```erlang
4> dew_tpl:render(<<"{{ for u in users }}{{ include \"row\" u }}{{ end }}">>,
                  #{users => [#{name => <<"David">>}, #{name => <<"Joe">>}]},
                  #{partials => #{row => <<"<li>{{ name }}</li>">>}}).
{ok, <<"<li>David</li><li>Joe</li>">>}
```

`{{ include "name" }}` renders the partial with the data of the including template, and
`{{ include "name" expr }}` renders it with `expr` as its data. Loop variables are not visible inside
a partial. Partials can include other partials, and can include themselves for recursive structures
such as trees, up to `max_include_depth` levels.

## Built-in functions

| Function | Description |
| --- | --- |
| `upper(x)` | Uppercase text. |
| `lower(x)` | Lowercase text. |
| `trim(x)` | Removes leading and trailing whitespace. |
| `length(x)` | Characters of a binary, elements of a list or tuple, size of a map. `0` for `nil`. |
| `join(list, sep)` | Joins the elements of a list as text, separated by `sep`. |
| `truncate(x, n)` | The first `n` characters of `x`. |
| `escape(x)` | HTML-escapes `x`. Use it when `escape_fun` is not set; with `escape_fun` set the output is escaped twice. |
| `raw(x)` | Outputs `x` without applying `escape_fun`. |
| `default(x, fallback)` | `x` if it is truthy, `fallback` otherwise. Also works when `x` is a missing key. |
| `defined(x)` | `true` if the key `x` exists in the data, `false` if it is missing. |

Any function can be used as a pipe stage: `{{ name | trim | truncate(20) }}`.

## Options

Options are a single map. `compile/2`, `compile_file/2` and `render/3` all accept the same map. Each
function uses the keys it needs and validates every key it is given. Unknown keys and invalid values
return `{error, #{reason := {invalid_option, Key, Value}}}`.

```erlang
5> dew_tpl:render(<<"{{ x }}">>, #{}, #{bogus => 1}).
{error, #{phase => compile, reason => {invalid_option, bogus, 1}}}
```

### Compile options

Used when a template is compiled. `render/3` also uses them when it is given a source instead of a
compiled template.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `name` | binary, string or atom | none (`compile_file` uses the path) | Label for the template in errors. |
| `keys` | `atom \| binary \| string \| fun((binary()) -> Key)` | `atom` | How keys are looked up in the data. |
| `functions` | `#{Name => fun}` | `#{}` | Custom functions callable from the template. |
| `escape_fun` | `fun((binary()) -> iodata()) \| none` | `none` | Applied to every `{{ expr }}` output. |

#### `name`

The name appears in the `template` key of error maps and as the prefix of `format_error/1` messages
(`page.tpl:3:5: ...`). It does not affect the output. A compiled template keeps its name, so `name`
given to `render/3` with a compiled template is ignored.

#### `keys`

Controls the type of the keys that `user.name` and `map["key"]` look up in maps and proplists:

- `atom` (default) looks up atom keys. It never creates atoms: a name that is not an existing atom
  is a missing key.
- `binary` looks up binary keys, for example data decoded from JSON.
- `string` looks up charlist keys.
- A `fun((binary()) -> Key)` converts the name in any way you need.

Keys are converted once, at compile time.

```erlang
6> dew_tpl:render(<<"{{ user.name }}">>, #{<<"user">> => #{<<"name">> => <<"David">>}},
                  #{keys => binary}).
{ok, <<"David">>}
```

#### `functions`

A map from name to fun. The functions can be called as `name(...)` or used as a pipe stage
`x | name(...)`. Names are atoms or binaries, and they override built-ins with the same name.

```erlang
7> Money = fun(Cents) -> io_lib:format("~.2f", [Cents / 100]) end.
8> dew_tpl:render(<<"Total: {{ total | money }} EUR">>, #{total => 1250},
                  #{functions => #{money => Money}}).
{ok, <<"Total: 12.50 EUR">>}
```

- Calling an unknown function or calling one with the wrong number of arguments is a compile error.
- A function may return any renderable value, or another value for further processing (for example a
  list for `join`).
- Returning `{error, Reason}` turns into a `{function_error, Name, Reason}` render error.
- A crash turns into a `{function_crashed, Name, Class, Reason}` render error.

#### `escape_fun`

A function applied to the text of every `{{ expr }}` output, except `raw(...)`. Use
`fun dew_tpl:escape_html/1` for HTML:

```erlang
9> dew_tpl:render(<<"{{ comment }} {{ raw(html) }}">>,
                  #{comment => <<"<script>">>, html => <<"<b>ok</b>">>},
                  #{escape_fun => fun dew_tpl:escape_html/1}).
{ok, <<"&lt;script&gt; <b>ok</b>">>}
```

Template text outside of tags is never escaped.

### Render options

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `missing` | `error \| empty` | `error` | What happens when a key is missing. |
| `partials` | `#{Name => Template \| Source}` | `#{}` | Partials for `{{ include "Name" }}`. |
| `output` | `binary \| iodata` | `binary` | Type of the rendered output. |
| `max_include_depth` | `non_neg_integer()` | `32` | How deep includes may nest. |

#### `missing`

- `error` makes a missing key a `{missing_key, Path}` render error.
- `empty` renders missing keys as nothing and treats them as falsy and empty in `if` and `for`.

`default(...)` and `defined(...)` handle missing keys in both modes. Note that `{{ a or b }}` with
`missing => error` needs `a` to exist (it can be falsy). Use `default(a, b)` when `a` may be missing.

#### `partials`

Names can be atoms, binaries or strings. Values are compiled templates or sources. Sources are
compiled with the compile options of the including template on every render, so compile them in
advance when performance matters. Errors inside a partial are reported with the partial's name as
`template` and an `include_stack` listing the chain of includes.

#### `output`

`binary` returns a single binary. `iodata` skips the final conversion and returns the iodata as
built, which is cheaper when the output goes straight to a socket or a file.

#### `max_include_depth`

The maximum nesting depth of includes. Going deeper is an `include_depth_exceeded` error, which
usually means a partial includes itself without an end condition.

## Errors

An error is a map:

```erlang
-type error() :: #{
  phase := compile | render,
  reason := term(),
  line => pos_integer(),
  column => pos_integer(),
  template => binary(),        % the template's name, when it has one
  snippet => binary(),         % the source line, for compile errors
  include_stack => [binary()]  % the chain of partials, outermost first
}.
```

`format_error/1` turns it into a readable message, with a caret pointing at the column for compile
errors:

```erlang
10> {error, E} = dew_tpl:compile(<<"Hi\n{{ if x }}\n{{ foo(1) }}">>, #{name => page}).
11> io:format("~s~n", [dew_tpl:format_error(E)]).
page:3:4: unknown function 'foo'
    {{ foo(1) }}
       ^
```

### Compile errors

| Reason | Cause |
| --- | --- |
| `unclosed_tag` | `{{` without `}}`. |
| `unclosed_comment` | `{{#` without `#}}`. |
| `{unexpected_character, Char}` | A character that is not valid inside a tag. |
| `unterminated_string` | A string literal without a closing quote. |
| `{unexpected_token, Token}`, `unexpected_end_of_expression`, `empty_tag` | Invalid expression. |
| `{unclosed_block, Block}` | `if`, `for` or `case` without `{{ end }}`. |
| `{unexpected_tag, Tag}` | `else`, `else if`, `end` or `when` in the wrong place. |
| `{reserved_word, Word}` | A keyword used as a name. |
| `{unknown_function, Name}` | A function that is neither built in nor in `functions`. |
| `{bad_arity, Name, Expected, Got}` | Wrong number of arguments. |
| `{unknown_loop_field, Field}` | `loop.x` with an unknown field. |
| `content_before_when` | Non-whitespace between `case` and the first `when`. |
| `{invalid_source, Source}` | The source is not a binary or a string. |
| `{file, Posix}` | `compile_file` could not read the file. |
| `{invalid_option, Key, Value}` | Invalid option. |

### Render errors

| Reason | Cause |
| --- | --- |
| `{missing_key, Path}` | A key is missing and `missing` is `error`. |
| `{not_accessible, Path, Value}` | A key or index is used on a value that is not a map, list or tuple. |
| `{not_iterable, Value}` | `for` over something that is not a list or a map. |
| `{unrenderable_value, Value}` | A value that cannot be rendered as text. |
| `{type_mismatch, Operator, Left, Right}` | Ordering values of different kinds. |
| `{bad_argument, Name, Value}` | Invalid argument to a built-in function. |
| `{function_error, Name, Reason}` | A custom function returned `{error, Reason}`. |
| `{function_crashed, Name, Class, Reason}` | A custom function or `escape_fun` crashed. |
| `{partial_not_found, Name}` | `include` of an unknown partial. |
| `include_depth_exceeded` | Includes nested deeper than `max_include_depth`. |
| `{bad_data, Data}` | `Data` is not a map or a list. |
| `{invalid_template, Term}` | `render` was given something that is not a template or a source. |
| `invalid_output` | `escape_fun` returned invalid iodata. |
| `{internal_error, Class, Reason}` | A bug in `dew_tpl`. Please report it. |
