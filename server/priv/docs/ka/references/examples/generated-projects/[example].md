---
{
  "editLink": false,
  "titleTemplate": ":title · მაგალითები · მითითებები · Tuist"
}
---
<script setup>
import { useData } from 'vitepress'

// params is a Vue ref
const { params } = useData()

</script>

<!-- @content -->

<a :href="params.url" target="blank">იხილეთ მაგალითი</a>
