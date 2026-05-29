import { copyTextToClipboard } from "../../shared/js/clipboard.js";

/**
 * Receives a server `push_event` carrying a serialized payload and either
 * copies it to the clipboard or downloads it as a file. Reusable across
 * pages: the event name is read from `data-copy-download-event` on the
 * hook element, so a LiveView wires it with
 *
 *   <div phx-hook="CopyOrDownload" data-copy-download-event="my-event" hidden></div>
 *
 * and pushes `{ format, payload, filename }`. A `format` of "download-csv"
 * triggers a CSV download; any other format copies the payload.
 */
export default {
  mounted() {
    const eventName = this.el.dataset.copyDownloadEvent;
    if (!eventName) return;

    this.handleEvent(eventName, ({ format, payload, filename }) => {
      if (format === "download-csv") {
        downloadAs(payload, filename, "text/csv");
      } else {
        copyTextToClipboard(payload).catch((error) => {
          console.warn("Failed to copy payload to clipboard", error);
        });
      }
    });
  },
};

function downloadAs(payload, filename, mime) {
  const blob = new Blob([payload], { type: mime });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
  URL.revokeObjectURL(url);
}
