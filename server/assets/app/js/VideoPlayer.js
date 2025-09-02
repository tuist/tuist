export default {
  mounted() {
    this.video = this.el;
    
    // Log video element and URL for debugging
    console.log("Video element mounted:", this.video);
    console.log("Video URL:", this.el.dataset.videoUrl);
    
    // Add event listeners for video loading
    this.video.addEventListener('loadstart', () => {
      console.log('Video load started');
    });
    
    this.video.addEventListener('loadedmetadata', () => {
      console.log('Video metadata loaded, duration:', this.video.duration);
    });
    
    this.video.addEventListener('error', (e) => {
      console.error('Video error:', e);
      console.error('Video error details:', this.video.error);
    });
    
    this.video.addEventListener('canplay', () => {
      console.log('Video can play');
    });
    
    // Set initial state from data attributes
    this.updateVideoState();
    
    // Listen for LiveView updates
    this.handleEvent("update_video_state", (state) => {
      this.updateVideoState();
    });
  },
  
  updated() {
    // Update video state when LiveView updates the element
    this.updateVideoState();
  },
  
  updateVideoState() {
    const currentTime = parseFloat(this.el.dataset.currentTime || "0");
    const isPlaying = this.el.dataset.isPlaying === "true";
    
    // Update current time if significantly different (avoid small drifts)
    if (Math.abs(this.video.currentTime - currentTime) > 0.5) {
      this.video.currentTime = currentTime;
    }
    
    // Play or pause based on state
    if (isPlaying) {
      if (this.video.paused) {
        this.video.play().catch(e => console.error("Video play failed:", e));
      }
    } else {
      if (!this.video.paused) {
        this.video.pause();
      }
    }
  }
};