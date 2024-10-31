function scrollInfinitely(scrollableContainer) {
  scrollableContainer.scrollLeft += 1;
  if (
    scrollableContainer.scrollLeft >=
    scrollableContainer.scrollWidth - scrollableContainer.clientWidth
  ) {
    scrollableContainer.scrollLeft = 0;
  }
  setTimeout(() => {
    requestAnimationFrame(function () {
      scrollInfinitely(scrollableContainer);
    });
  }, 10);
}

const logosElement = document.querySelector(
  ".marketing__home__section__companies__logos",
);
if (logosElement) {
  scrollInfinitely(logosElement);
}

const testimonialsElement = document.querySelector(
  ".marketing__home__section__testimonials__main",
);
if (testimonialsElement) {
  scrollInfinitely(testimonialsElement);
}
