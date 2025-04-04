import { Termynal } from "./components/termynal.js";

function scrollInfinitely(scrollableContainer) {
  scrollableContainer.scrollLeft += 1;
  if (scrollableContainer.scrollLeft >= scrollableContainer.scrollWidth - scrollableContainer.clientWidth) {
    scrollableContainer.scrollLeft = 0;
  }
  setTimeout(() => {
    requestAnimationFrame(function () {
      scrollInfinitely(scrollableContainer);
    });
  }, 10);
}

const logosElement = document.querySelector(".marketing__home__section__companies__logos");
if (logosElement) {
  scrollInfinitely(logosElement);
}

const testimonialsElement = document.querySelector(".marketing__home__section__testimonials__main");
if (testimonialsElement) {
  scrollInfinitely(testimonialsElement);
}

// Terminals
document.addEventListener("DOMContentLoaded", () => {
  if (document.querySelector("#hero-terminal")) {
    new Termynal("#hero-terminal", { startDelay: 600, noInit: false });
  }
  const previewsTerminalEelement = document.querySelector("#preview-terminal");
  const previewsVideoElement = document.querySelector("#previews-video");
  let previewsAnimationPlayed = false;

  if (previewsTerminalEelement && previewsVideoElement) {
    const termynal = new Termynal(previewsTerminalEelement, {
      startDelay: 600,
      noInit: true,
    });

    const observer = new IntersectionObserver(
      async (entries, observer) => {
        for (const entry of entries) {
          if (entry.isIntersecting && !previewsAnimationPlayed) {
            termynal.reset();
            await termynal.start();
            previewsVideoElement.play();
            previewsAnimationPlayed = true;
          }
        }
      },
      {
        threshold: 0.5,
      },
    );

    observer.observe(previewsTerminalEelement);
  }
});
