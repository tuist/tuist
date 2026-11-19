// Matches the server's template: decision data, not model-authored UI.
import { mount, Decision } from "./luft";

mount(() => <Decision
  question="How should we investigate the slow builds?"
  options={[
    { id: "cache", label: "Investigate cache misses, including changes to build settings and dependencies that invalidate otherwise reusable targets" },
    { id: "timing", label: "Compare build timings" },
    { id: "later", label: "Leave the investigation for later" },
  ]}
  allowOther={true}
/>);
