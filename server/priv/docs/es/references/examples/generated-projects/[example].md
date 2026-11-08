---
{
  "editLink": false,
  "titleTemplate": ":title · Ejemplos · Referencias · Tuist"
}
---
<script setup>
import { useData } from 'vitepress'

// params is a Vue ref
const { params } = useData()

</script>

<!-- @content -->

<a :href="params.url" target="blank">Ver ejemplo</a>
