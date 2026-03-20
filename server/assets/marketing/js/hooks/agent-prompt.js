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
const SCROLL_THRESHOLD = 40;

function queryElements(root) {
  const elements = {};

  for (const [key, selector] of Object.entries(SELECTORS)) {
    const el = root.querySelector(selector);
    if (!el) return null;
    elements[key] = el;
  }

  return elements;
}

function parseResponseSteps(json) {
  try {
    const steps = JSON.parse(json);
    if (!Array.isArray(steps)) return [];
    return steps.map((s) => ({ text: s.text || "", waitMs: s.wait_ms || 0 }));
  } catch {
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

const AgentPrompt = {
  mounted() {
    this.elements = queryElements(this.el);
    if (!this.elements) return;

    this.abortController = null;
    this.prompt = this.elements.prompt.dataset.value || "";
    this.responseSteps = parseResponseSteps(this.elements.responseSection.dataset.responseSteps);
    this.prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    this.handleClick = (event) => {
      if (event.target.closest(SELECTORS.trigger)) this.start();
    };
    this.el.addEventListener("click", this.handleClick);
    this.reset();
  },

  destroyed() {
    this.abort();
    this.el.removeEventListener("click", this.handleClick);
  },

  reset() {
    if (!this.elements) return;

    this.abort();
    this.started = false;

    const { code, prompt, response, promptCursor, responseCursor, responseSection, trigger } = this.elements;
    prompt.textContent = "";
    response.textContent = "";
    responseSection.style.display = "none";
    promptCursor.style.visibility = "hidden";
    responseCursor.style.visibility = "hidden";
    trigger.disabled = false;
    trigger.removeAttribute("data-played");
    code.scrollTop = 0;
  },

  start() {
    if (!this.elements || this.started) return;

    this.started = true;
    this.elements.trigger.disabled = true;
    this.elements.trigger.setAttribute("data-played", "true");

    if (this.prefersReducedMotion) {
      this.renderInstant();
    } else {
      this.animate();
    }
  },

  renderInstant() {
    const { code, prompt, response, responseSection } = this.elements;
    prompt.textContent = this.prompt;
    response.textContent = this.responseSteps.map((s) => s.text).join("\n");
    responseSection.style.display = "";
    this.scrollToBottom(code);
  },

  async animate() {
    const { code, prompt, promptCursor, responseCursor, response, responseSection } = this.elements;
    const signal = this.createAbortSignal();

    promptCursor.style.visibility = "visible";
    await this.typeText(prompt, this.prompt, TIMING.promptCharMs, signal);
    promptCursor.style.visibility = "hidden";

    await this.delay(TIMING.promptToResponseMs, signal);

    responseSection.style.display = "";
    responseCursor.style.visibility = "visible";
    this.scrollToBottom(code);

    for (let i = 0; i < this.responseSteps.length; i++) {
      const step = this.responseSteps[i];
      const text = i === 0 ? step.text : `\n${step.text}`;
      await this.typeRichText(response, text, signal);
      this.scrollToBottom(code);
      await this.delay(step.waitMs || TIMING.stepPauseMs, signal);
    }

    responseCursor.style.visibility = "hidden";
  },

  async typeText(container, text, charMs, signal) {
    const node = document.createTextNode("");
    container.appendChild(node);

    for (const char of text) {
      signal.throwIfAborted();
      node.textContent += char;
      this.scrollToBottom(this.elements.code);
      await this.delay(charMs, signal);
    }
  },

  async typeRichText(container, text, signal) {
    for (const segment of segmentText(text)) {
      signal.throwIfAborted();

      if (segment.type === "link") {
        const link = document.createElement("a");
        link.href = segment.value;
        link.target = "_blank";
        link.rel = "noreferrer";
        link.textContent = segment.value;
        container.appendChild(link);
        this.scrollToBottom(this.elements.code);
        await this.delay(TIMING.responseCharMs, signal);
      } else {
        await this.typeText(container, segment.value, TIMING.responseCharMs, signal);
      }
    }
  },

  delay(ms, signal) {
    if (signal?.aborted) return Promise.reject(signal.reason);
    return new Promise((resolve, reject) => {
      const id = setTimeout(resolve, ms);
      signal?.addEventListener("abort", () => { clearTimeout(id); reject(signal.reason); }, { once: true });
    });
  },

  createAbortSignal() {
    this.abortController = new AbortController();
    return this.abortController.signal;
  },

  abort() {
    this.abortController?.abort();
    this.abortController = null;
  },

  scrollToBottom(element) {
    const distanceFromBottom = element.scrollHeight - element.scrollTop - element.clientHeight;
    if (distanceFromBottom < SCROLL_THRESHOLD) {
      element.scrollTop = element.scrollHeight;
    }
  },
};

export { AgentPrompt };
