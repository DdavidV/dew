start
  {{ if show }}
  shown
  {{ end }}
{{# a standalone comment #}}
{{ for x in xs }}
  - {{ x }}
{{ end }}
inline {{ if show }}yes{{ end }} stays
{{ if show }}{{ if show }}
nested standalone
{{ end }}{{ end }}
end
