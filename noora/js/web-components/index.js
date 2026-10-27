import { NooraBadge, registerNooraBadge } from "./Badge.js";
import { NooraButton, registerNooraButton } from "./Button.js";
import { registerRemainingNooraComponents } from "./Remaining.js";

registerNooraBadge();
registerNooraButton();
registerRemainingNooraComponents();

export { NooraBadge, NooraButton, registerNooraBadge, registerNooraButton };
export * from "./Remaining.js";
