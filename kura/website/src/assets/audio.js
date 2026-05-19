const root = document.querySelector(".kura-audio");

if (root) {
  const audio = root.querySelector('[data-part="player"]');
  const button = root.querySelector('[data-part="toggle"]');
  const status = root.querySelector('[data-part="status"]');
  const storeKey = root.dataset.storeKey || "kura-soundtrack";

  const labels = {
    play: button.dataset.labelPlay,
    pause: button.dataset.labelPause,
    playing: button.dataset.labelPlaying,
    paused: button.dataset.labelPaused,
  };

  let session = null;
  try {
    session = window.sessionStorage;
  } catch {
    session = null;
  }

  const remember = (value) => {
    if (session) {
      try {
        session.setItem(storeKey, value);
      } catch {
        /* storage unavailable, ignore */
      }
    }
  };

  const reflect = (playing) => {
    root.dataset.state = playing ? "playing" : "paused";
    button.setAttribute("aria-label", playing ? labels.pause : labels.play);
    if (status) status.textContent = playing ? labels.playing : labels.paused;
  };

  button.addEventListener("click", () => {
    if (audio.paused) {
      audio.play().then(() => remember("on")).catch(() => reflect(false));
    } else {
      audio.pause();
      remember("off");
    }
  });

  audio.addEventListener("play", () => reflect(true));
  audio.addEventListener("pause", () => reflect(false));
  audio.addEventListener("ended", () => reflect(false));

  if (session && session.getItem(storeKey) === "on") {
    audio.play().catch(() => reflect(false));
  }
}
