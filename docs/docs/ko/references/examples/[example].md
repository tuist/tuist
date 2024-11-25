---
editLink: false
titleTemplate: :title · Examples · References · Tuist
description: "{{ $params.description }}"
---

<script setup>
import { useData } from 'vitepress'

// params is a Vue ref
const { params } = useData()

</script>

<!-- @content -->

<a :href="params.url" target="blank">예제 확인</a>
