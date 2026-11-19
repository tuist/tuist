---
{
  "editLink": false,
  "titleTemplate": ":title · Примеры · Справочники · Tuist"
}
---
<script setup>
import { useData } from 'vitepress'

// params is a Vue ref
const { params } = useData()

</script>

<!-- @content -->

<a :href="params.url" target="blank">Посмотреть пример</a>
