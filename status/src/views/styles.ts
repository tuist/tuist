import { NOORA_CSS } from "./noora-css.js";

const PAGE_CSS = `
*, *::before, *::after { box-sizing: border-box; }

html, body { margin: 0; padding: 0; }

body {
  font: var(--noora-font-body-medium);
  color: var(--noora-surface-label-primary);
  background: var(--noora-surface-background-secondary);
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

main {
  display: flex;
  flex-direction: column;
}

.status-page {
  width: 100%;
  max-width: 56rem;
  margin: 0 auto;
  padding: var(--noora-spacing-9) var(--noora-spacing-7) var(--noora-spacing-13);
  display: flex;
  flex-direction: column;
  gap: var(--noora-spacing-8);
}

.status-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--noora-spacing-6);

  & > [data-part="brand"] {
    display: inline-flex;
    align-items: center;
    gap: var(--noora-spacing-4);
    color: var(--noora-surface-label-primary);
    text-decoration: none;
    font: var(--noora-font-weight-medium) var(--noora-font-body-large);
    letter-spacing: -0.005em;

    & > [data-part="mark"] {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 1.5rem;
      height: 1.5rem;
      color: var(--noora-purple-500);

      & > svg {
        width: 100%;
        height: 100%;
        display: block;
      }
    }
  }

  & > [data-part="meta"] {
    color: var(--noora-surface-label-tertiary);
    font: var(--noora-font-body-small);
  }
}

.status-component {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--noora-spacing-6);

  & > [data-part="name"] {
    display: flex;
    flex-direction: column;
    gap: var(--noora-spacing-1);
    min-width: 0;

    & > [data-part="title"] {
      font: var(--noora-font-weight-medium) var(--noora-font-body-medium);
      color: var(--noora-surface-label-primary);
    }

    & > [data-part="description"] {
      font: var(--noora-font-body-small);
      color: var(--noora-surface-label-tertiary);
    }
  }
}

.status-incident {
  display: flex;
  flex-direction: column;
  gap: var(--noora-spacing-4);

  & > [data-part="header"] {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--noora-spacing-3) var(--noora-spacing-4);

    & > [data-part="title"] {
      margin: 0;
      flex: 1 1 auto;
      min-width: 0;
      font: var(--noora-font-weight-medium) var(--noora-font-body-large);
      color: var(--noora-surface-label-primary);
    }
  }

  & > [data-part="meta"] {
    font: var(--noora-font-body-small);
    color: var(--noora-surface-label-tertiary);
  }

  & > [data-part="updates"] {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: var(--noora-spacing-4);

    & > li {
      display: grid;
      grid-template-columns: 8rem 1fr;
      gap: var(--noora-spacing-5);
      font: var(--noora-font-body-medium);
      color: var(--noora-surface-label-secondary);

      & > [data-part="time"] {
        color: var(--noora-surface-label-tertiary);
        font: var(--noora-font-body-small);
        font-variant-numeric: tabular-nums;
        padding-top: 0.0625rem;
      }

      & > [data-part="body"] > [data-part="status"] {
        font-weight: var(--noora-font-weight-medium);
        color: var(--noora-surface-label-primary);
        text-transform: capitalize;
      }
    }
  }
}

.status-subscribe {
  & > [data-part="text"] {
    margin: 0 0 var(--noora-spacing-5);
    font: var(--noora-font-body-medium);
    color: var(--noora-surface-label-secondary);
  }

  & > [data-part="links"] {
    display: flex;
    flex-wrap: wrap;
    gap: var(--noora-spacing-3);

    & > [data-part="link"] {
      display: inline-flex;
      align-items: center;
      gap: var(--noora-spacing-2);
      padding: var(--noora-spacing-3) var(--noora-spacing-5);
      font: var(--noora-font-weight-medium) var(--noora-font-body-small);
      color: var(--noora-surface-label-primary);
      background: var(--noora-surface-background-primary);
      text-decoration: none;
      border-radius: var(--noora-radius-3);
      box-shadow: var(--noora-border-light-default);
      transition: color 120ms ease;

      &:hover {
        color: var(--noora-purple-500);
      }

      & > svg {
        width: var(--noora-icon-size-medium);
        height: var(--noora-icon-size-medium);
      }
    }
  }
}

.status-footer {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--noora-spacing-3);
  padding-top: var(--noora-spacing-6);
  font: var(--noora-font-body-small);
  color: var(--noora-surface-label-tertiary);
  border-top: 1px solid var(--noora-content-divider-line);

  & a {
    color: inherit;
    text-decoration: underline;
    text-underline-offset: 2px;
  }
}

.status-empty {
  font: var(--noora-font-body-medium);
  color: var(--noora-surface-label-tertiary);
  text-align: center;
  padding: var(--noora-spacing-4) 0;
}

@media (max-width: 30rem) {
  .status-page {
    padding: var(--noora-spacing-7) var(--noora-spacing-5) var(--noora-spacing-11);
  }
  .status-incident > [data-part="updates"] > li {
    grid-template-columns: 1fr;
    gap: var(--noora-spacing-1);
  }
}
`;

export const STYLES = NOORA_CSS + PAGE_CSS;
