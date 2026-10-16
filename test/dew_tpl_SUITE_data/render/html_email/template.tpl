{{ include "header" }}
<p>Hi {{ customer.name }},</p>
{{ if orders }}
<p>You have {{ length(orders) }} {{ plural(length(orders), "order", "orders") }}:</p>
<table>
  {{ for order in orders }}
  <tr class="{{ if loop.index0 == 0 }}first{{ else if loop.last }}last{{ else }}middle{{ end }}">
    <td>{{ loop.index }}</td>
    <td>{{ order.item }}</td>
    <td>{{ money(order.cents) }} {{ currency }}</td>
  </tr>
  {{ end }}
</table>
{{ else }}
<p>You have no orders yet.</p>
{{ end }}
<div class="note">{{ raw(note_html) }}</div>
<p>{{ customer.comment }}</p>
{{ include "footer" }}
