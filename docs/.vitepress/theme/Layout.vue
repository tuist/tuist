<script setup lang="ts">
import DefaultTheme from "vitepress/theme";
import { useData } from "vitepress";
import { watchEffect } from "vue";
const inBrowser = typeof document !== "undefined";

const { lang } = useData();
watchEffect(() => {
    if (inBrowser) {
        document.cookie = `nf_lang=${lang.value}; expires=Mon, 1 Jan 2030 00:00:00 UTC; path=/`;
    }
});
</script>

<template>
    <DefaultTheme.Layout />
</template>
