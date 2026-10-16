{{ title }}: {{ for item in items }}{{ item.name }}={{ item.qty }}{{ if not loop.last }}, {{ end }}{{ end }}
