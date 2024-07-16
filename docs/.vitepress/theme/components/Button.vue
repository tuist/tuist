<script>
export default {
  props: {
    title: String,
    href: String
  }
}
</script>

<template>
    <a class="button_link" :href="href">
        <span class="button_link_content">{{title}}</span>
    </a>
</template>

<style scoped>
.button_link {
    display: flex;
    align-items: center;
    font-size: 14px;
    font-weight: 500;
}
.button_link_content {
    background: var(--vp-c-brand-1);
    color: var(--vp-button-brand-text);
    padding: 3px 8px;
    border-radius: 4px;

    &:hover {
        background: var(--vp-c-brand-2);
    }
}
</style>