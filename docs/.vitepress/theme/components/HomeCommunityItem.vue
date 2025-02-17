<script setup>
defineProps(["title", "description", "href"]);
</script>

<template>
    <a target="_blank" class="item" :href>
        <article>
            <div>
                <slot name="logo"></slot>
            </div>
            <div>
                <h2>{{ title }}</h2>
                <p>{{ description }}</p>
            </div>
        </article>
    </a>
</template>

<style scoped>
.item {
    text-decoration: none;

    & > article {
        display: flex;
        padding: 24px;
        flex-direction: row;
        gap: 1rem;
        border: 1px solid var(--vp-c-bg-soft);
        border-radius: 12px;
        height: 100%;
        background-color: var(--vp-c-bg-soft);
        transition:
            border-color 0.25s,
            background-color 0.25s;

        &:hover {
            background-color: var(--vp-button-alt-hover-bg);
            & h2 {
                color: var(--vp-c-brand-1);
            }
        }

        & h2 {
            text-decoration: none;
            margin-top: 0px;
            padding-top: 0px;
            border: 0px;
            line-height: 24px;
            font-size: 16px;
            font-weight: 600;
            color: var(--vp-c-text-1);
        }

        & p {
            text-decoration: none;
            font-size: 14px;
            font-weight: 500;
            color: var(--vp-c-text-2);
        }
    }
}
</style>
