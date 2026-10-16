# generated for {{ env }}
{{ case env }}
{{ when "prod", "production" }}
log_level = warning
{{ when "staging" }}
log_level = info
{{ else }}
log_level = debug
{{ end }}

[server]
{{ for key, value in server }}
{{ key }} = {{ value }}
{{ end }}

[upstreams]
{{ for i, host in upstreams }}
upstream_{{ i }} = {{ host.name }}:{{ default(host.port, 80) }}{{ if default(host.backup, false) }} backup{{ end }}
{{ else }}
# no upstreams
{{ end }}
features = {{ join(features, ",") }}
