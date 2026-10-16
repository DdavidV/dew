-module({{ module }}).

-export([
{{ for f in fields }}
  {{ f.name }}/1{{ if not loop.last }},{{ end }}
{{ end }}
]).

-record({{ record }}, {
{{ for f in fields }}
  {{ f.name }}{{ if defined(f.default) }} = {{ f.default }}{{ end }} :: {{ f.type }}{{ if not loop.last }},{{ end }}
{{ end }}
}).
{{ for f in fields }}

{{ f.name }}(#{{ record }}{ {{ f.name }} = Value }) ->
  Value.
{{ end }}
