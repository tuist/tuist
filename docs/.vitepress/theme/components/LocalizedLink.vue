<script setup>
import { useData } from "vitepress";

const { lang } = useData();

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

// Log invalid links in development mode
if (import.meta.env.DEV && props.href) {
  // This can help catch issues during development
  const fullHref = `/${lang}${props.href}`;
  
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
      :href="`/${lang}${href}`"
      :data-original-href="href"
      :data-localized-href="`/${lang}${href}`"
    >
      <slot></slot>
    </a>
</template>
