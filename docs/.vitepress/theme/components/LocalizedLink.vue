<script setup>
import { useData } from "vitepress";

const { lang } = useData();

defineProps(["href"]);
</script>

<template>
    <a :href="`/${lang}${href}`"><slot></slot></a>
</template>
