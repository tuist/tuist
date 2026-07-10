function websocketURL(path) {
  const url = new URL(path, window.location.href);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  return url.href;
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const maxLines = 2000;

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

function csiParameter(parameters, fallback = 1) {
  const first = parameters.split(";")[0]?.replace(/^\?/, "");
  const parsed = Number.parseInt(first, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function csiParameters(parameters, fallback = [1]) {
  if (!parameters) return fallback;

  const parsed = parameters
    .replace(/^\?/, "")
    .split(";")
    .map((parameter) => Number.parseInt(parameter, 10))
    .map((parameter) => (Number.isFinite(parameter) ? parameter : 1));

  return parsed.length > 0 ? parsed : fallback;
}

function escapeSequence(input, index) {
  if (index + 1 >= input.length) return { incomplete: true };

  const type = input[index + 1];
  if (type === "[") {
    let cursor = index + 2;
    while (cursor < input.length) {
      const code = input.charCodeAt(cursor);
      if (code >= 0x40 && code <= 0x7e) {
        return {
          kind: "csi",
          parameters: input.slice(index + 2, cursor),
          command: input[cursor],
          end: cursor,
        };
      }
      cursor += 1;
    }

    return { incomplete: true };
  }

  if (type === "]") {
    let cursor = index + 2;
    while (cursor < input.length) {
      if (input[cursor] === "\x07") return { kind: "osc", end: cursor };
      if (input[cursor] === "\x1b" && input[cursor + 1] === "\\") {
        return { kind: "osc", end: cursor + 1 };
      }
      cursor += 1;
    }

    return { incomplete: true };
  }

  if ((type === "(" || type === ")") && index + 2 >= input.length) return { incomplete: true };

  return { kind: "escape", command: type, end: type === "(" || type === ")" ? index + 2 : index + 1 };
}

class TerminalScreen {
  constructor(output) {
    this.output = output;
    this.lines = [""];
    this.cursorRow = 0;
    this.cursorColumn = 0;
    this.pending = "";
    this.cursorVisible = true;
  }

  write(text) {
    if (!text) return;

    const input = this.pending + text;
    this.pending = "";

    for (let index = 0; index < input.length; index += 1) {
      const character = input[index];

      if (character === "\x1b") {
        const sequence = escapeSequence(input, index);
        if (sequence.incomplete) {
          this.pending = input.slice(index);
          break;
        }

        this.applyEscape(sequence);
        index = sequence.end;
        continue;
      }

      this.writeCharacter(character);
    }

    this.trimScrollback();
    this.render();
  }

  writeCharacter(character) {
    switch (character) {
      case "\x00":
      case "\x07":
      case "\x0e":
      case "\x0f":
        return;
      case "\r":
        this.cursorColumn = 0;
        return;
      case "\n":
        this.cursorRow += 1;
        this.ensureCursor();
        return;
      case "\b":
      case "\x7f":
        this.cursorColumn = Math.max(0, this.cursorColumn - 1);
        return;
      case "\t":
        this.writeSpaces(8 - (this.cursorColumn % 8));
        return;
      case "\f":
        this.clear();
        return;
      default:
        if (character.charCodeAt(0) < 32) return;
        this.put(character);
    }
  }

  writeSpaces(count) {
    for (let index = 0; index < count; index += 1) this.put(" ");
  }

  put(character) {
    this.ensureCursor();

    let line = this.lines[this.cursorRow] || "";
    if (this.cursorColumn > line.length) line = line.padEnd(this.cursorColumn, " ");

    this.lines[this.cursorRow] =
      line.slice(0, this.cursorColumn) + character + line.slice(this.cursorColumn + 1);
    this.cursorColumn += 1;
  }

  applyEscape(sequence) {
    if (sequence.kind !== "csi") return;

    switch (sequence.command) {
      case "A":
        this.cursorRow = Math.max(0, this.cursorRow - csiParameter(sequence.parameters));
        return;
      case "B":
        this.cursorRow += csiParameter(sequence.parameters);
        this.ensureCursor();
        return;
      case "C":
        this.cursorColumn += csiParameter(sequence.parameters);
        this.ensureCursor();
        return;
      case "D":
        this.cursorColumn = Math.max(0, this.cursorColumn - csiParameter(sequence.parameters));
        return;
      case "G":
        this.cursorColumn = Math.max(0, csiParameter(sequence.parameters) - 1);
        this.ensureCursor();
        return;
      case "H":
      case "f": {
        const [row, column] = csiParameters(sequence.parameters, [1, 1]);
        this.cursorRow = Math.max(0, row - 1);
        this.cursorColumn = Math.max(0, column - 1);
        this.ensureCursor();
        return;
      }
      case "J":
        this.eraseDisplay(Number.parseInt(sequence.parameters || "0", 10) || 0);
        return;
      case "K":
        this.eraseLine(Number.parseInt(sequence.parameters || "0", 10) || 0);
        return;
      case "h":
        if (sequence.parameters === "?25") this.cursorVisible = true;
        return;
      case "l":
        if (sequence.parameters === "?25") this.cursorVisible = false;
        return;
      case "m":
        return;
      default:
        return;
    }
  }

  eraseDisplay(mode) {
    this.ensureCursor();

    if (mode === 2 || mode === 3) {
      this.clear();
      return;
    }

    if (mode === 1) {
      this.lines = [this.currentLine().slice(this.cursorColumn)];
      this.cursorRow = 0;
      this.cursorColumn = 0;
      return;
    }

    this.lines = this.lines.slice(0, this.cursorRow + 1);
    this.eraseLine(0);
  }

  eraseLine(mode) {
    this.ensureCursor();

    const line = this.currentLine();
    if (mode === 2) {
      this.lines[this.cursorRow] = "";
    } else if (mode === 1) {
      this.lines[this.cursorRow] = " ".repeat(Math.min(this.cursorColumn, line.length)) + line.slice(this.cursorColumn);
    } else {
      this.lines[this.cursorRow] = line.slice(0, this.cursorColumn);
    }
  }

  clear() {
    this.lines = [""];
    this.cursorRow = 0;
    this.cursorColumn = 0;
  }

  currentLine() {
    return this.lines[this.cursorRow] || "";
  }

  ensureCursor() {
    while (this.cursorRow >= this.lines.length) this.lines.push("");
  }

  trimScrollback() {
    if (this.lines.length <= maxLines) return;

    const dropped = this.lines.length - maxLines;
    this.lines = this.lines.slice(dropped);
    this.cursorRow = Math.max(0, this.cursorRow - dropped);
  }

  render() {
    const fragment = document.createDocumentFragment();

    this.lines.forEach((line, index) => {
      const row = document.createElement("div");
      row.dataset.part = "terminal-line";

      if (index === this.cursorRow && this.cursorVisible) {
        const cursorColumn = Math.min(this.cursorColumn, line.length);
        row.append(document.createTextNode(line.slice(0, cursorColumn)));

        const cursor = document.createElement("span");
        cursor.dataset.part = "terminal-cursor";
        cursor.textContent = line[cursorColumn] || " ";
        row.append(cursor);
        row.append(document.createTextNode(line.slice(cursorColumn + 1)));
      } else {
        row.textContent = line || " ";
      }

      fragment.append(row);
    });

    this.output.replaceChildren(fragment);
  }
}

class TerminalSimulation {
  constructor(write) {
    this.write = write;
    this.line = "";
    this.cwd = "~/work";
  }

  start() {
    this.write("\x1b[2J\x1b[H");
    this.write("tuist@runner " + this.cwd + " % ");
  }

  input(text) {
    for (let index = 0; index < text.length; index += 1) {
      const character = text[index];

      if (character === "\x1b") {
        if (text[index + 1] === "\x7f") {
          this.deletePreviousWord();
          index += 1;
          continue;
        }

        const sequence = escapeSequence(text, index);
        if (sequence.incomplete) return;
        index = sequence.end;
        continue;
      }

      if (character === "\r" || character === "\n") {
        this.write("\r\n");
        this.runCommand();
        this.line = "";
        this.prompt();
      } else if (character === "\x03") {
        this.write("^C\r\n");
        this.line = "";
        this.prompt();
      } else if (character === "\x15") {
        this.deleteLine();
      } else if (character === "\b" || character === "\x7f") {
        this.deletePreviousCharacter();
      } else if (character === "\t") {
        this.line += "  ";
        this.write("  ");
      } else if (character.charCodeAt(0) >= 32) {
        this.line += character;
        this.write(character);
      }
    }
  }

  deletePreviousCharacter() {
    this.deleteCharacters(1);
  }

  deletePreviousWord() {
    let cursor = this.line.length;

    while (cursor > 0 && /\s/.test(this.line[cursor - 1])) cursor -= 1;
    while (cursor > 0 && !/\s/.test(this.line[cursor - 1])) cursor -= 1;

    this.deleteCharacters(this.line.length - cursor);
  }

  deleteLine() {
    this.deleteCharacters(this.line.length);
  }

  deleteCharacters(count) {
    if (count <= 0) return;

    this.line = this.line.slice(0, -count);
    this.write("\b".repeat(count) + "\x1b[K");
  }

  runCommand() {
    const command = this.line.trim();
    if (!command) return;

    if (command === "clear") {
      this.write("\x1b[2J\x1b[H");
      return;
    }

    if (command === "pwd") {
      this.write("/Users/runner/work/tuist/tuist\r\n");
      return;
    }

    if (command === "ls") {
      this.write("AGENTS.md  cli  infra  server  tuist_common\r\n");
      return;
    }

    if (command === "whoami") {
      this.write("runner\r\n");
      return;
    }

    if (command === "date") {
      this.write(`${new Date().toISOString()}\r\n`);
      return;
    }

    if (command === "echo" || command.startsWith("echo ")) {
      this.write(`${this.echo(command.slice(4))}\r\n`);
      return;
    }

    this.write(`zsh: command not found: ${command}\r\n`);
  }

  echo(input) {
    const trimmed = input.trim();
    if (
      (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
      (trimmed.startsWith("'") && trimmed.endsWith("'"))
    ) {
      return trimmed.slice(1, -1);
    }

    return trimmed;
  }

  prompt() {
    this.write("tuist@runner " + this.cwd + " % ");
  }
}

export default {
  mounted() {
    this.output = this.el.querySelector('[data-part="interactive-terminal-output"]');
    this.screen = new TerminalScreen(this.output);
    this.simulation = null;
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
    if (this.el.dataset.shellSimulation === "true") {
      this.el.dataset.connection = "connected";
      this.el.dataset.shellStatus = "simulated";
      this.simulation = new TerminalSimulation((text) => this.append(text));
      this.simulation.start();
      this.el.focus();
      return;
    }

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
    this.simulation = null;
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

    let sequence = null;
    if (event.key === "Backspace" && event.metaKey) sequence = "\x15";
    if (!sequence && event.key === "Backspace" && event.altKey) sequence = "\x1b\x7f";
    if (!sequence) sequence = keySequences[event.key];
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
    if (this.simulation) {
      this.simulation.input(text);
      return;
    }

    this.socket.send(encoder.encode(text));
  },

  sendResize() {
    if (!this.connected() || this.simulation) return;

    this.socket.send(JSON.stringify({ type: "resize", ...terminalSize(this.el) }));
  },

  append(text) {
    this.screen.write(text);
    this.el.scrollTop = this.el.scrollHeight;
  },

  connected() {
    return Boolean(this.simulation) || this.socket?.readyState === WebSocket.OPEN;
  },
};
