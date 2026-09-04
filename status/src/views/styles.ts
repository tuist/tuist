import { MARKETING_TOKENS_CSS } from "./marketing-tokens.js";
import { NOORA_CSS } from "./noora-css.js";

// Page glue in the redesigned marketing site's idiom: a primary-surface page
// made of 1200px hairline-framed sections separated by 2px seams, the 72px
// navbar bar with the 32px wordmark, and an open-bottom footer frame. Only
// the tokens are shared with the marketing bundle; everything below is the
// status page's own layout.
const PAGE_CSS = `
/* Registered as colors so the wave script reads computed colors (with
   light-dark() already resolved) from getComputedStyle instead of the raw
   declaration text. One ramp of four per wave state. */
@property --wave-ink-operational-1 {
  syntax: "<color>";
  inherits: true;
  initial-value: transparent;
}
@property --wave-ink-operational-2 {
  syntax: "<color>";
  inherits: true;
  initial-value: transparent;
}
@property --wave-ink-operational-3 {
  syntax: "<color>";
  inherits: true;
  initial-value: transparent;
}
@property --wave-ink-operational-4 {
  syntax: "<color>";
  inherits: true;
  initial-value: transparent;
}
@property --wave-ink-degraded-1 {
  syntax: "<color>";
  inherits: true;
  initial-value: transparent;
}
@property --wave-ink-degraded-2 {
  syntax: "<color>";
  inherits: true;
  initial-value: transparent;
}
@property --wave-ink-degraded-3 {
  syntax: "<color>";
  inherits: true;
  initial-value: transparent;
}
@property --wave-ink-degraded-4 {
  syntax: "<color>";
  inherits: true;
  initial-value: transparent;
}
@property --wave-ink-outage-1 {
  syntax: "<color>";
  inherits: true;
  initial-value: transparent;
}
@property --wave-ink-outage-2 {
  syntax: "<color>";
  inherits: true;
  initial-value: transparent;
}
@property --wave-ink-outage-3 {
  syntax: "<color>";
  inherits: true;
  initial-value: transparent;
}
@property --wave-ink-outage-4 {
  syntax: "<color>";
  inherits: true;
  initial-value: transparent;
}
@property --wave-ink-maintenance-1 {
  syntax: "<color>";
  inherits: true;
  initial-value: transparent;
}
@property --wave-ink-maintenance-2 {
  syntax: "<color>";
  inherits: true;
  initial-value: transparent;
}
@property --wave-ink-maintenance-3 {
  syntax: "<color>";
  inherits: true;
  initial-value: transparent;
}
@property --wave-ink-maintenance-4 {
  syntax: "<color>";
  inherits: true;
  initial-value: transparent;
}

:root {
  /* Inter from rsms.me is served under the "InterVariable" family name;
     Noora's tokens ask for "Inter Variable". Point both text families at it. */
  --noora-font-body: "InterVariable", "Inter", sans-serif;
  --noora-font-heading: "InterVariable", "Inter", sans-serif;
  color-scheme: light dark;
}

html, body {
  margin: 0;
  padding: 0;
}

body {
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: var(--noora-spacing-1);
  min-height: 100vh;
  background: var(--noora-surface-background-primary);
  color: var(--noora-surface-label-primary);
  font: var(--noora-font-weight-regular) var(--noora-font-body-medium);
  text-wrap: pretty;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

:focus-visible {
  outline: 2px solid light-dark(var(--noora-purple-500), var(--noora-purple-300));
  outline-offset: 2px;
}

/* Brand marks: purple petals (500 on light, 400 on dark, like the navbar's
   two SVG variants) and a label-colored wordmark. */
[data-part="petals"] {
  fill: light-dark(var(--noora-purple-500), var(--noora-purple-400));
}

[data-part="wordmark"] {
  fill: var(--noora-surface-label-primary);
}

/* Navbar: hairline under a 1200px bar with 20px vertical / 16px side
   padding. The mark and page title on the left; the subscribe label with
   Noora secondary icon buttons (Atom, RSS) on the right, as on the blog. */
.status-navbar {
  display: flex;
  justify-content: center;
  border-bottom: 1px solid var(--marketing-stroke-default);
  background: var(--noora-surface-background-primary);

  & > [data-part="bar"] {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: var(--noora-spacing-6);
    box-sizing: border-box;
    padding: var(--noora-spacing-7) var(--noora-spacing-4);
    width: 100%;
    max-width: var(--marketing-page-width);
  }

  & [data-part="brand"] {
    display: flex;
    align-items: center;
    gap: var(--noora-spacing-4);
    color: inherit;
    text-decoration: none;

    & > svg {
      display: block;
      width: 26px;
      height: 26px;
    }

    & > [data-part="title"] {
      color: var(--noora-surface-label-primary);
      font: var(--noora-font-weight-regular) var(--noora-font-heading-medium);
    }
  }

  /* Figma: 32px buttons 8px apart, 16px after the label. */
  & [data-part="subscribe"] {
    display: flex;
    align-items: center;
    gap: var(--noora-spacing-4);

    & > [data-part="label"] {
      margin-right: var(--noora-spacing-4);
      color: var(--noora-surface-label-primary);
      font: var(--noora-font-weight-regular) var(--noora-font-body-medium);

      @media (max-width: 480px) {
        display: none;
      }
    }
  }
}

main {
  display: flex;
  flex: 1;
  flex-direction: column;
  align-items: stretch;
  gap: var(--noora-spacing-1);

  @media (min-width: 1024px) {
    align-items: center;
  }
}

/* Every section shares the page shell: hairline frame on the primary
   surface, 2px inset on narrow viewports, 1200px wide on desktop. */
.status-frame {
  box-sizing: border-box;
  margin: 0 var(--noora-spacing-1);
  border: 1px solid var(--marketing-stroke-default);
  background: var(--noora-surface-background-primary);

  @media (min-width: 1024px) {
    margin: 0;
    width: 100%;
    max-width: var(--marketing-page-width);
  }
}

/* Wave stage between the navbar and the hero (Figma: 1200 x 96): one canvas
   the wave script paints with the overall status's shape and ink ramp. Every
   state's ramp is declared here (not per data-wave) so the script can
   cross-fade between two of them while the status changes. Four steps of
   the Noora ramp each, deeper on the light surface and lighter on the dark
   one so both keep contrast. */
.status-stage {
  height: 96px;
  overflow: hidden;

  & > canvas {
    --wave-ink-operational-1: light-dark(var(--noora-green-700), var(--noora-green-200));
    --wave-ink-operational-2: light-dark(var(--noora-green-600), var(--noora-green-300));
    --wave-ink-operational-3: light-dark(var(--noora-green-500), var(--noora-green-400));
    --wave-ink-operational-4: light-dark(var(--noora-green-400), var(--noora-green-500));
    --wave-ink-degraded-1: light-dark(var(--noora-orange-700), var(--noora-orange-200));
    --wave-ink-degraded-2: light-dark(var(--noora-orange-600), var(--noora-orange-300));
    --wave-ink-degraded-3: light-dark(var(--noora-orange-500), var(--noora-orange-400));
    --wave-ink-degraded-4: light-dark(var(--noora-orange-400), var(--noora-orange-500));
    --wave-ink-outage-1: light-dark(var(--noora-red-700), var(--noora-red-200));
    --wave-ink-outage-2: light-dark(var(--noora-red-600), var(--noora-red-300));
    --wave-ink-outage-3: light-dark(var(--noora-red-500), var(--noora-red-400));
    --wave-ink-outage-4: light-dark(var(--noora-red-400), var(--noora-red-500));
    --wave-ink-maintenance-1: light-dark(var(--noora-blue-700), var(--noora-blue-200));
    --wave-ink-maintenance-2: light-dark(var(--noora-blue-600), var(--noora-blue-300));
    --wave-ink-maintenance-3: light-dark(var(--noora-blue-500), var(--noora-blue-400));
    --wave-ink-maintenance-4: light-dark(var(--noora-blue-400), var(--noora-blue-500));

    display: block;
    width: 100%;
    height: 100%;
    color: var(--noora-surface-label-primary);
  }
}

/* Hero: centered eyebrow, overall headline and the freshness line, 64px
   above and below with 8px sides. */
.status-hero {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: var(--noora-spacing-7);
  padding: var(--noora-spacing-13) var(--noora-spacing-4);
  text-align: center;

  @media (max-width: 720px) {
    padding: var(--noora-spacing-11) var(--noora-spacing-7);
  }

  & > [data-part="eyebrow"] {
    color: var(--noora-surface-label-secondary);
    font: var(--noora-font-weight-regular) var(--noora-font-code-large);
    text-transform: uppercase;
  }

  & > [data-part="title"] {
    margin: 0;
    color: var(--noora-surface-label-primary);
    font: var(--noora-font-weight-regular) var(--noora-font-display-small);
    letter-spacing: -0.01em;
    text-wrap: balance;
  }

  & > [data-part="meta"] {
    color: var(--noora-surface-label-secondary);
    font: var(--noora-font-weight-regular) var(--noora-font-body-large);
  }
}

/* Section: a titled header strip over a hairline-divided list. */
.status-section {
  display: flex;
  flex-direction: column;

  /* Header strip on the tertiary surface, like a table header; an optional
     link button sits at its right edge. */
  & > [data-part="header"] {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: var(--noora-spacing-6);
    border-bottom: 1px solid var(--marketing-stroke-default);
    background: var(--noora-surface-background-tertiary);
    padding: var(--noora-spacing-7) var(--noora-spacing-7);

    & > [data-part="title"] {
      margin: 0;
      color: var(--noora-surface-label-primary);
      font: var(--noora-font-weight-regular) var(--noora-font-heading-small);
    }
  }

  & > [data-part="list"] {
    display: flex;
    flex-direction: column;
    margin: 0;
    padding: 0;
    list-style: none;

    & > li:not(:first-child) {
      border-top: 1px solid var(--marketing-stroke-default);
    }
  }
}

.status-empty {
  padding: var(--noora-spacing-9) var(--noora-spacing-7);
  color: var(--noora-surface-label-secondary);
  font: var(--noora-font-weight-regular) var(--noora-font-body-medium);
}

/* Component row: name and description on the left, status badge right. */
.status-component {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: var(--noora-spacing-6);
  padding: var(--noora-spacing-6) var(--noora-spacing-7);

  & > [data-part="name"] {
    display: flex;
    flex-direction: column;
    gap: var(--noora-spacing-2);
    min-width: 0;

    & > [data-part="title"] {
      color: var(--noora-surface-label-primary);
      font: var(--noora-font-weight-regular) var(--noora-font-body-large);
    }

    & > [data-part="description"] {
      color: var(--noora-surface-label-secondary);
      font: var(--noora-font-weight-regular) var(--noora-font-body-medium);
    }
  }

  & > .noora-status-badge {
    flex: none;
  }
}

/* Incident: the day (range) as an eyebrow, the title row with severity +
   state badges, then the update timeline as a time / body grid. */
.status-incident {
  display: flex;
  flex-direction: column;
  gap: var(--noora-spacing-5);
  padding: var(--noora-spacing-7);

  /* Title with the severity and state badges at the right on desktop; on
     narrow viewports the badges drop to their own row under the title. */
  & > [data-part="header"] {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: var(--noora-spacing-4);

    @media (max-width: 720px) {
      flex-direction: column;
      align-items: flex-start;
    }

    & > [data-part="title"] {
      flex: 1 1 auto;
      margin: 0;
      min-width: 0;
      color: var(--noora-surface-label-primary);
      font: var(--noora-font-weight-medium) var(--noora-font-body-large);
    }

    & > [data-part="badges"] {
      display: flex;
      flex: none;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--noora-spacing-3);
    }
  }

  & > [data-part="meta"] {
    color: var(--noora-surface-label-secondary);
    font: var(--noora-font-weight-regular) var(--noora-font-body-medium);
    font-variant-numeric: tabular-nums;
  }

  & > [data-part="updates"] {
    display: flex;
    flex-direction: column;
    gap: var(--noora-spacing-7);
    margin: var(--noora-spacing-2) 0 0;
    padding: 0;
    list-style: none;

    & > li {
      display: grid;
      /* Wide enough for "Sep 4, 11:53 AM GMT+10:30" in the mono face. */
      grid-template-columns: 12rem minmax(0, 1fr);
      gap: var(--noora-spacing-5);
      color: var(--noora-surface-label-secondary);
      font: var(--noora-font-weight-regular) var(--noora-font-body-medium);

      @media (max-width: 720px) {
        grid-template-columns: 1fr;
        gap: var(--noora-spacing-2);
      }

      & > [data-part="time"] {
        padding-top: 0.0625rem;
        color: var(--noora-surface-label-tertiary);
        font: var(--noora-font-weight-regular) var(--noora-font-code-medium);
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
      }

      & > [data-part="body"] {
        min-width: 0;

        & > [data-part="status"] {
          color: var(--noora-surface-label-primary);
          font-weight: var(--noora-font-weight-medium);
        }

        & > [data-part="markdown"] {
          display: contents;

          & > p {
            margin: var(--noora-spacing-3) 0 0;
          }

          & > p:first-child {
            display: inline;
            margin: 0;
          }

          & > ul,
          & > ol {
            margin: var(--noora-spacing-3) 0 0;
            padding-left: var(--noora-spacing-7);
          }

          & a {
            color: inherit;
            text-decoration: underline;
            text-underline-position: from-font;
            overflow-wrap: anywhere;
          }

          & code {
            font-family: var(--noora-font-code);
          }
        }
      }
    }
  }
}

/* Footer: open at the bottom like the marketing footer. Wordmark and
   tagline on top, a hairline, then the theme switcher and the feed / API
   shortcuts. */
.status-footer {
  display: flex;
  flex-direction: column;
  gap: var(--noora-spacing-9);
  border-bottom: none;
  padding: var(--noora-spacing-11) var(--noora-spacing-7) var(--noora-spacing-9);

  & > [data-part="main"] {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    align-items: flex-start;
    gap: var(--noora-spacing-9);

    & > [data-part="brand"] {
      display: flex;
      flex-direction: column;
      gap: var(--noora-spacing-5);

      & > svg {
        display: block;
        height: 32px;
      }

      & > [data-part="tagline"] {
        margin: 0;
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-medium);
      }
    }

  }

  & > [data-part="bar"] {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    align-items: center;
    gap: var(--noora-spacing-4) var(--noora-spacing-6);
    border-top: 1px solid var(--marketing-stroke-default);
    padding-top: var(--noora-spacing-7);
    color: var(--noora-surface-label-secondary);
    font: var(--noora-font-weight-regular) var(--noora-font-body-small);

    & > [data-part="links"] {
      display: flex;
      flex-wrap: wrap;
      gap: var(--noora-spacing-5);

      & > a {
        color: inherit;
        text-decoration: none;

        &:hover {
          color: var(--noora-surface-label-primary);
        }
      }
    }
  }
}

`;

export const STYLES = NOORA_CSS + MARKETING_TOKENS_CSS + PAGE_CSS;
