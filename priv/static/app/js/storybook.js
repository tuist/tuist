import NooraDropdown from "./components/Dropdown.js";
import NooraDigitInput from "./components/DigitInput.js";
import NooraModal from "./components/Modal.js";
import NooraTooltip from "./components/Tooltip.js";

let Hooks = {};
Hooks.NooraDropdown = NooraDropdown;
Hooks.NooraDigitInput = NooraDigitInput;
Hooks.NooraModal = NooraModal;
Hooks.NooraTooltip = NooraTooltip;

window.storybook = { Hooks };
