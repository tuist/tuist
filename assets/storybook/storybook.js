import * as NooraComponents from "../_noora/noora.js";

const Hooks = {};

Object.keys(NooraComponents).forEach((key) => {
  Hooks[key] = NooraComponents[key];
});

window.storybook = { Hooks };
