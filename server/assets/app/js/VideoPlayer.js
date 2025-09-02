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

    // Playing state
    this.isPlaying = false;

    // Parse steps from data attribute
    try {
      this.steps = JSON.parse(this.el.dataset.steps || '[]');
    } catch (e) {
      this.steps = [];
    }

    this.el.addEventListener("play", () => {
      this.isPlaying = true;
      this.updatePlayPauseButton();
      this.startSmoothUpdates();
    });

    this.el.addEventListener("pause", () => {
      this.isPlaying = false;
      this.updatePlayPauseButton();
      this.stopSmoothUpdates();
    });

    this.el.addEventListener("ended", () => {
      this.isPlaying = false;
      this.updatePlayPauseButton();
      this.stopSmoothUpdates();
      this.pushEvent("video_ended", {});
    });

    const currentStepIndex = this.findCurrentStepIndex(this.steps, this.el.duration);
    this.pushEvent("video_time_update", {
      current_time: this.el.currentTime,
      current_step_index: currentStepIndex
    });

    // Initialize button states
    this.updateSeekButtonStates(this.el.currentTime);
    this.updatePlayPauseButton();

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

    // Handle play/pause toggle from button click
    this.handlePlayPauseToggle = (event) => {
      if (event.detail.id == this.el.id) {
        if (this.isPlaying) {
          this.el.pause();
        } else {
          this.el.play();
        }
      }
    };
    window.addEventListener("phx:play-pause-toggle", this.handlePlayPauseToggle);

    // Handle external seek command
    this.handleSeekVideo = (event) => {
      if (event.detail.id == this.el.id) {
        console.log(Math.min(event.detail.time, this.el.duration));
        this.el.currentTime = Math.min(event.detail.time, this.el.duration);
        // Auto-scroll if explicitly requested, otherwise don't auto-scroll during external seek
        const shouldAutoScroll = event.detail.auto_scroll || false;
        this.updateProgressBar(this.el.currentTime, this.el.duration, shouldAutoScroll);
      }
    };
    window.addEventListener("phx:seek-video", this.handleSeekVideo);

    // Handle seek to previous step
    this.handleSeekPrevStep = (event) => {
      this.seekToPreviousStep(this.steps, this.el.duration);
    };
    window.addEventListener("phx:seek-prev-step", this.handleSeekPrevStep);

    // Handle seek to next step
    this.handleSeekNextStep = (event) => {
      this.seekToNextStep(this.steps, this.el.duration);
    };
    window.addEventListener("phx:seek-next-step", this.handleSeekNextStep);

    // Handle user scrolling detection
    this.setupScrollDetection();

    // Setup draggable playhead
    this.setupDraggablePlayhead();

  },

  startSmoothUpdates() {
    const update = () => {
      if (!this.el.paused && !this.el.ended) {
        // Auto-scroll when video is playing
        this.updateProgressBar(this.el.currentTime, this.el.duration, true);
        this.animationFrameId = requestAnimationFrame(update);
      }
    };
    update();
  },

  stopSmoothUpdates() {
    if (this.animationFrameId) {
      // Don't auto-scroll when stopping playback
      this.updateProgressBar(this.el.currentTime, this.el.duration, false);
      cancelAnimationFrame(this.animationFrameId);
      this.animationFrameId = null;
    }
  },

  setupScrollDetection() {
    const scrollContainer = document.querySelector('[data-part="timeline"]');
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

  setupDraggablePlayhead() {
    const playhead = document.querySelector('#playhead');
    const playheadArea = document.querySelector('#playhead-area');

    if (!playhead || !playheadArea) return;

    let isDragging = false;
    let wasPlaying = false;
    let dragStartTime = 0;
    const DRAG_THRESHOLD = 5; // pixels

    const handleMouseDown = (e) => {
      e.preventDefault();
      isDragging = true;
      wasPlaying = !this.el.paused;
      dragStartTime = Date.now();

      // Pause video during drag
      if (wasPlaying) {
        this.el.pause();
      }

      // Add document-level listeners for better drag behavior
      document.addEventListener('mousemove', handleMouseMove);
      document.addEventListener('mouseup', handleMouseUp);

      // Change cursor on playhead area
      playheadArea.style.cursor = 'grabbing';
      document.body.style.cursor = 'grabbing';
    };

    const handleMouseMove = (e) => {
      if (!isDragging) return;

      const rect = playheadArea.getBoundingClientRect();
      const x = Math.max(0, Math.min(e.clientX - rect.left, playheadArea.clientWidth));
      const percentage = x / playheadArea.clientWidth;
      const duration = this.el.duration;
      const seekTime = percentage * duration;

      // Update playhead position immediately during drag
      playhead.style.left = `${x}px`;

      // Update video time and seek immediately for better feedback
      const targetTime = Math.min(seekTime, duration);

      // Simple Firefox optimization - use fastSeek if available
      if (navigator.userAgent.includes('Firefox') && this.el.fastSeek) {
        this.el.fastSeek(targetTime);
      } else {
        this.el.currentTime = targetTime;
      }

      // Update time display directly in JS for better performance
      this.updateTimeDisplay(this.el.currentTime, duration);
    };

    const handleMouseUp = (e) => {
      if (!isDragging) return;

      isDragging = false;

      // Calculate final seek position
      const rect = playheadArea.getBoundingClientRect();
      const x = Math.max(0, Math.min(e.clientX - rect.left, playheadArea.clientWidth));
      const percentage = x / playheadArea.clientWidth;
      const duration = this.el.duration;
      const seekTime = percentage * duration;

      // Final seek
      this.el.currentTime = Math.min(seekTime, duration);

      // Update server with final time
      const currentStepIndex = this.findCurrentStepIndex(this.steps, this.el.duration);
      this.pushEvent("video_time_update", {
        current_time: this.el.currentTime,
        current_step_index: currentStepIndex
      });

      // Resume playback if it was playing before drag
      if (wasPlaying) {
        this.el.play();
      }

      // Remove document listeners
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);

      // Reset cursors
      playheadArea.style.cursor = 'grab';
      document.body.style.cursor = '';
    };

    // Add initial event listener to playhead area
    playheadArea.addEventListener('mousedown', handleMouseDown);
    playheadArea.style.cursor = 'grab';

    // Add drag handling for step thumbnails
    this.setupStepThumbnailDragging(handleMouseDown, handleMouseMove, handleMouseUp);

    // Store references for cleanup
    this.playheadHandlers = {
      handleMouseDown,
      handleMouseMove,
      handleMouseUp
    };
  },

  setupStepThumbnailDragging(handleMouseDown, handleMouseMove, handleMouseUp) {
    const stepThumbnails = document.querySelectorAll('[data-part="step-thumbnail"] img');

    stepThumbnails.forEach(thumbnail => {
      let dragStartX = 0;
      let dragStartY = 0;
      let hasDragged = false;
      const DRAG_THRESHOLD = 5; // pixels

      const thumbnailMouseDown = (e) => {
        dragStartX = e.clientX;
        dragStartY = e.clientY;
        hasDragged = false;

        const thumbnailMouseMove = (e) => {
          const deltaX = Math.abs(e.clientX - dragStartX);
          const deltaY = Math.abs(e.clientY - dragStartY);

          if (!hasDragged && (deltaX > DRAG_THRESHOLD || deltaY > DRAG_THRESHOLD)) {
            hasDragged = true;
            // Stop propagation to prevent phx-click
            e.stopPropagation();
            e.preventDefault();

            // Start playhead dragging
            handleMouseDown(e);

            // Remove thumbnail listeners since we're now in playhead drag mode
            document.removeEventListener('mousemove', thumbnailMouseMove);
            document.removeEventListener('mouseup', thumbnailMouseUp);
          }
        };

        const thumbnailMouseUp = (e) => {
          document.removeEventListener('mousemove', thumbnailMouseMove);
          document.removeEventListener('mouseup', thumbnailMouseUp);

          // If we didn't drag, allow the click event to proceed normally
          if (!hasDragged) {
            // The phx-click will handle the step seeking
            return;
          }
        };

        // Add temporary listeners for this potential drag
        document.addEventListener('mousemove', thumbnailMouseMove);
        document.addEventListener('mouseup', thumbnailMouseUp);
      };

      thumbnail.addEventListener('mousedown', thumbnailMouseDown);

      // Store reference for cleanup
      if (!this.thumbnailHandlers) this.thumbnailHandlers = [];
      this.thumbnailHandlers.push({
        element: thumbnail,
        handler: thumbnailMouseDown
      });
    });
  },

  updateTimeDisplay(currentTime, duration) {
    const timeDisplay = document.querySelector('[data-part="time-display"]');
    if (!timeDisplay) return;

    const formatTime = (seconds) => {
      const minutes = Math.floor(seconds / 60);
      const remainingSeconds = Math.floor(seconds % 60);
      return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
    };

    timeDisplay.textContent = `${formatTime(currentTime)}/${formatTime(duration)}`;
  },

  updateProgressBar(currentTime, duration, shouldAutoScroll = false) {
    // if (!duration || duration === 0) return;
    const progress = Math.min((currentTime / duration), 1);

    const playhead = document.querySelector('#playhead');
    const playheadArea = document.querySelector("#playhead-area");

    if (playhead && playheadArea) {
      console.log("Setting playhead to ", playheadArea.clientWidth * progress);
      playhead.style.left = `${playheadArea.clientWidth * progress}px`;
      console.log(`Updating playhead position to ${playheadArea.clientWidth * progress}px`);
    }

    // Auto-scroll timeline only when explicitly requested (video playing or seeking to step)
    if (shouldAutoScroll) {
      this.autoScrollTimeline(currentTime, duration);
    }

    // Update seek button states
    this.updateSeekButtonStates(currentTime);

    // Update steps counter
    this.updateStepsCounter(currentTime);

    // Send periodic updates to server (throttled)
    this.sendPeriodicTimeUpdate(currentTime);
  },

  sendPeriodicTimeUpdate(currentTime) {
    const now = Date.now();

    // Only send updates every 250ms and if there's a meaningful time difference
    if (now - this.lastServerUpdate > this.serverUpdateInterval &&
        Math.abs(currentTime - this.lastServerUpdateTime) > 0.1) {

      const currentStepIndex = this.findCurrentStepIndex(this.steps, this.el.duration);
      this.pushEvent("video_time_update", {
        current_time: currentTime,
        current_step_index: currentStepIndex
      });

      this.lastServerUpdate = now;
      this.lastServerUpdateTime = currentTime;
    }
  },

  autoScrollTimeline(currentTime, duration) {
    const timelineContent = document.querySelector('#timeline-content');
    const scrollContainer = document.querySelector('[data-part="timeline"]');

    if (!timelineContent || !scrollContainer) return;

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
    const margin = containerWidth * 0.1; // 10% margin from edges (reduced to trigger less often)

    // Check if playhead is getting close to the right edge
    if (playheadPosition > visibleEnd - margin) {
      // Scroll to keep playhead at 25% from left edge (scroll much further ahead)
      const targetScroll = playheadPosition - containerWidth * 0.25;
      scrollContainer.scrollTo({
        left: Math.max(0, Math.min(targetScroll, trackWidth - containerWidth)),
        behavior: 'smooth'
      });
    }
    // Check if playhead is getting close to the left edge (when seeking backward)
    else if (playheadPosition < visibleStart + margin) {
      // Scroll to keep playhead at 75% from left edge (scroll much further back)
      const targetScroll = playheadPosition - containerWidth * 0.75;
      scrollContainer.scrollTo({
        left: Math.max(0, targetScroll),
        behavior: 'smooth'
      });
    }
  },

  findCurrentStepIndex(steps, duration) {
    if (!steps || steps.length === 0) return 0;

    const currentTime = this.el.currentTime;

    // Find the index of the last step that has passed
    let currentIndex = 0;
    for (let i = steps.length - 1; i >= 0; i--) {
      if (steps[i].time <= currentTime) {
        currentIndex = i;
        break;
      }
    }

    return currentIndex;
  },

  seekToPreviousStep(steps, duration) {
    if (!steps || steps.length === 0) return;

    const currentStepIndex = this.findCurrentStepIndex(steps, duration);
    const prevStepIndex = Math.max(0, currentStepIndex - 1);

    this.seekToStepByIndex(steps, prevStepIndex, duration);
  },

  seekToNextStep(steps, duration) {
    if (!steps || steps.length === 0) return;

    const currentStepIndex = this.findCurrentStepIndex(steps, duration);
    const nextStepIndex = Math.min(steps.length - 1, currentStepIndex + 1);

    this.seekToStepByIndex(steps, nextStepIndex, duration);
  },

  seekToStepByIndex(steps, stepIndex, duration) {
    if (stepIndex < 0 || stepIndex >= steps.length) return;

    const step = steps[stepIndex];

    if (!step) return;

    // Use the time directly from the step
    let seekTime = step.time;

    // Add a small offset to ensure we're clearly "at" this step
    seekTime = Math.min(seekTime, duration);

    // Seek to the step
    this.el.currentTime = seekTime;

    // Update UI immediately and auto-scroll when seeking to step
    this.updateProgressBar(this.el.currentTime, this.el.duration, true);

    // Update server with new time
    const currentStepIndex = this.findCurrentStepIndex(this.steps, this.el.duration);
    this.pushEvent("video_time_update", {
      current_time: this.el.currentTime,
      current_step_index: currentStepIndex
    });
  },

  updateSeekButtonStates(currentTime) {
    const prevButton = document.querySelector('#seek-prev-button');
    const nextButton = document.querySelector('#seek-next-button');

    if (!prevButton || !nextButton || !this.steps || this.steps.length === 0) return;

    // Find current step index
    const currentStepIndex = this.findCurrentStepIndex(this.steps, this.el.duration);

    // Update prev button state
    const canSeekPrev = currentStepIndex > 0;
    console.log(canSeekPrev);
    if (canSeekPrev) {
      prevButton.disabled = false;
    } else {
      prevButton.disabled = true;
    }

    // Update next button state
    const canSeekNext = currentStepIndex < this.steps.length - 1;
    if (canSeekNext) {
      nextButton.disabled = false;
    } else {
      nextButton.disabled = true;
    }
  },

  updateStepsCounter(currentTime) {
    const stepsCounter = document.querySelector('[data-part="steps-counter"]');
    if (!stepsCounter || !this.steps || this.steps.length === 0) return;

    // Find current step index (1-based for display)
    const currentStepIndex = this.findCurrentStepIndex(this.steps, this.el.duration);
    const currentStepDisplay = currentStepIndex + 1;
    const totalSteps = this.steps.length;

    // Update the counter text - match the format from the template
    stepsCounter.textContent = `${currentStepDisplay}/${totalSteps} steps`;
  },

  updatePlayPauseButton() {
    const playPauseButton = document.querySelector('#play-pause-button');
    if (!playPauseButton) return;

    // Clear existing icon
    const iconContainer = playPauseButton.querySelector('svg').parentElement;
    iconContainer.innerHTML = '';

    // Add the appropriate icon based on play state
    if (this.isPlaying) {
      // Add pause icon
      iconContainer.innerHTML = `<svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg" data-icon="player_pause">
        <path d="M7 2.75H5.25C4.83579 2.75 4.5 3.08579 4.5 3.5V16.5C4.5 16.9142 4.83579 17.25 5.25 17.25H7C7.41421 17.25 7.75 16.9142 7.75 16.5V3.5C7.75 3.08579 7.41421 2.75 7 2.75Z" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
        <path d="M14.75 2.75H13C12.5858 2.75 12.25 3.08579 12.25 3.5V16.5C12.25 16.9142 12.5858 17.25 13 17.25H14.75C15.1642 17.25 15.5 16.9142 15.5 16.5V3.5C15.5 3.08579 15.1642 2.75 14.75 2.75Z" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>`;
    } else {
      // Add play icon
      iconContainer.innerHTML = `<svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg" data-icon="player_play">
        <path d="M4.75 2.74707L4.75 17.2529C4.75 17.5281 5.05901 17.7028 5.30035 17.5592L16.3688 10.3063C16.5908 10.1746 16.5908 9.82538 16.3688 9.69371L5.30035 2.44085C5.05901 2.29718 4.75 2.47186 4.75 2.74707Z" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>`;
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
    window.removeEventListener("phx:play-pause-toggle", this.handlePlayPauseToggle);
    window.removeEventListener("phx:seek-video", this.handleSeekVideo);
    window.removeEventListener("phx:seek-prev-step", this.handleSeekPrevStep);
    window.removeEventListener("phx:seek-next-step", this.handleSeekNextStep);

    // Remove scroll listener
    const scrollContainer = document.querySelector('[data-part="timeline"]');
    if (scrollContainer && this.handleUserScroll) {
      scrollContainer.removeEventListener('scroll', this.handleUserScroll);
    }

    // Remove playhead drag listeners
    const playheadArea = document.querySelector('#playhead-area');
    if (playheadArea && this.playheadHandlers) {
      playheadArea.removeEventListener('mousedown', this.playheadHandlers.handleMouseDown);
      // Also clean up any potentially remaining document listeners
      document.removeEventListener('mousemove', this.playheadHandlers.handleMouseMove);
      document.removeEventListener('mouseup', this.playheadHandlers.handleMouseUp);
    }

    // Remove thumbnail drag listeners
    if (this.thumbnailHandlers) {
      this.thumbnailHandlers.forEach(({ element, handler }) => {
        element.removeEventListener('mousedown', handler);
      });
    }
  }
};
