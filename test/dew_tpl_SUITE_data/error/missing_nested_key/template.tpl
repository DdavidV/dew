{{ for order in orders }}
{{ for line in order.lines }}
{{ line.product.name }}
{{ end }}
{{ end }}
