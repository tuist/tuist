import { copyTextToClipboard } from "../../shared/js/clipboard.js";

/**
 * Receives a server `push_event` carrying `{ payload }` and copies the
 * payload to the clipboard. Reusable across pages: the event name is
 * read from `data-event` on the hook element. Wire with:
 *
 *   <div phx-hook="CopyFromEvent" data-event="my-copy-event" hidden></div>
 *
 * Click-driven copy lives in the separate `Clipboard` hook
 * (`data-clipboard-value`); this one is for the server-push-driven
 * case where the server builds the payload first.
 */
export default {
  mounted() {
    const eventName = this.el.dataset.event;
    if (!eventName) return;

    this.handleEvent(eventName, ({ payload }) => {
      copyTextToClipboard(payload).catch((error) => {
        console.warn("Failed to copy payload to clipboard", error);
      });
    });
  },
};
