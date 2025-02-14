<script setup>
defineProps(["videos"]);
</script>

<template>
    <div class="videos">
        <slot></slot>
        <iframe
            v-for="[title, videoId] in videos"
            :title
            width="336"
            height="189"
            :src="`https://videos.tuist.dev/videos/embed/${videoId}`"
            frameborder="0"
            allowfullscreen=""
            sandbox="allow-same-origin allow-scripts allow-popups allow-forms"
        ></iframe>
    </div>
</template>

<style scoped>
.videos {
    display: flex;
    flex-direction: row;
    gap: 3rem;
    overflow: scroll;
    padding-bottom: 2rem;
}
</style>
