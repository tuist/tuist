---
{
  "editLink": false,
  "titleTemplate": ":title · Örnekler · Referanslar · Tuist"
}
---
<script setup>
import { useData } from 'vitepress'

// params is a Vue ref
const { params } = useData()

</script>

<!-- @content -->

<a :href="params.url" target="blank">Örneği inceleyin</a>
