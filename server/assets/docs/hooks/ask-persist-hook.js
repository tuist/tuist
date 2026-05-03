const STORAGE_KEY = "tuist:docs-ask:v1";
const MAX_PERSISTED_MESSAGES = 50;

function logPersistenceError(action, error) {
  console.warn(`Failed to ${action} for the docs Ask AI history.`, error);
}

function runStorageTask(task) {
  if (window.scheduler?.postTask) {
    return window.scheduler.postTask(task, { priority: "background" });
  }

  return new Promise((resolve, reject) => {
    window.setTimeout(() => {
      try {
        resolve(task());
      } catch (error) {
        reject(error);
      }
    }, 0);
  });
}

async function readMessages() {
  try {
    return await runStorageTask(() => {
      const raw = window.localStorage.getItem(STORAGE_KEY);
      if (!raw) return [];

      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : [];
    });
  } catch (error) {
    logPersistenceError("restore persisted messages", error);
    return [];
  }
}

async function persistMessages(messages) {
  try {
    const trimmed = Array.isArray(messages)
      ? messages.slice(-MAX_PERSISTED_MESSAGES)
      : [];

    await runStorageTask(() => {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(trimmed));
    });
  } catch (error) {
    logPersistenceError("persist messages", error);
  }
}

async function clearMessages() {
  try {
    await runStorageTask(() => {
      window.localStorage.removeItem(STORAGE_KEY);
    });
  } catch (error) {
    logPersistenceError("clear persisted messages", error);
  }
}

const AskPersistHook = {
  async mounted() {
    this.shouldHydrateStoredMessages = true;

    this.handleEvent("docs-ask:save", ({ messages }) => {
      this.shouldHydrateStoredMessages = false;
      void persistMessages(messages);
    });

    this.handleEvent("docs-ask:clear", () => {
      this.shouldHydrateStoredMessages = false;
      void clearMessages();
    });

    const messages = await readMessages();
    if (!this.el.isConnected || !this.shouldHydrateStoredMessages || messages.length === 0) return;

    this.pushEventTo(this.el, "hydrate", { messages });
  },
};

export default AskPersistHook;
