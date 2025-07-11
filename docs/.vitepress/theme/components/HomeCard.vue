<script setup>
import LocalizedLink from "./LocalizedLink.vue";

const props = defineProps({
    icon: String,
    title: String,
    details: String,
    linkText: String,
    link: String,
    rel: { type: String, required: false },
    target: { type: String, required: false },
});

// Check if the link is external (starts with http:// or https://)
const isExternalLink = (url) => {
    return url && (url.startsWith('http://') || url.startsWith('https://'));
};
</script>

<template>
    <!-- Use regular <a> tag for external links -->
    <a
        v-if="isExternalLink(link)"
        class="HomeCard"
        :href="link"
        :rel="rel"
        :target="target || '_blank'"
    >
        <article class="box">
            <div v-if="typeof icon === 'object' && icon.wrap" class="icon">
                <VPImage
                    :image="icon"
                    :alt="icon.alt"
                    :height="icon.height || 48"
                    :width="icon.width || 48"
                />
            </div>
            <VPImage
                v-else-if="typeof icon === 'object'"
                :image="icon"
                :alt="icon.alt"
                :height="icon.height || 48"
                :width="icon.width || 48"
            />
            <div v-else-if="icon" class="icon" v-html="icon"></div>
            <h2 class="title" v-html="title"></h2>
            <p v-if="details" class="details" v-html="details"></p>

            <div v-if="linkText" class="link-text">
                <p class="link-text-value">
                    {{ linkText }}
                    <span class="vpi-arrow-right link-text-icon" />
                </p>
            </div>
        </article>
    </a>
    
    <!-- Use LocalizedLink for internal links -->
    <LocalizedLink
        v-else-if="link"
        class="HomeCard"
        :href="link"
        :rel="rel"
        :target="target"
    >
        <article class="box">
            <div v-if="typeof icon === 'object' && icon.wrap" class="icon">
                <VPImage
                    :image="icon"
                    :alt="icon.alt"
                    :height="icon.height || 48"
                    :width="icon.width || 48"
                />
            </div>
            <VPImage
                v-else-if="typeof icon === 'object'"
                :image="icon"
                :alt="icon.alt"
                :height="icon.height || 48"
                :width="icon.width || 48"
            />
            <div v-else-if="icon" class="icon" v-html="icon"></div>
            <h2 class="title" v-html="title"></h2>
            <p v-if="details" class="details" v-html="details"></p>

            <div v-if="linkText" class="link-text">
                <p class="link-text-value">
                    {{ linkText }}
                    <span class="vpi-arrow-right link-text-icon" />
                </p>
            </div>
        </article>
    </LocalizedLink>
    
    <!-- Use div for no link -->
    <div
        v-else
        class="HomeCard"
    >
        <article class="box">
            <div v-if="typeof icon === 'object' && icon.wrap" class="icon">
                <VPImage
                    :image="icon"
                    :alt="icon.alt"
                    :height="icon.height || 48"
                    :width="icon.width || 48"
                />
            </div>
            <VPImage
                v-else-if="typeof icon === 'object'"
                :image="icon"
                :alt="icon.alt"
                :height="icon.height || 48"
                :width="icon.width || 48"
            />
            <div v-else-if="icon" class="icon" v-html="icon"></div>
            <h2 class="title" v-html="title"></h2>
            <p v-if="details" class="details" v-html="details"></p>

            <div v-if="linkText" class="link-text">
                <p class="link-text-value">
                    {{ linkText }}
                    <span class="vpi-arrow-right link-text-icon" />
                </p>
            </div>
        </article>
    </div>
</template>

<style scoped>
LocalyzedLink {
    text-decoration: none;
}
.HomeCard {
    text-decoration: none;
    display: block;
    border: 1px solid var(--vp-c-bg-soft);
    border-radius: 12px;
    height: 100%;
    background-color: var(--vp-c-bg-soft);
    transition:
        border-color 0.25s,
        background-color 0.25s;

    &:hover {
        background-color: var(--vp-button-alt-hover-bg);
        & .title {
            color: var(--vp-c-brand-1);
        }
    }
}

.VPFeature.link:hover {
    border-color: var(--vp-c-brand-1);
}

.box {
    display: flex;
    flex-direction: column;
    padding: 24px;
    height: 100%;
}

.box > :deep(.VPImage) {
    margin-bottom: 20px;
}

.icon {
    display: flex;
    justify-content: center;
    align-items: center;
    margin-bottom: 20px;
    border-radius: 6px;
    background-color: var(--vp-c-default-soft);
    width: 48px;
    height: 48px;
    font-size: 24px;
    transition: background-color 0.25s;
}

.title {
    line-height: 24px;
    font-size: 16px;
    font-weight: 600;
    border-width: 0;
    margin-top: 0;
    padding-top: 0;
    color: var(--vp-c-text-1);
}

.details {
    flex-grow: 1;
    padding-top: 8px;
    line-height: 24px;
    font-size: 14px;
    font-weight: 500;
    color: var(--vp-c-text-2);
}

.link-text {
    padding-top: 8px;
}

.link-text-value {
    display: flex;
    align-items: center;
    font-size: 14px;
    font-weight: 500;
    color: var(--vp-c-brand-1);
}

.link-text-icon {
    margin-left: 6px;
}
</style>
