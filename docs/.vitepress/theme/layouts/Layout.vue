<script setup lang="ts">
import DefaultTheme from "vitepress/theme";
import { useData } from "vitepress";
import { computed, watchEffect } from "vue";
const inBrowser = typeof document !== "undefined";
import { localizedString } from "../../i18n.mjs";

const { lang } = useData();
watchEffect(() => {
    if (inBrowser) {
        document.cookie = `nf_lang=${lang.value}; expires=Mon, 1 Jan 2030 00:00:00 UTC; path=/`;
    }
});
const showAsideBottom = computed(() => lang.value !== "en");
</script>

<template>
    <DefaultTheme.Layout>
        <template #aside-bottom v-if="showAsideBottom"
            ><div class="tip custom-block">
                <p class="custom-block-title">
                    {{ localizedString(lang, "aside.translate.title.text") }}
                </p>
                <p>
                    {{
                        localizedString(
                            lang,
                            "aside.translate.description.text",
                        )
                    }}
                </p>
                <p>
                    <a :href="`/${lang}/contributors/translate`">{{
                        localizedString(lang, "aside.translate.cta.text")
                    }}</a>
                </p>
            </div></template
        >
    </DefaultTheme.Layout>
</template>
