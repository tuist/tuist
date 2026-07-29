import { copyTextToClipboard } from "../../shared/js/clipboard.js";

/**
 * Copies a server-supplied payload to the clipboard. The hook listens
 * for a Phoenix LiveView `push_event` whose name is read from
 * `data-event` and copies the event's `payload` field. Wire with:
 *
 *   <div phx-hook="CopyToClipboard" data-event="my-copy-event" hidden></div>
 *
 * Click-driven copy lives in the separate `Clipboard` hook
 * (`data-clipboard-value`); this one is for the server-driven case
 * where the server builds the payload first.
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
