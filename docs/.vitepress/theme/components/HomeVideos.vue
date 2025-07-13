<script setup>
import { ref, onMounted, computed } from 'vue'

// Props for backwards compatibility (can pass static videos if needed)
const props = defineProps(["videos"])

const dynamicVideos = ref([])
const isLoading = ref(true)
const error = ref(null)

// Fetch videos from PeerTube API
const fetchVideos = async () => {
  try {
    const response = await fetch('https://videos.tuist.dev/api/v1/video-channels/tuist_videos/videos?count=6&sort=-publishedAt')
    
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`)
    }
    
    const data = await response.json()
    
    // Transform PeerTube data to match the expected format [title, videoId]
    dynamicVideos.value = data.data.map(video => [
      video.name,
      video.shortUUID
    ])
  } catch (err) {
    console.warn('Failed to fetch videos from PeerTube:', err)
    error.value = err
    
    // Fallback to hardcoded videos if API fails
    dynamicVideos.value = [
      ['Tuist Registry Walkthrough', '2bd2deb4-1897-4c5b-9de6-37c8acd16fb0'],
      ['Running latest Tuist Previews', '6872527d-4225-469d-9b89-2ec562c37603'],
      ['Inspect implicit imports to make Xcode more reliable and its builds more deterministic', '88696ce1-aa08-48e8-b410-bc7a57726d67'],
      ['Clean Xcode builds with binary XCFrameworks from Tuist Cloud', '3a15bae1-a0b2-4c6e-97f2-f78457d87099']
    ]
  } finally {
    isLoading.value = false
  }
}

onMounted(() => {
  // If videos prop is provided, use those instead of fetching
  if (!props.videos || props.videos.length === 0) {
    fetchVideos()
  }
})

// Use provided videos or fetched videos
const videosToDisplay = computed(() => {
  return props.videos && props.videos.length > 0 ? props.videos : dynamicVideos.value
})
</script>

<template>
    <div class="videos">
        <slot></slot>
        <div v-if="isLoading" class="loading">
            Loading latest videos...
        </div>
        <iframe
            v-else
            v-for="[title, videoId] in videosToDisplay"
            :key="videoId"
            :title="title"
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
