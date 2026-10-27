// Verbatim copy of server/assets/marketing/css/shared/tokens.css (the redesigned
// marketing site's page-frame, stroke and illustration-ramp tokens), so the
// status page shares the marketing look without depending on the Phoenix build.
// Regenerate after the marketing tokens change; the only edit is swapping the
// backticks inside CSS comments for straight quotes so the template literal
// survives.
export const MARKETING_TOKENS_CSS = String.raw`
/*This file contains tokens that are specific to the marketing site*/

:root {
  /*
   * Breakpoints for responsive design
   *
   * These breakpoint values define the viewport widths where layout changes occur:
   * - sm: 370px (small mobile devices)
   * - md: 1024px (tablets and small desktops)
   * - lg: 1440px (large desktops)
   */
  --marketing-breakpoint-lg: 1440px;
  --marketing-breakpoint-md: 1024px;
  --marketing-breakpoint-sm: 370px;

  /*
   * Page container: content is exactly --marketing-page-width on wide
   * viewports; --marketing-page-margin doubles as the mobile gutter.
   * Containers use max-width: --marketing-page-width-with-margin together
   * with padding-inline: --marketing-page-margin (border-box).
   */
  --marketing-page-margin: var(--noora-spacing-8);
  --marketing-page-width: 1200px;
  --marketing-page-width-with-margin: calc(var(--marketing-page-width) + var(--marketing-page-margin) * 2);

  @media (max-width: 768px) {
    --marketing-page-margin: var(--noora-spacing-2);
  }

  --marketing-stroke-default: light-dark(var(--noora-neutral-light-200), var(--noora-neutral-dark-1000));

  /*
   * Cursor-proximity edge glow mask stops, shared by the navbar hairline,
   * hero card, and platform panels. Only the alpha channel matters in a
   * mask: the first stop is fully opaque (reveal), the second fully
   * transparent (hide). Use sites write the radial-gradient themselves with
   * 'at var(--hx, -9999px) var(--hy, -9999px)' — the coordinates must live
   * in the use-site declaration because var() inside a :root token would
   * resolve against :root (where --hx is never set), not the glow element.
   */
  --marketing-edge-glow-stops: var(--noora-neutral-light-900) 25%,
    color-mix(in oklch, var(--noora-neutral-light-900), transparent 100%) 75%;

  /* The color the edge glow reveals (the glow layer's border color). */
  --marketing-edge-glow-color: var(--marketing-illustration-neutral-3);

  /*
   * Tinted fills: pale -50 tints in light mode, translucent color washes in
   * dark mode (the alpha composites over the page background, like Noora's
   * --noora-alpha-* tokens). --marketing-tint-alpha is the dark-mode
   * strength knob — raise it to make the dithered fills denser/brighter.
   * Canvas hooks resolve these too, so a change retunes the cache chart,
   * runner grid and test grid together.
   */
  --marketing-tint-alpha: 40%;
  --marketing-tint-purple: light-dark(
    var(--noora-purple-50),
    color-mix(in oklch, var(--noora-purple-500) var(--marketing-tint-alpha), transparent)
  );
  /* Red reads hotter than purple at the same strength, so it gets its own
     dark alpha instead of --marketing-tint-alpha. */
  --marketing-tint-red: light-dark(var(--noora-red-50), color-mix(in oklch, var(--noora-red-500) 20%, transparent));

  --marketing-illustration-neutral-1: light-dark(var(--noora-neutral-light-200), var(--noora-neutral-dark-1000));
  --marketing-illustration-neutral-2: light-dark(var(--noora-neutral-light-300), var(--noora-neutral-dark-900));
  --marketing-illustration-neutral-3: light-dark(var(--noora-neutral-light-400), var(--noora-neutral-dark-800));
  --marketing-illustration-neutral-4: light-dark(var(--noora-neutral-light-500), var(--noora-neutral-dark-700));
  --marketing-illustration-neutral-5: light-dark(var(--noora-neutral-light-600), var(--noora-neutral-dark-600));
  --marketing-illustration-neutral-6: light-dark(var(--noora-neutral-light-700), var(--noora-neutral-dark-500));
  --marketing-illustration-neutral-7: light-dark(var(--noora-neutral-light-800), var(--noora-neutral-dark-400));
  --marketing-illustration-neutral-8: light-dark(var(--noora-neutral-light-900), var(--noora-neutral-dark-300));
  --marketing-illustration-neutral-9: light-dark(var(--noora-neutral-light-1000), var(--noora-neutral-dark-200));
  --marketing-illustration-neutral-10: light-dark(var(--noora-neutral-light-1100), var(--noora-neutral-dark-100));

  /* The navigation bar is sticky and absolutely positioned. If there are other sticky elements, they should be sticky with this top offset */
  --sticky-top: 72px;

  @media (max-width: 480px) {
    --sticky-top: 48px;
  }
}
`;
