const SELECTORS = {
  code: "[data-part='code']",
  prompt: "[data-part='prompt-text']",
  response: "[data-part='response-text']",
  promptCursor: "[data-part='prompt-cursor']",
  responseCursor: "[data-part='response-cursor']",
  trigger: "[data-part='trigger']",
  responseSection: "[data-part='response-section']",
};

const TIMING = {
  promptCharMs: 30,
  responseCharMs: 12,
  stepPauseMs: 180,
  promptToResponseMs: 220,
};

const URL_REGEX = /(https?:\/\/[^\s]+)/g;

function queryElements(root) {
  const elements = {
    code: root.querySelector(SELECTORS.code),
    prompt: root.querySelector(SELECTORS.prompt),
    response: root.querySelector(SELECTORS.response),
    promptCursor: root.querySelector(SELECTORS.promptCursor),
    responseCursor: root.querySelector(SELECTORS.responseCursor),
    trigger: root.querySelector(SELECTORS.trigger),
    responseSection: root.querySelector(SELECTORS.responseSection),
  };

  return Object.values(elements).every(Boolean) ? elements : null;
}

function parseResponseSteps(rawValue) {
  try {
    const steps = JSON.parse(rawValue);

    if (!Array.isArray(steps)) return [];

    return steps.map((step) => ({
      text: step.text || "",
      waitMs: step.wait_ms || 0,
    }));
  } catch (_error) {
    return [];
  }
}

function segmentText(text) {
  const segments = [];
  let lastIndex = 0;

  for (const match of text.matchAll(URL_REGEX)) {
    const index = match.index ?? 0;

    if (index > lastIndex) {
      segments.push({ type: "text", value: text.slice(lastIndex, index) });
    }

    segments.push({ type: "link", value: match[0] });
    lastIndex = index + match[0].length;
  }

  if (lastIndex < text.length) {
    segments.push({ type: "text", value: text.slice(lastIndex) });
  }

  return segments;
}

function appendLink(container, url) {
  const link = document.createElement("a");
  link.href = url;
  link.target = "_blank";
  link.rel = "noreferrer";
  link.textContent = url;
  container.appendChild(link);
}

function setCursorVisibility(cursor, isVisible) {
  if (cursor) {
    cursor.style.visibility = isVisible ? "visible" : "hidden";
  }
}

const AgentPrompt = {
  mounted() {
    this.elements = queryElements(this.el);
    if (!this.elements) return;

    this.timers = new Set();
    this.prompt = this.elements.prompt.dataset.value || "";
    this.responseSteps = parseResponseSteps(this.elements.responseSection.dataset.responseSteps);
    this.prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    this.handleClick = (event) => {
      if (!event.target.closest(SELECTORS.trigger)) return;
      this.start();
    };
    this.el.addEventListener("click", this.handleClick);

    this.reset();
  },

  beforeDestroy() {
    this.cleanup();
  },

  destroyed() {
    this.cleanup();
  },

  reset() {
    if (!this.elements) return;

    this.clearTimers();
    this.started = false;

    const { code, prompt, response, promptCursor, responseCursor, responseSection, trigger } = this.elements;

    prompt.textContent = "";
    response.textContent = "";
    responseSection.style.display = "none";
    setCursorVisibility(promptCursor, false);
    setCursorVisibility(responseCursor, false);
    trigger.disabled = false;
    trigger.removeAttribute("data-played");
    code.scrollTop = 0;
  },

  cleanup() {
    this.clearTimers();
    this.el.removeEventListener("click", this.handleClick);
  },

  start() {
    if (!this.elements || this.started) return;

    this.started = true;
    this.elements.trigger.disabled = true;
    this.elements.trigger.setAttribute("data-played", "true");

    if (this.prefersReducedMotion) {
      this.renderCompletedState();
      return;
    }

    this.playPrompt();
  },

  renderCompletedState() {
    const { code, prompt, response, responseSection } = this.elements;

    prompt.textContent = this.prompt;
    response.textContent = this.responseSteps.map((step) => step.text).join("\n");
    responseSection.style.display = "";
    this.scrollToBottom(code);
  },

  playPrompt() {
    const { code, prompt, promptCursor, responseCursor, responseSection } = this.elements;

    setCursorVisibility(promptCursor, true);

    this.typeCharacters(prompt, this.prompt, TIMING.promptCharMs, () => {
      setCursorVisibility(promptCursor, false);

      this.schedule(() => {
        responseSection.style.display = "";
        setCursorVisibility(responseCursor, true);
        this.scrollToBottom(code);
        this.playResponseStep(0);
      }, TIMING.promptToResponseMs);
    });
  },

  playResponseStep(index) {
    const { code, response, responseCursor } = this.elements;

    if (index >= this.responseSteps.length) {
      setCursorVisibility(responseCursor, false);
      this.scrollToBottom(code);
      return;
    }

    const step = this.responseSteps[index];
    const text = index === 0 ? step.text : `\n${step.text}`;

    this.typeRichText(response, text, () => {
      this.scrollToBottom(code);
      this.schedule(() => this.playResponseStep(index + 1), step.waitMs > 0 ? step.waitMs : TIMING.stepPauseMs);
    });
  },

  typeRichText(container, text, onComplete) {
    const segments = segmentText(text);
    this.typeSegments(container, segments, 0, onComplete);
  },

  typeSegments(container, segments, index, onComplete) {
    if (index >= segments.length) {
      onComplete();
      return;
    }

    const segment = segments[index];

    if (segment.type === "link") {
      appendLink(container, segment.value);
      this.scrollToBottom(this.elements.code);
      this.schedule(() => this.typeSegments(container, segments, index + 1, onComplete), TIMING.responseCharMs);
      return;
    }

    this.typeCharacters(container, segment.value, TIMING.responseCharMs, () =>
      this.typeSegments(container, segments, index + 1, onComplete),
    );
  },

  typeCharacters(container, text, delay, onComplete) {
    const node = document.createTextNode("");
    container.appendChild(node);
    this.scrollToBottom(this.elements.code);

    let index = 0;

    const tick = () => {
      if (index >= text.length) {
        onComplete();
        return;
      }

      node.textContent += text[index];
      index += 1;
      this.scrollToBottom(this.elements.code);
      this.schedule(tick, delay);
    };

    tick();
  },

  schedule(callback, delay) {
    const timerId = window.setTimeout(() => {
      this.timers.delete(timerId);
      callback();
    }, delay);

    this.timers.add(timerId);
  },

  clearTimers() {
    this.timers?.forEach((timerId) => window.clearTimeout(timerId));
    this.timers?.clear();
  },

  scrollToBottom(element) {
    const threshold = 40;
    const isNearBottom = element.scrollHeight - element.scrollTop - element.clientHeight < threshold;

    if (isNearBottom) {
      element.scrollTop = element.scrollHeight;
    }
  },
};

export { AgentPrompt };
