---
{
  "editLink": false,
  "titleTemplate": ":title · 例 · リファレンス · Tuist"
}
---
<script setup>
import { useData } from 'vitepress'

// params is a Vue ref
const { params } = useData()

</script>

<!-- @content -->

<a :href="params.url" target="blank">サンプルを確認</a>
