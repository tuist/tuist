const STORAGE_KEY = "tuist:docs-ask:v1";
const MAX_PERSISTED_MESSAGES = 50;

function readStored() {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (_e) {
    return [];
  }
}

function writeStored(messages) {
  try {
    const trimmed = Array.isArray(messages)
      ? messages.slice(-MAX_PERSISTED_MESSAGES)
      : [];
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(trimmed));
  } catch (_e) {
    // localStorage can throw in private mode or when full; ignore.
  }
}

function clearStored() {
  try {
    window.localStorage.removeItem(STORAGE_KEY);
  } catch (_e) {
    // ignore
  }
}

const DocsAskPersistHook = {
  mounted() {
    const messages = readStored();
    if (messages.length > 0) {
      this.pushEventTo(this.el, "hydrate", { messages });
    }

    this.handleEvent("docs-ask:save", ({ messages }) => writeStored(messages));
    this.handleEvent("docs-ask:clear", () => clearStored());
  },
};

export default DocsAskPersistHook;
