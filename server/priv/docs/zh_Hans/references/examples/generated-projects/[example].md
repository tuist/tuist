---
{
  "editLink": false,
  "titleTemplate": ":title · 示例 · 参考文档 · Tuist"
}
---
<script setup>
import { useData } from 'vitepress'

// params is a Vue ref
const { params } = useData()

</script>

<!-- @content -->

<a :href="params.url" target="blank">查看示例</a>
