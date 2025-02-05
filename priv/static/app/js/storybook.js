import NooraDropdown from "./components/Dropdown.js";
import NooraTooltip from "./components/Tooltip.js";

let Hooks = {};
Hooks.NooraDropdown = NooraDropdown;
Hooks.NooraTooltip = NooraTooltip;

window.storybook = { Hooks };
