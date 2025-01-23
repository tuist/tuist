<script setup></script>

<template>
    <div class="community">
        <slot></slot>
    </div>
</template>

<style scoped>
.community {
    display: grid;
    position: relative;
    grid-template-columns: repeat(2, 1fr);
    gap: 2rem;

    @media (max-width: 960px) {
        grid-template-columns: repeat(1, 1fr);
    }
}
</style>
