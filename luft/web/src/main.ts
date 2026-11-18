// The web edge: it renders what the core worker reports and nothing more.
const status = document.querySelector<HTMLParagraphElement>("#status")!;
const list = document.querySelector<HTMLUListElement>("#themes")!;

const core = new Worker(new URL("./core.worker.ts", import.meta.url), { type: "module" });
core.onmessage = (event: MessageEvent<{ themes: string[] }>) => {
  status.textContent = `The Rust core is running in a worker and knows ${event.data.themes.length} themes:`;
  list.replaceChildren(
    ...event.data.themes.map((name) => {
      const item = document.createElement("li");
      item.textContent = name;
      return item;
    }),
  );
};
core.onerror = (event) => {
  status.textContent = `The Luft core failed to start: ${event.message}`;
};
