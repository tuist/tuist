<script setup>
defineProps(["type"]);
</script>

<template>
    <div :class="`HomeCards ${type}`">
        <slot></slot>
    </div>
</template>

<style scoped>
.HomeCards:not(.carousel) {
    display: grid;
    position: relative;
    grid-template-columns: repeat(2, 1fr);
    gap: 2rem;

    @media (max-width: 960px) {
        grid-template-columns: repeat(1, 1fr);
    }
}
.HomeCards.carousel {
    display: grid;
    position: relative;
    grid-template-columns: repeat(auto-fill, 300px);
    gap: 2rem;
    grid-auto-flow: column;
    grid-auto-columns: 300px;
    overflow-x: auto;
    overscroll-behavior-x: contain;
    scroll-snap-type: x mandatory;
    padding-bottom: 1rem;
    &::-webkit-scrollbar {
        display: none;
    }
    scrollbar-width: none;
}
</style>
