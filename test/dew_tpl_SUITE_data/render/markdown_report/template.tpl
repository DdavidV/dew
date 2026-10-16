# {{ title }}

{{ for section in sections }}
## {{ loop.index }}. {{ section.name }}

{{ for row in section.rows }}
- {{ row.label | truncate(12) }}: {{ case row.status }}{{ when "ok" }}✅{{ when "warn" }}⚠️{{ else }}❌{{ end }} ({{ row.value }})
{{ else }}
_No data._
{{ end }}

{{ end }}
Total sections: {{ length(sections) }}
Tags: {{ join(tags, " · ") }}
