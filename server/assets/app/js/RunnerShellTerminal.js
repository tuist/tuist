function websocketURL(path) {
  const url = new URL(path, window.location.href);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  return url.href;
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();

const keySequences = {
  Enter: "\r",
  Backspace: "\x7f",
  Tab: "\t",
  Escape: "\x1b",
  ArrowUp: "\x1b[A",
  ArrowDown: "\x1b[B",
  ArrowRight: "\x1b[C",
  ArrowLeft: "\x1b[D",
  Home: "\x1b[H",
  End: "\x1b[F",
  Delete: "\x1b[3~",
  PageUp: "\x1b[5~",
  PageDown: "\x1b[6~",
};

function controlSequence(key) {
  if (key.length !== 1) return null;

  const code = key.toUpperCase().charCodeAt(0);
  if (code < 64 || code > 95) return null;

  return String.fromCharCode(code - 64);
}

function terminalSize(element) {
  const style = window.getComputedStyle(element);
  const fontSize = parseFloat(style.fontSize) || 13;
  const lineHeight = parseFloat(style.lineHeight) || fontSize * 1.4;
  const columns = Math.max(20, Math.floor(element.clientWidth / (fontSize * 0.62)));
  const rows = Math.max(6, Math.floor(element.clientHeight / lineHeight));

  return { columns, rows };
}

export default {
  mounted() {
    this.output = this.el.querySelector('[data-part="interactive-terminal-output"]');
    this.buffer = "";
    this.onKeyDown = (event) => this.handleKeyDown(event);
    this.onPaste = (event) => this.handlePaste(event);
    this.onResize = () => this.sendResize();

    this.el.addEventListener("keydown", this.onKeyDown);
    this.el.addEventListener("paste", this.onPaste);
    this.resizeObserver = new ResizeObserver(this.onResize);
    this.resizeObserver.observe(this.el);

    this.connect();
  },

  destroyed() {
    this.disconnect();
    this.resizeObserver?.disconnect();
    this.el.removeEventListener("keydown", this.onKeyDown);
    this.el.removeEventListener("paste", this.onPaste);
  },

  connect() {
    const path = this.el.dataset.shellPath;
    const token = this.el.dataset.shellToken;
    if (!path || !token) {
      this.el.dataset.connection = "idle";
      return;
    }

    this.el.dataset.connection = "connecting";
    this.socket = new WebSocket(websocketURL(path), [token]);
    this.socket.binaryType = "arraybuffer";

    this.socket.addEventListener("open", () => {
      this.el.dataset.connection = "connected";
      this.el.focus();
      this.sendResize();
    });

    this.socket.addEventListener("message", (event) => this.handleMessage(event));
    this.socket.addEventListener("close", () => {
      this.el.dataset.connection = "closed";
    });
    this.socket.addEventListener("error", () => {
      this.el.dataset.connection = "error";
    });
  },

  disconnect() {
    if (!this.socket) return;

    if (this.socket.readyState === WebSocket.OPEN) {
      this.socket.send(JSON.stringify({ type: "close" }));
    }

    this.socket.close();
    this.socket = null;
  },

  handleMessage(event) {
    if (typeof event.data === "string") {
      this.handleControlMessage(event.data);
      return;
    }

    if (event.data instanceof ArrayBuffer) {
      this.append(decoder.decode(new Uint8Array(event.data)));
      return;
    }

    if (event.data instanceof Blob) {
      event.data.arrayBuffer().then((buffer) => this.append(decoder.decode(new Uint8Array(buffer))));
    }
  },

  handleControlMessage(data) {
    try {
      const message = JSON.parse(data);
      if (message.type === "status") this.el.dataset.shellStatus = message.status;
      if (message.type === "exit") this.el.dataset.shellExitStatus = `${message.status}`;
    } catch (_error) {
      this.append(data);
    }
  },

  handleKeyDown(event) {
    if (!this.connected()) return;

    let sequence = keySequences[event.key];
    if (!sequence && event.ctrlKey) sequence = controlSequence(event.key);
    if (!sequence && !event.metaKey && !event.altKey && event.key.length === 1) sequence = event.key;
    if (!sequence) return;

    event.preventDefault();
    this.send(sequence);
  },

  handlePaste(event) {
    if (!this.connected()) return;

    const text = event.clipboardData?.getData("text");
    if (!text) return;

    event.preventDefault();
    this.send(text);
  },

  send(text) {
    this.socket.send(encoder.encode(text));
  },

  sendResize() {
    if (!this.connected()) return;

    this.socket.send(JSON.stringify({ type: "resize", ...terminalSize(this.el) }));
  },

  append(text) {
    this.buffer += text;
    if (this.buffer.length > 200000) this.buffer = this.buffer.slice(-150000);
    this.output.textContent = this.buffer;
    this.el.scrollTop = this.el.scrollHeight;
  },

  connected() {
    return this.socket?.readyState === WebSocket.OPEN;
  },
};
