name=[{{ user.name }}]
nick=[{{ user.nick or user.name or "anon" }}]
{{ if user.admin }}
admin
{{ else }}
not admin
{{ end }}
{{ for p in user.posts }}
{{ p }}
{{ else }}
no posts
{{ end }}
