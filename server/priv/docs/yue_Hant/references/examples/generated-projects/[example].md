---
{
  "editLink": false,
  "titleTemplate": ":title · 範例 · 參考資料 · Tuist"
}
---
<script setup>
import { useData } from 'vitepress'

// params is a Vue ref
const { params } = useData()

</script>

<!-- @content -->

<a :href="params.url" target="blank">查看範例</a>
