---
editLink: false
description: {{ $params.description }}
---

<script setup>
import { useData } from 'vitepress'

// params is a Vue ref
const { params } = useData()

</script>

<!-- @content -->

<a :href="params.url" target="blank">Check out example</a>
