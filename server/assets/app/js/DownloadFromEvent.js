/**
 * Receives a server `push_event` carrying `{ payload, filename, mime }`
 * and triggers a browser download of the payload as a file. Reusable
 * across pages: the event name is read from `data-event` on the hook
 * element. Wire with:
 *
 *   <div phx-hook="DownloadFromEvent" data-event="my-download-event" hidden></div>
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
