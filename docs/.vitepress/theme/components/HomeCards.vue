<template>
    <div class="HomeCards">
        <slot></slot>
    </div>
</template>

<style scoped>
.HomeCards {
    display: grid;
    position: relative;
    grid-template-columns: repeat(2, 1fr);
    gap: 2rem;
}
</style>
