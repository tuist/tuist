export default {
  mounted() {
    this.animationFrameId = null;

    this.isUserScrolling = false;
    this.isDragging = false;

    this.el.addEventListener("play", () => {
      this.pushEvent("video_play");
      this.startVideoUpdates();
    });

    this.el.addEventListener("pause", () => {
      if (!this.isDragging) {
        this.pushEvent("video_pause");
      }
      this.stopVideoUpdates();
    });

    this.el.addEventListener("ended", () => {
      this.pushEvent("video_ended");
      this.stopVideoUpdates();
    });

    this.handlePlayPauseToggle = (event) => {
      if (event.detail.id == this.el.id) {
        if (this.el.paused) {
          this.el.play();
        } else {
          this.el.pause();
        }
      }
    };
    window.addEventListener("phx:play-pause-toggle", this.handlePlayPauseToggle);

    this.handleSeekVideo = (event) => {
      if (event.detail.id == this.el.id) {
        this.el.currentTime = event.detail.time;
        this.updateProgressBar(this.el.currentTime, this.el.duration, event.detail.auto_scroll || false);
      }
    };
    window.addEventListener("phx:seek-video", this.handleSeekVideo);

    this.handleSetPlaybackSpeed = (event) => {
      if (event.detail.id == this.el.id) {
        this.el.playbackRate = event.detail.speed;
      }
    };
    window.addEventListener("phx:set-playback-speed", this.handleSetPlaybackSpeed);

    this.setupDraggablePlayhead();
  },

  startVideoUpdates() {
    const update = () => {
      this.updateProgressBar(this.el.currentTime, this.el.duration, true);
      this.animationFrameId = requestAnimationFrame(update);
    };
    update();
  },

  stopVideoUpdates() {
    if (this.animationFrameId) {
      this.updateProgressBar(this.el.currentTime, this.el.duration, false);
      cancelAnimationFrame(this.animationFrameId);
      this.animationFrameId = null;
    }
  },

  setupDraggablePlayhead() {
    const playhead = document.querySelector("#playhead");
    const playheadArea = document.querySelector("#playhead-area");

    let wasPlaying = false;
    let dragStartX = 0;
    let dragStartY = 0;

    this.handleMouseDown = (event) => {
      dragStartX = event.clientX;
      dragStartY = event.clientY;

      document.addEventListener("mousemove", this.handleMouseMove);
      document.addEventListener("mouseup", this.handleMouseUp);

      playheadArea.style.cursor = "grabbing";
      document.body.style.cursor = "grabbing";
    };

    const DRAG_THRESHOLD = 5;
    this.handleMouseMove = (event) => {
      const deltaX = Math.abs(event.clientX - dragStartX);
      const deltaY = Math.abs(event.clientY - dragStartY);

      if (!this.isDragging && (deltaX > DRAG_THRESHOLD || deltaY > DRAG_THRESHOLD)) {
        this.isDragging = true;
        wasPlaying = !this.el.paused;
      }
      if (!this.isDragging) return;
      this.el.pause();

      const seekTime = this.seekTimeAfterDrag(event, playheadArea);

      // Firefox stops seeking the video if currentTime is set too frequently.
      if (navigator.userAgent.includes("Firefox") && this.el.fastSeek) {
        this.el.fastSeek(seekTime);
      } else {
        this.el.currentTime = seekTime;
      }

      this.pushEvent("video_time_update", {
        current_time: this.el.currentTime,
      });
    };

    this.handleMouseUp = (element) => {
      playheadArea.style.cursor = "grab";
      document.body.style.cursor = "";

      document.removeEventListener("mousemove", this.handleMouseMove);
      document.removeEventListener("mouseup", this.handleMouseUp);

      if (this.isDragging) {
        this.isDragging = false;
        this.el.currentTime = this.seekTimeAfterDrag(element, playheadArea);

        this.pushEvent("video_time_update", {
          current_time: this.el.currentTime,
        });

        if (wasPlaying) {
          this.el.play();
        }
      }
    };

    playheadArea.addEventListener("mousedown", this.handleMouseDown);
    document.addEventListener("handlePropagatedMouseMove", this.handleMouseDown);
  },

  seekTimeAfterDrag(event, playheadArea) {
    const rect = playheadArea.getBoundingClientRect();
    const x = Math.max(0, Math.min(event.clientX - rect.left, playheadArea.clientWidth));
    const percentage = x / playheadArea.clientWidth;
    const seekTime = percentage * this.el.duration;

    playhead.style.left = `${x}px`;

    return Math.min(seekTime, this.el.duration);
  },

  updateProgressBar(currentTime, duration, shouldAutoScroll = false) {
    const progress = Math.min(currentTime / duration, 1);

    const playhead = document.querySelector("#playhead");
    const playheadArea = document.querySelector("#playhead-area");

    playhead.style.left = `${playheadArea.clientWidth * progress}px`;

    if (shouldAutoScroll) {
      this.autoScrollTimeline(currentTime, duration);
    }

    this.pushEvent("video_time_update", {
      current_time: currentTime,
    });
  },

  autoScrollTimeline(currentTime, duration) {
    const timelineContent = document.querySelector("#timeline-content");
    const scrollContainer = document.querySelector("#timeline-track");

    const trackWidth = timelineContent.scrollWidth;
    const containerWidth = scrollContainer.clientWidth;

    // Only scroll if the track is wider than the container
    if (trackWidth <= containerWidth) return;

    // Calculate current playhead position in pixels relative to the timeline content
    const progress = currentTime / duration;
    const playheadPosition = progress * trackWidth;

    // Get current scroll position
    const currentScroll = scrollContainer.scrollLeft;
    const visibleStart = currentScroll;
    const visibleEnd = currentScroll + containerWidth;

    // Calculate desired scroll position to keep playhead visible with some margin
    const margin = containerWidth * 0.1;

    // Check if playhead is getting close to the right edge
    if (playheadPosition > visibleEnd - margin) {
      // Scroll to keep playhead at 25% from left edge
      const targetScroll = playheadPosition - containerWidth * 0.25;
      scrollContainer.scrollTo({
        left: Math.max(0, Math.min(targetScroll, trackWidth - containerWidth)),
        behavior: "smooth",
      });
    }
    // Check if playhead is getting close to the left edge (when seeking backward)
    else if (playheadPosition < visibleStart + margin) {
      // Scroll to keep playhead at 75% from left edge
      const targetScroll = playheadPosition - containerWidth * 0.75;
      scrollContainer.scrollTo({
        left: Math.max(0, targetScroll),
        behavior: "smooth",
      });
    }
  },

  destroyed() {
    this.stopVideoUpdates();

    window.removeEventListener("phx:play-pause-toggle", this.handlePlayPauseToggle);
    window.removeEventListener("phx:seek-video", this.handleSeekVideo);
    window.removeEventListener("phx:set-playback-speed", this.handleSetPlaybackSpeed);

    const playheadArea = document.querySelector("#playhead-area");
    playheadArea.removeEventListener("mousedown", this.handleMouseDown);
    document.removeEventListener("mousemove", this.handleMouseMove);
    document.removeEventListener("mouseup", this.handleMouseUp);
    document.removeEventListener("handlePropagatedMouseMove", this.handleMouseDown);
  },
};
