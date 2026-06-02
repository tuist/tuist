/**
 * Triggers a browser download of a server-supplied payload as a file.
 * The hook listens for a Phoenix LiveView `push_event` whose name is
 * read from `data-event`, and downloads the event's `payload` field as
 * `filename` (with optional `mime`). Wire with:
 *
 *   <div phx-hook="DownloadAsFile" data-event="my-download-event" hidden></div>
 */
export default {
  mounted() {
    const eventName = this.el.dataset.event;
    if (!eventName) return;

    this.handleEvent(eventName, ({ payload, filename, mime }) => {
      const blob = new Blob([payload], { type: mime || "application/octet-stream" });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = filename;
      document.body.appendChild(anchor);
      anchor.click();
      document.body.removeChild(anchor);
      URL.revokeObjectURL(url);
    });
  },
};
