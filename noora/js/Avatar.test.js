// @vitest-environment happy-dom
import { afterEach, expect, it } from "vitest";
import Avatar from "./Avatar.js";

let hook;

afterEach(() => {
  hook?.beforeDestroy();
  document.body.innerHTML = "";
});

it("shows the image once it loads", async () => {
  document.body.innerHTML = `
    <div class="noora-avatar" id="avatar" phx-hook="NooraAvatar">
      <img data-part="image" src="/avatar.png" />
      <span data-part="initials">PP</span>
    </div>`;
  const el = document.getElementById("avatar");
  const image = el.querySelector('[data-part="image"]');
  hook = { ...Avatar, el, pushEvent: () => {} };
  hook.mounted();

  expect(image.dataset.state).toBe("hidden");

  image.dispatchEvent(new Event("load"));
  await new Promise((resolve) => setTimeout(resolve, 0));

  expect(image.dataset.state).toBe("visible");
  expect(el.id).toBe("avatar");
});
