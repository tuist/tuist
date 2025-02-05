import NooraDropdown from "./components/Dropdown.js";
import NooraModal from "./components/Modal.js";
import NooraTooltip from "./components/Tooltip.js";

let Hooks = {};
Hooks.NooraDropdown = NooraDropdown;
Hooks.NooraModal = NooraModal;
Hooks.NooraTooltip = NooraTooltip;

window.storybook = { Hooks };
