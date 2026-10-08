// @vitest-environment happy-dom
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { transformSync } from "esbuild";
import { afterEach, expect, it } from "vitest";
const styles = transformSync(
  ["text_input", "tooltip"]
    .map((name) =>
      readFileSync(resolve(import.meta.dirname, `../css/${name}.css`), "utf8"),
    )
    .join("\n"),
  { loader: "css", target: "chrome100" },
).code;

afterEach(() => {
  document.body.innerHTML = "";
});

it("keeps suffix tooltip content in flow so its positioner can measure the full size", () => {
  document.body.innerHTML = `
    <style>${styles}</style>
    <div class="noora-text-input">
      <div data-part="wrapper">
        <input id="api-url" />
        <div data-part="suffix-hint">
          <div id="api-url-hint" class="noora-tooltip" data-positioning-placement="bottom-end">
            <span data-part="trigger" tabindex="0" data-state="open">Help</span>
            <div data-part="positioner" style="position: absolute">
              <div data-part="content" data-size="small">The REST API base URL Tuist servers can access, including /api/v3.</div>
            </div>
          </div>
        </div>
      </div>
    </div>`;
  const positioner = document.querySelector('[data-part="positioner"]');
  const content = document.querySelector('[data-part="content"]');
  expect(getComputedStyle(positioner).position).toBe("absolute");
  expect(getComputedStyle(positioner).display).toBe("flex");
  expect(getComputedStyle(content).position).not.toBe("absolute");
  expect(getComputedStyle(content).position).not.toBe("fixed");
  expect(getComputedStyle(content).maxWidth).toBe("250px");
});
