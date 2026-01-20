<script setup>
import { computed } from "vue";
import { useData } from "vitepress";

const { lang } = useData();

const nonLocalizedRoutes = [
  "/cli",
  "/references/project-description",
];

const props = defineProps({
  href: {
    type: String,
    required: true,
    validator: (value) => {
      // Basic validation during development
      if (import.meta.env.DEV && (!value || !value.startsWith('/'))) {
        console.warn(`LocalizedLink: href should start with '/', got: ${value}`);
        return false;
      }
      return true;
    }
  }
});

const resolvedLocale = computed(() => {
  const href = props.href ?? "";
  const isNonLocalized = nonLocalizedRoutes.some(
    (route) => href === route || href.startsWith(`${route}/`),
  );
  return isNonLocalized ? "en" : lang.value;
});

const resolvedHref = computed(() => `/${resolvedLocale.value}${props.href}`);

// Log invalid links in development mode
if (import.meta.env.DEV && props.href) {
  // This can help catch issues during development
  const fullHref = resolvedHref.value;
  
  // Warn about common issues
  if (props.href.includes('.html')) {
    console.warn(`LocalizedLink: href contains .html extension, consider removing it: ${props.href}`);
  }
  
  if (props.href.includes('//')) {
    console.warn(`LocalizedLink: href contains double slashes: ${props.href}`);
  }
}
</script>

<template>
    <a 
      :href="resolvedHref"
      :data-original-href="href"
      :data-localized-href="resolvedHref"
    >
      <slot></slot>
    </a>
</template>
