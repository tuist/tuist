---
{
  "editLink": false,
  "titleTemplate": ":title · Examples · References · Tuist"
}
---
<script setup>
import { useData } from 'vitepress'

// params is a Vue ref
const { params } = useData()
</script>

<!-- @content -->

<a :href="params.url" target="blank">Check out example</a>
