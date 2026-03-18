const AgentPrompt = {
  mounted() {
    const promptEl = this.el.querySelector("[data-part='prompt-text']");
    const responseEl = this.el.querySelector("[data-part='response-text']");
    const cursorEl = this.el.querySelector("[data-part='cursor']");
    const responseSection = this.el.querySelector(
      "[data-part='response-section']"
    );

    if (!promptEl || !responseEl || !responseSection) return;

    const prompt = promptEl.dataset.value;
    const response = responseEl.dataset.value;

    promptEl.textContent = "";
    responseEl.textContent = "";
    responseSection.style.display = "none";

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) {
          observer.disconnect();
          this.animate(
            promptEl,
            responseEl,
            cursorEl,
            responseSection,
            prompt,
            response
          );
        }
      },
      { threshold: 0.3 }
    );
    observer.observe(this.el);
  },

  animate(promptEl, responseEl, cursorEl, responseSection, prompt, response) {
    let i = 0;
    const promptSpeed = 30;
    const responseSpeed = 10;

    const typePrompt = () => {
      if (i < prompt.length) {
        promptEl.textContent += prompt[i];
        i++;
        setTimeout(typePrompt, promptSpeed);
      } else {
        setTimeout(typeResponse, 400);
      }
    };

    const typeResponse = () => {
      responseSection.style.display = "";
      let j = 0;
      const typeChar = () => {
        if (j < response.length) {
          responseEl.textContent += response[j];
          j++;
          setTimeout(typeChar, responseSpeed);
        } else if (cursorEl) {
          cursorEl.style.display = "none";
        }
      };
      typeChar();
    };

    typePrompt();
  },
};

export { AgentPrompt };
