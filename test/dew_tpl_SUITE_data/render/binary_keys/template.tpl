{{ for user in users }}
{{ user.name }} <{{ user["e-mail"] }}> {{ case user.role }}{{ when "admin" }}[A]{{ else }}[U]{{ end }}
{{ end }}
