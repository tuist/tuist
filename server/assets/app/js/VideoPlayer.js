export default {
  mounted() {
    // Animation and timing state
    this.animationFrameId = null;
    this.lastServerUpdate = 0;
    this.lastServerUpdateTime = 0; // Track the actual video time of last server update
    this.serverUpdateInterval = 250; // Update server 4 times per second

    // Auto-scroll state
    this.isUserScrolling = false;
    this.userScrollTimeout = null;

    this.el.addEventListener("play", () => {
      this.startSmoothUpdates();
    });

    this.el.addEventListener("pause", () => {
      this.stopSmoothUpdates();
    });

    // Also stop on video end
    // this.el.addEventListener("ended", () => {
    //   // Stop smooth updates first to prevent conflicts
    //   this.stopSmoothUpdates();

    //   // Calculate proportional animation duration to match video playback speed
    //   const timeDelta = this.el.currentTime - this.lastServerUpdateTime;
    //   // The animation duration should be the same as the real time it took to play that video segment
    //   // Since timeupdate fires roughly every 250ms during playback, use that as the basis
    //   const proportionalDuration = Math.max(50, timeDelta * 1000); // Convert video seconds to milliseconds

    //   // Animate progress bar with proportional timing
    //   this.animateProgressToEnd(proportionalDuration);

    //   this.pushEvent("video_time_update", {
    //     current_time: this.el.currentTime,
    //     duration: this.el.duration
    //   });
    //   this.pushEvent("video_ended", {});
    // });

    // this.el.addEventListener("ended", () => {
    //     this.pushEvent("video_time_update", {
    //       current_time: this.el.currentTime,
    //       duration: this.el.duration
    //     });
    //     this.updateProgressBar(this.el.currentTime, this.el.duration);
    // });

    // this.el.addEventListener("timeupdate", () => {
    //     this.pushEvent("video_time_update", {
    //       current_time: this.el.currentTime,
    //       duration: this.el.duration
    //     });
    //     this.updateProgressBar(this.el.currentTime, this.el.duration);
    // });

    this.pushEvent("video_time_update", {
      current_time: this.el.currentTime,
      duration: this.el.duration
    });

    // Handle external pause command
    this.handlePauseVideo = (event) => {
      if (event.detail.id == this.el.id) {
        this.el.pause();
      }
    };
    window.addEventListener("phx:pause-video", this.handlePauseVideo);

    // Handle external play command
    this.handlePlayVideo = (event) => {
      if (event.detail.id == this.el.id) {
        this.el.play();
      }
    };
    window.addEventListener("phx:play-video", this.handlePlayVideo);

    // Handle external seek command
    this.handleSeekVideo = (event) => {
      if (event.detail.id == this.el.id) {
        this.el.currentTime = event.detail.time;
        // Update UI immediately on seek
        this.updateProgressBar(event.detail.time, this.el.duration);
      }
    };
    window.addEventListener("phx:seek-video", this.handleSeekVideo);

    // Handle user scrolling detection
    this.setupScrollDetection();
  },

  startSmoothUpdates() {
    const update = () => {
      if (!this.el.paused && !this.el.ended) {
        this.updateProgressBar(this.el.currentTime, this.el.duration);
        this.animationFrameId = requestAnimationFrame(update);
      }
    };
    update();
  },

  stopSmoothUpdates() {
    if (this.animationFrameId) {
      this.updateProgressBar(this.el.currentTime, this.el.duration);
      cancelAnimationFrame(this.animationFrameId);
      this.animationFrameId = null;
    }
  },

  setupScrollDetection() {
    const scrollContainer = document.querySelector('.scrollable-container');
    if (!scrollContainer) return;

    // Detect when user starts scrolling
    this.handleUserScroll = () => {
      this.isUserScrolling = true;

      // Clear existing timeout
      if (this.userScrollTimeout) {
        clearTimeout(this.userScrollTimeout);
      }

      // Resume auto-scroll after 2 seconds of no manual scrolling
      this.userScrollTimeout = setTimeout(() => {
        this.isUserScrolling = false;
      }, 2000);
    };

    scrollContainer.addEventListener('scroll', this.handleUserScroll, { passive: true });
  },

  updateProgressBar(currentTime, duration) {
    if (!duration || duration === 0) return;

    const progress = Math.min((currentTime / duration), 1);

    const playhead = document.querySelector('#playhead');
    const timeMarkers = document.querySelector("#time-markers");
    const width = timeMarkers.width;
    console.log(timeMarkers);
    if (playhead) {
      console.log("Setting playhead to ", timeMarkers.scrollWidth * progress);
      playhead.style.left = `${timeMarkers.scrollWidth * progress}px`;
    }

    // Auto-scroll timeline to keep playhead visible
    this.autoScrollTimeline(currentTime, duration);
  },

  autoScrollTimeline(currentTime, duration) {
    // Don't auto-scroll if user is manually scrolling
    if (this.isUserScrolling) return;

    const timelineTrack = document.querySelector('#timeline-track');
    const scrollContainer = document.querySelector('.scrollable-container');

    if (!timelineTrack || !scrollContainer) return;

    const trackWidth = timelineTrack.offsetWidth;
    const containerWidth = scrollContainer.clientWidth;

    // Only scroll if the track is wider than the container
    if (trackWidth <= containerWidth) return;

    // Calculate current playhead position in pixels
    const progress = currentTime / duration;
    const playheadPosition = progress * trackWidth;

    // Get current scroll position
    const currentScroll = scrollContainer.scrollLeft;
    const visibleStart = currentScroll;
    const visibleEnd = currentScroll + containerWidth;

    // Calculate desired scroll position to keep playhead centered with some margin
    const margin = containerWidth * 0.2; // 20% margin from edges

    // Check if playhead is getting close to the right edge
    if (playheadPosition > visibleEnd - margin) {
      // Scroll to keep playhead at 80% from left edge
      const targetScroll = playheadPosition - containerWidth * 0.8;
      scrollContainer.scrollTo({
        left: Math.max(0, Math.min(targetScroll, containerWidth)),
        behavior: 'smooth'
      });
    }
    // Check if playhead is getting close to the left edge (when seeking backward)
    else if (playheadPosition < visibleStart + margin) {
      // Scroll to keep playhead at 20% from left edge
      const targetScroll = playheadPosition - containerWidth * 0.2;
      scrollContainer.scrollTo({
        left: Math.max(0, targetScroll),
        behavior: 'smooth'
      });
    }
  },

  // animateProgressToEnd(duration) {
  //   const progressBar = document.querySelector('.progress-bar');
  //   const playhead = document.querySelector('#playhead');

  //   if (!progressBar || !playhead) return;

  //   // Add smooth transition with calculated duration
  //   progressBar.style.transition = `width ${duration}ms linear`;
  //   playhead.style.transition = `left ${duration}ms linear`;

  //   // Animate to 100%
  //   progressBar.style.width = '100%';
  //   playhead.style.left = '100%';

  //   // Remove transition after animation completes
  //   setTimeout(() => {
  //     progressBar.style.transition = '';
  //     playhead.style.transition = '';
  //   }, duration);
  // },

  destroyed() {
    this.stopSmoothUpdates();

    // Clear user scroll timeout
    if (this.userScrollTimeout) {
      clearTimeout(this.userScrollTimeout);
    }

    // Remove event listeners
    window.removeEventListener("phx:pause-video", this.handlePauseVideo);
    window.removeEventListener("phx:play-video", this.handlePlayVideo);
    window.removeEventListener("phx:seek-video", this.handleSeekVideo);

    // Remove scroll listener
    const scrollContainer = document.querySelector('.scrollable-container');
    if (scrollContainer && this.handleUserScroll) {
      scrollContainer.removeEventListener('scroll', this.handleUserScroll);
    }
  }
};
