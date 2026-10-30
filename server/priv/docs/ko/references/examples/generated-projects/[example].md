---
{
  "editLink": false,
  "titleTemplate": ":title · 예제 · 레퍼런스 · Tuist"
}
---
<script setup>
import { useData } from 'vitepress'

// params is a Vue ref
const { params } = useData()

</script>

<!-- @content -->

<a :href="params.url" target="blank">예제 살펴보기</a>
