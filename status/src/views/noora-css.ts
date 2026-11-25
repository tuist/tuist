export const NOORA_CSS = String.raw`

/* tokens.css */
:root {
  color-scheme: light dark;

  /* Color palette */
  --noora-purple-50: oklch(97.5% 0.012 291.5);
  --noora-purple-100: oklch(93.7% 0.032 290.8);
  --noora-purple-200: oklch(86.8% 0.069 290);
  --noora-purple-300: oklch(77.5% 0.122 289.2);
  --noora-purple-400: oklch(66.5% 0.189 288.3);
  --noora-purple-500: oklch(54.8% 0.266 287.4);
  --noora-purple-600: oklch(48.5% 0.262 287);
  --noora-purple-700: oklch(41.5% 0.222 286.6);
  --noora-purple-800: oklch(34.5% 0.176 286.2);
  --noora-purple-900: oklch(27.5% 0.13 285.9);
  --noora-purple-950: oklch(21.5% 0.095 285.6);

  --noora-pink-50: oklch(97.5% 0.012 5);
  --noora-pink-100: oklch(93.7% 0.033 5.5);
  --noora-pink-200: oklch(86.8% 0.073 6);
  --noora-pink-300: oklch(77.5% 0.138 6.5);
  --noora-pink-400: oklch(66.5% 0.233 7);
  --noora-pink-500: oklch(54.8% 0.219 7.5);
  --noora-pink-600: oklch(48.5% 0.194 7.8);
  --noora-pink-700: oklch(41.5% 0.166 8);
  --noora-pink-800: oklch(34.5% 0.138 8);
  --noora-pink-900: oklch(27.5% 0.11 8);
  --noora-pink-950: oklch(21.5% 0.085 8);

  --noora-red-50: oklch(97.5% 0.012 25);
  --noora-red-100: oklch(93.7% 0.031 25.4);
  --noora-red-200: oklch(86.8% 0.07 25.8);
  --noora-red-300: oklch(77.5% 0.132 26.2);
  --noora-red-400: oklch(66.5% 0.221 26.6);
  --noora-red-500: oklch(54.8% 0.223 27);
  --noora-red-600: oklch(48.5% 0.197 27.2);
  --noora-red-700: oklch(41.5% 0.169 27.4);
  --noora-red-800: oklch(34.5% 0.14 27.6);
  --noora-red-900: oklch(27.5% 0.112 27.8);
  --noora-red-950: oklch(21.5% 0.087 28);

  --noora-orange-50: oklch(97.5% 0.014 58);
  --noora-orange-100: oklch(93.7% 0.038 57);
  --noora-orange-200: oklch(86.8% 0.082 55);
  --noora-orange-300: oklch(77.5% 0.148 52);
  --noora-orange-400: oklch(66.5% 0.181 48);
  --noora-orange-500: oklch(54.8% 0.159 44);
  --noora-orange-600: oklch(48.5% 0.146 42);
  --noora-orange-700: oklch(41.5% 0.127 41);
  --noora-orange-800: oklch(34.5% 0.106 41);
  --noora-orange-900: oklch(27.5% 0.084 41);
  --noora-orange-950: oklch(21.5% 0.066 41);

  --noora-yellow-50: oklch(97.5% 0.032 94);
  --noora-yellow-100: oklch(95.5% 0.063 93);
  --noora-yellow-200: oklch(93% 0.094 91.5);
  --noora-yellow-300: oklch(90.5% 0.121 90);
  --noora-yellow-400: oklch(87.5% 0.15 88);
  --noora-yellow-500: oklch(84.8% 0.173 86);
  --noora-yellow-600: oklch(72% 0.149 80);
  --noora-yellow-700: oklch(56.5% 0.119 74);
  --noora-yellow-800: oklch(44.5% 0.096 70);
  --noora-yellow-900: oklch(32.5% 0.071 68);
  --noora-yellow-950: oklch(21.5% 0.047 67);

  --noora-green-50: oklch(97.5% 0.022 152);
  --noora-green-100: oklch(93.7% 0.05 151);
  --noora-green-200: oklch(86.8% 0.1 150);
  --noora-green-300: oklch(77.5% 0.165 149);
  --noora-green-400: oklch(66.5% 0.192 148);
  --noora-green-500: oklch(54.8% 0.162 147);
  --noora-green-600: oklch(48.5% 0.142 147.5);
  --noora-green-700: oklch(41.5% 0.12 148);
  --noora-green-800: oklch(34.5% 0.097 149);
  --noora-green-900: oklch(27.5% 0.075 150);
  --noora-green-950: oklch(21.5% 0.057 151);

  --noora-azure-50: oklch(97.5% 0.013 236);
  --noora-azure-100: oklch(93.7% 0.034 236.5);
  --noora-azure-200: oklch(86.8% 0.074 237);
  --noora-azure-300: oklch(77.5% 0.13 238);
  --noora-azure-400: oklch(66.5% 0.152 240);
  --noora-azure-500: oklch(54.8% 0.13 242);
  --noora-azure-600: oklch(48.5% 0.118 243.5);
  --noora-azure-700: oklch(41.5% 0.104 245);
  --noora-azure-800: oklch(34.5% 0.088 246);
  --noora-azure-900: oklch(27.5% 0.072 247);
  --noora-azure-950: oklch(21.5% 0.057 248);

  --noora-blue-50: oklch(97.5% 0.011 256);
  --noora-blue-100: oklch(93.7% 0.03 256.5);
  --noora-blue-200: oklch(86.8% 0.065 257);
  --noora-blue-300: oklch(77.5% 0.115 258);
  --noora-blue-400: oklch(66.5% 0.178 259);
  --noora-blue-500: oklch(54.8% 0.223 260);
  --noora-blue-600: oklch(48.5% 0.209 261);
  --noora-blue-700: oklch(41.5% 0.191 262);
  --noora-blue-800: oklch(34.5% 0.155 263);
  --noora-blue-900: oklch(27.5% 0.118 263.5);
  --noora-blue-950: oklch(21.5% 0.088 264);

  --noora-neutral-light-50: oklch(99.4% 0 0);
  --noora-neutral-light-100: oklch(97.6% 0 0);
  --noora-neutral-light-200: oklch(95.5% 0.002 247.84);
  --noora-neutral-light-300: oklch(93% 0.003 247.86);
  --noora-neutral-light-400: oklch(89% 0.003 247.863);
  --noora-neutral-light-500: oklch(84.4% 0.005 247.888);
  --noora-neutral-light-600: oklch(78.4% 0.005 247.894);
  --noora-neutral-light-700: oklch(72% 0.006 247.902);
  --noora-neutral-light-800: oklch(64.5% 0.006 247.914);
  --noora-neutral-light-900: oklch(55.7% 0.008 247.968);
  --noora-neutral-light-1000: oklch(45.1% 0.006 247.965);
  --noora-neutral-light-1100: oklch(32% 0.005 247.968);
  --noora-neutral-light-1200: oklch(21.7% 0.002 247.941);

  --noora-neutral-dark-50: oklch(97.2% 0 0);
  --noora-neutral-dark-100: oklch(91.9% 0 0);
  --noora-neutral-dark-200: oklch(86.3% 0 0);
  --noora-neutral-dark-300: oklch(72% 0 0);
  --noora-neutral-dark-400: oklch(64.9% 0 0);
  --noora-neutral-dark-500: oklch(54.9% 0 0);
  --noora-neutral-dark-600: oklch(45.9% 0 0);
  --noora-neutral-dark-700: oklch(39.6% 0 0);
  --noora-neutral-dark-800: oklch(34.8% 0 0);
  --noora-neutral-dark-900: oklch(30.2% 0 0);
  --noora-neutral-dark-1000: oklch(25.4% 0 0);
  --noora-neutral-dark-1100: oklch(20.9% 0 0);
  --noora-neutral-dark-1200: oklch(16.2% 0 0);

  --noora-neutral-gray-50: oklch(30.2% 0 0 / 0.5);
  --noora-neutral-gray-24: oklch(32% 0.005 247.968 / 0.24);
  --noora-neutral-gray-16: oklch(34.8% 0 0 / 0.16);

  --noora-alpha-red-24: oklch(54.8% 0.223 27 / 0.24);
  --noora-alpha-red-32: oklch(54.8% 0.223 27 / 0.32);
  --noora-alpha-orange-24: oklch(66.5% 0.181 48 / 0.24);
  --noora-alpha-yellow-24: oklch(84.8% 0.173 86 / 0.24);
  --noora-alpha-green-24: oklch(54.8% 0.162 147 / 0.24);
  --noora-alpha-azure-24: oklch(54.8% 0.13 242 / 0.24);
  --noora-alpha-blue-24: oklch(54.8% 0.223 260 / 0.24);
  --noora-alpha-purple-24: oklch(54.8% 0.266 287.4 / 0.24);
  --noora-alpha-purple-32: oklch(54.8% 0.266 287.4 / 0.32);
  --noora-alpha-pink-24: oklch(54.8% 0.219 7.5 / 0.24);
  --noora-alpha-black-80: oklch(0% 0 0 / 0.8);

  /* Semantic colors */
  /* Background */
  --noora-surface-background-primary: light-dark(
    var(--noora-neutral-light-50),
    var(--noora-neutral-dark-1200)
  );
  --noora-surface-background-secondary: light-dark(
    var(--noora-neutral-light-200),
    var(--noora-neutral-dark-1000)
  );
  --noora-surface-background-tertiary: light-dark(
    var(--noora-neutral-light-100),
    var(--noora-neutral-dark-1100)
  );
  --noora-surface-background-destructive: light-dark(
    var(--noora-red-100),
    var(--noora-alpha-red-24)
  );
  --noora-surface-overlay: light-dark(
    var(--noora-neutral-gray-24),
    var(--noora-neutral-gray-16)
  );

  /* Label */
  --noora-surface-label-primary: light-dark(
    var(--noora-neutral-light-1200),
    var(--noora-neutral-dark-50)
  );
  --noora-surface-label-secondary: light-dark(
    var(--noora-neutral-light-1000),
    var(--noora-neutral-dark-200)
  );
  --noora-surface-label-tertiary: light-dark(
    var(--noora-neutral-light-700),
    var(--noora-neutral-dark-500)
  );
  --noora-surface-label-destructive: light-dark(
    var(--noora-red-500),
    var(--noora-red-300)
  );
  --noora-surface-label-success: light-dark(
    var(--noora-green-500),
    var(--noora-green-400)
  );
  --noora-surface-label-brand: light-dark(
    var(--noora-purple-500),
    var(--noora-purple-400)
  );
  --noora-surface-label-disabled: light-dark(
    var(--noora-neutral-light-600),
    var(--noora-neutral-dark-300)
  );

  /* Focus ring: one focus treatment for every focusable element. A 1.5px
     gap in the surface color, then a 1.5px purple ring. As box-shadow layers
     (--noora-focus-ring), or as an outline (width, color, offset) where a
     shadow doesn't fit. Component focus tokens put it over their own resting
     border. */
  --noora-focus-ring-color: light-dark(
    var(--noora-purple-500),
    var(--noora-purple-400)
  );
  --noora-focus-ring-gap: light-dark(
    var(--noora-neutral-light-50),
    var(--noora-neutral-dark-1200)
  );
  --noora-focus-ring-width: 1.5px;
  --noora-focus-ring-offset: 1.5px;
  --noora-focus-ring:
    0px 0px 0px 1.5px var(--noora-focus-ring-gap),
    0px 0px 0px 3px var(--noora-focus-ring-color);

  /* Button */
  /* Disabled is one look for every button: primary, secondary, destructive,
     and neutral. */
  --noora-button-disabled-background: light-dark(
    var(--noora-neutral-light-100),
    var(--noora-neutral-dark-1000)
  );
  --noora-button-disabled-label: light-dark(
    var(--noora-neutral-light-600),
    var(--noora-neutral-dark-600)
  );
  --noora-button-primary-background: var(--noora-purple-500);
  --noora-button-primary-label: var(--noora-neutral-light-50);
  --noora-button-secondary-background: light-dark(
    var(--noora-neutral-light-50),
    var(--noora-neutral-dark-1100)
  );
  --noora-button-secondary-label: light-dark(
    var(--noora-neutral-light-1200),
    var(--noora-neutral-light-50)
  );
  --noora-button-destructive-background: var(--noora-red-500);
  --noora-button-destructive-label: var(--noora-neutral-light-50);

  /* Ghost button: no fill at rest, a tint on hover, a stronger one while
     selected (pressed), per variant. Disabled uses the shared button
     disabled colors. */
  --noora-button-ghost-primary-hover: light-dark(
    var(--noora-purple-50),
    var(--noora-alpha-purple-24)
  );
  --noora-button-ghost-primary-selected: light-dark(
    var(--noora-purple-100),
    var(--noora-alpha-purple-32)
  );
  --noora-button-ghost-primary-label: light-dark(
    var(--noora-purple-500),
    var(--noora-purple-400)
  );
  --noora-button-ghost-secondary-hover: light-dark(
    var(--noora-neutral-light-200),
    var(--noora-neutral-dark-1000)
  );
  --noora-button-ghost-secondary-selected: light-dark(
    var(--noora-neutral-light-300),
    var(--noora-neutral-dark-900)
  );
  --noora-button-ghost-secondary-label: light-dark(
    var(--noora-neutral-light-1200),
    var(--noora-neutral-light-50)
  );
  --noora-button-ghost-destructive-hover: light-dark(
    var(--noora-red-50),
    var(--noora-alpha-red-24)
  );
  --noora-button-ghost-destructive-selected: light-dark(
    var(--noora-red-100),
    var(--noora-alpha-red-32)
  );
  --noora-button-ghost-destructive-label: light-dark(
    var(--noora-red-500),
    var(--noora-red-400)
  );
  /* The outline variant: the secondary colors with this 1px border. */
  --noora-button-ghost-outline-border: light-dark(
    oklch(from var(--noora-neutral-light-1100) l c h / 0.15),
    oklch(from var(--noora-neutral-dark-500) l c h / 0.45)
  );

  /* Button Dropdown Trigger */
  --noora-button-dropdown-trigger-background:
    linear-gradient(
      180deg,
      oklch(78.4% 0.005 247.894 / 0) 0%,
      light-dark(
          oklch(78.4% 0.005 247.894 / 0.06),
          oklch(78.4% 0.005 247.894 / 0.13)
        )
        100%
    ),
    var(--noora-button-secondary-background);
  --noora-button-dropdown-trigger-background-hover:
    linear-gradient(
      180deg,
      light-dark(
          oklch(78.4% 0.005 247.894 / 0.03),
          oklch(78.4% 0.005 247.894 / 0)
        )
        0%,
      light-dark(
          oklch(78.4% 0.005 247.894 / 0.13),
          oklch(78.4% 0.005 247.894 / 0.255)
        )
        100%
    ),
    var(--noora-button-secondary-background);
  --noora-button-dropdown-trigger-background-disabled:
    linear-gradient(
      180deg,
      oklch(78.4% 0.005 247.894 / 0) 0%,
      light-dark(
          oklch(78.4% 0.005 247.894 / 0.06),
          oklch(78.4% 0.005 247.894 / 0.13)
        )
        100%
    ),
    var(--noora-button-disabled-background);

  --noora-button-background-primary:
    linear-gradient(
      180deg,
      oklch(100% 0 0 / 0.06) 0%,
      oklch(100% 0 0 / 0) 100%
    ),
    var(--noora-button-primary-background);
  --noora-button-background-primary-hover:
    linear-gradient(
      180deg,
      oklch(100% 0 0 / 0.18) 0%,
      oklch(100% 0 0 / 0) 100%
    ),
    var(--noora-button-primary-background);
  --noora-button-background-primary-active: var(
    --noora-button-primary-background
  );
  --noora-button-border-primary:
    0px 1px 0px 0px oklch(100% 0 0 / 0.2) inset,
    0px 1px 1px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.05), oklch(16.2% 0 0 / 0.2)),
    0px 0px 0px 1px oklch(from var(--noora-purple-600) l c h / 0.9),
    0px 1px 3px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.16), oklch(0% 0 0 / 0.4));
  --noora-button-border-primary-hover:
    0px 1px 0px oklch(100% 0 0 / 0.1) inset,
    0px 1px 1px oklch(32% 0.005 247.968 / 0.12),
    0px 0px 0px 1px oklch(from var(--noora-purple-600) l c h / 0.9),
    0px 2px 3px oklch(32% 0.005 247.968 / 0.16);
  /* The focus ring of every button and button-like control (buttons,
     dropdown and button dropdown triggers, the date picker, table sort
     buttons) over the primary button's shading. */
  --noora-button-border-focus:
    var(--noora-focus-ring), 0px 1px 0px 0px oklch(100% 0 0 / 0.2) inset,
    0px 1px 1px 0px oklch(32% 0.005 247.968 / 0.12),
    0px 0px 0px 1px oklch(from var(--noora-purple-600) l c h / 0.9),
    0px 2px 3px 0px oklch(32% 0.005 247.968 / 0.16);
  --noora-button-border-primary-active:
    0px 0px 0px 1px oklch(from var(--noora-purple-600) l c h / 0.9),
    0px 1px 4px 0px light-dark(oklch(0% 0 0 / 0.3), oklch(0% 0 0 / 0.4)) inset;

  --noora-button-background-secondary:
    linear-gradient(
      180deg,
      light-dark(oklch(78.4% 0.005 247.894 / 0), oklch(100% 0 0 / 0.02)),
      light-dark(oklch(78.4% 0.005 247.894 / 0.08), oklch(100% 0 0 / 0))
    ),
    var(--noora-button-secondary-background);
  --noora-button-background-secondary-hover:
    linear-gradient(
      180deg,
      light-dark(oklch(78.4% 0.005 247.894 / 0), oklch(100% 0 0 / 0.08)),
      light-dark(oklch(78.4% 0.005 247.894 / 0.16), oklch(100% 0 0 / 0))
    ),
    var(--noora-button-secondary-background);
  --noora-button-background-disabled:
    linear-gradient(
      180deg,
      light-dark(oklch(78.4% 0.005 247.894 / 0), oklch(100% 0 0 / 0.06)),
      light-dark(oklch(78.4% 0.005 247.894 / 0.08), oklch(100% 0 0 / 0))
    ),
    var(--noora-button-disabled-background);
  --noora-button-border-secondary:
    0px 1px 0px 0px light-dark(oklch(100% 0 0 / 0.9), oklch(100% 0 0 / 0.16))
      inset,
    0px 1px 1px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.05), oklch(16.2% 0 0 / 0.1)),
    0px 0px 0px 1px
      light-dark(oklch(32% 0.005 247.968 / 0.08), oklch(34.8% 0 0 / 0.9)),
    0px 2px 3px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.06), oklch(0% 0 0 / 0.5));
  --noora-button-border-disabled:
    0px 1px 0px 0px light-dark(oklch(100% 0 0 / 0.7), oklch(100% 0 0 / 0.16))
      inset,
    0px 1px 1px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.05), oklch(16.2% 0 0 / 0.1)),
    0px 0px 0px 1px
      light-dark(oklch(32% 0.005 247.968 / 0.05), oklch(34.8% 0 0 / 0.9)),
    0px 2px 3px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.06), oklch(0% 0 0 / 0.5));
  --noora-button-background-secondary-active:
    linear-gradient(
      180deg,
      light-dark(oklch(78.4% 0.005 247.894 / 0.03), oklch(100% 0 0 / 0.03)),
      light-dark(oklch(78.4% 0.005 247.894 / 0.13), oklch(100% 0 0 / 0))
    ),
    var(--noora-button-secondary-background);
  --noora-button-border-secondary-active:
    0px 0px 0px 1px
      light-dark(oklch(32% 0.005 247.968 / 0.08), oklch(34.8% 0 0 / 0.9)),
    0px 1px 2px 0px light-dark(oklch(0% 0 0 / 0.05), oklch(0% 0 0 / 0.4)) inset;

  --noora-button-background-destructive:
    linear-gradient(180deg, oklch(100% 0 0 / 0.06), oklch(100% 0 0 / 0)),
    var(--noora-button-destructive-background);
  --noora-button-border-destructive:
    0px 1px 0px 0px oklch(100% 0 0 / 0.2) inset,
    0px 1px 1px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.12), oklch(16.2% 0 0 / 0.2)),
    0px 0px 0px 1px oklch(from var(--noora-red-600) l c h / 0.8),
    0px 2px 3px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.16), oklch(0% 0 0 / 0.4));
  --noora-button-background-destructive-hover:
    linear-gradient(180deg, oklch(100% 0 0 / 0.24), oklch(100% 0 0 / 0)),
    var(--noora-button-destructive-background);
  --noora-button-border-destructive-hover:
    0px 1px 0px 0px oklch(100% 0 0 / 0.1) inset,
    0px 1px 1px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.12), oklch(16.2% 0 0 / 0.2)),
    0px 0px 0px 1px oklch(from var(--noora-red-600) l c h / 0.8),
    0px 2px 3px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.16), oklch(0% 0 0 / 0.4));
  --noora-button-border-destructive-active:
    0px 0px 0px 1px oklch(from var(--noora-red-600) l c h / 0.8),
    0px 1px 4px 0px light-dark(oklch(0% 0 0 / 0.3), oklch(0% 0 0 / 0.4)) inset;

  /* Tooltip */
  --noora-tooltip-background: light-dark(
    var(--noora-neutral-light-1200),
    var(--noora-neutral-dark-50)
  );
  --noora-tooltip-border:
    box-shadow: 0 4px 8px 0
      light-dark(oklch(32% 0.005 247.968 / 0.08), oklch(0% 0 0 / 0.16)) 0 2px
      4px 0 light-dark(oklch(32% 0.005 247.968 / 0.04), oklch(0% 0 0 / 0.24)),
    0 1px 2px 0 light-dark(oklch(0% 0 0 / 0.25), oklch(0% 0 0 / 0.65));
  --noora-tooltip-label-primary: light-dark(
    var(--noora-neutral-light-50),
    var(--noora-neutral-dark-1200)
  );
  --noora-tooltip-label-secondary: light-dark(
    var(--noora-neutral-light-200),
    var(--noora-neutral-dark-1000)
  );

  /* Badge */
  --noora-badge-fill-primary-label: light-dark(
    var(--noora-neutral-light-50),
    var(--noora-neutral-dark-50)
  );
  --noora-badge-fill-secondary-label: light-dark(
    var(--noora-neutral-light-1200),
    var(--noora-neutral-dark-1200)
  );
  --noora-badge-fill-neutral: light-dark(
    var(--noora-neutral-light-900),
    var(--noora-neutral-dark-700)
  );
  --noora-badge-fill-destructive: light-dark(
    var(--noora-red-500),
    var(--noora-red-500)
  );
  --noora-badge-fill-warning: light-dark(
    var(--noora-orange-500),
    var(--noora-orange-500)
  );
  --noora-badge-fill-attention: light-dark(
    var(--noora-yellow-500),
    var(--noora-yellow-500)
  );
  --noora-badge-fill-success: light-dark(
    var(--noora-green-600),
    var(--noora-green-600)
  );
  --noora-badge-fill-information: light-dark(
    var(--noora-azure-500),
    var(--noora-azure-600)
  );
  --noora-badge-fill-focus: light-dark(
    var(--noora-blue-500),
    var(--noora-blue-600)
  );
  --noora-badge-fill-primary: light-dark(
    var(--noora-purple-500),
    var(--noora-purple-600)
  );
  --noora-badge-fill-secondary: light-dark(
    var(--noora-pink-500),
    var(--noora-pink-600)
  );

  /* Light-fill backgrounds are tints that blend with the surface under the
     badge (see --noora-badge-light-fill-blend-mode): multiplied in light
     mode and screened in dark mode, so a badge stays a step darker or
     lighter than whatever it sits on. Each tint keeps a scale step's hue at
     a fixed lightness, with half its chroma; neutral blends its scale steps
     as they are. */
  --noora-badge-light-fill-blend-mode: multiply;
  --noora-badge-light-fill-neutral-background: light-dark(
    var(--noora-neutral-light-200),
    var(--noora-neutral-dark-1100)
  );
  --noora-badge-light-fill-neutral-label: light-dark(
    var(--noora-neutral-light-1100),
    var(--noora-neutral-dark-50)
  );
  --noora-badge-light-fill-destructive-background: light-dark(
    oklch(from var(--noora-red-800) 0.95 calc(c * 0.5) h),
    oklch(from var(--noora-red-400) 0.24 calc(c * 0.5) h)
  );
  --noora-badge-light-fill-destructive-label: light-dark(
    var(--noora-red-700),
    var(--noora-red-300)
  );
  --noora-badge-light-fill-warning-background: light-dark(
    oklch(from var(--noora-orange-800) 0.95 calc(c * 0.5) h),
    oklch(from var(--noora-orange-400) 0.24 calc(c * 0.5) h)
  );
  --noora-badge-light-fill-warning-label: light-dark(
    var(--noora-orange-700),
    var(--noora-orange-300)
  );
  --noora-badge-light-fill-attention-background: light-dark(
    oklch(from var(--noora-yellow-400) 0.95 calc(c * 0.5) h),
    oklch(from var(--noora-yellow-500) 0.24 calc(c * 0.5) h)
  );
  --noora-badge-light-fill-attention-label: light-dark(
    var(--noora-yellow-800),
    var(--noora-yellow-400)
  );
  --noora-badge-light-fill-success-background: light-dark(
    oklch(from var(--noora-green-500) 0.95 calc(c * 0.5) h),
    oklch(from var(--noora-green-600) 0.24 calc(c * 0.5) h)
  );
  --noora-badge-light-fill-success-label: light-dark(
    var(--noora-green-700),
    var(--noora-green-300)
  );
  --noora-badge-light-fill-information-background: light-dark(
    oklch(from var(--noora-azure-800) 0.95 calc(c * 0.5) h),
    oklch(from var(--noora-azure-500) 0.24 calc(c * 0.5) h)
  );
  --noora-badge-light-fill-information-label: light-dark(
    var(--noora-azure-700),
    var(--noora-azure-300)
  );
  --noora-badge-light-fill-focus-background: light-dark(
    oklch(from var(--noora-blue-950) 0.95 calc(c * 0.5) h),
    oklch(from var(--noora-blue-600) 0.24 calc(c * 0.5) h)
  );
  --noora-badge-light-fill-focus-label: light-dark(
    var(--noora-blue-700),
    var(--noora-blue-300)
  );
  --noora-badge-light-fill-primary-background: light-dark(
    oklch(from var(--noora-purple-500) 0.95 calc(c * 0.5) h),
    oklch(from var(--noora-purple-500) 0.24 calc(c * 0.5) h)
  );
  --noora-badge-light-fill-primary-label: light-dark(
    var(--noora-purple-700),
    var(--noora-purple-300)
  );
  --noora-badge-light-fill-secondary-background: light-dark(
    oklch(from var(--noora-pink-900) 0.95 calc(c * 0.5) h),
    oklch(from var(--noora-pink-500) 0.24 calc(c * 0.5) h)
  );
  --noora-badge-light-fill-secondary-label: light-dark(
    var(--noora-pink-700),
    var(--noora-pink-300)
  );

  --noora-badge-disabled-background: light-dark(
    var(--noora-neutral-light-200),
    var(--noora-neutral-dark-1000)
  );
  --noora-badge-disabled-label: light-dark(
    var(--noora-neutral-light-600),
    var(--noora-neutral-dark-500)
  );

  --noora-badge-status-success: light-dark(
    var(--noora-green-500),
    var(--noora-green-400)
  );
  --noora-badge-status-warning: var(--noora-orange-400);
  --noora-badge-status-error: light-dark(
    var(--noora-red-500),
    var(--noora-red-400)
  );
  --noora-badge-status-attention: light-dark(
    var(--noora-yellow-600),
    var(--noora-yellow-400)
  );
  --noora-badge-status-in-progress: light-dark(
    var(--noora-neutral-light-900),
    var(--noora-neutral-dark-200)
  );

  /* Borders */
  --noora-surface-border-primary: light-dark(
    var(--noora-neutral-light-500),
    var(--noora-neutral-dark-800)
  );
  /* Table */
  --noora-surface-table-header: light-dark(
    var(--noora-neutral-light-200),
    var(--noora-neutral-dark-1000)
  );

  /* Choice Selector */
  --noora-choice-selector-uncheck-background:
    linear-gradient(
      180deg,
      oklch(78.4% 0.005 247.894 / 0) 0%,
      oklch(78.4% 0.005 247.894 / 0.06) 100%
    ),
    var(--noora-neutral-light-50);
  --noora-choice-selector-uncheck-background-hover:
    linear-gradient(
      180deg,
      oklch(78.4% 0.005 247.894 / 0.05) 0%,
      oklch(78.4% 0.005 247.894 / 0.19) 100%
    ),
    var(--noora-neutral-light-50);
  --noora-choice-selector-check-background:
    linear-gradient(
      180deg,
      oklch(100% 0 0 / 0.16) 0%,
      oklch(100% 0 0 / 0) 100%
    ),
    var(--noora-purple-500);
  --noora-choice-selector-check-background-hover:
    linear-gradient(
      180deg,
      oklch(100% 0 0 / 0.12) 0%,
      oklch(100% 0 0 / 0) 100%
    ),
    var(--noora-purple-500);
  --noora-choice-selector-disabled-background: light-dark(
    var(--noora-neutral-light-400),
    var(--noora-neutral-dark-900)
  );
  --noora-choice-selector-label: oklch(99.4% 0 0);
  --noora-choice-selector-switch-off-background: var(--noora-neutral-light-400);
  --noora-choice-selector-switch-off-background-hover: var(
    --noora-neutral-light-500
  );
  --noora-choice-selector-check-border:
    0px 1px 0px 0px oklch(100% 0 0 / 0.2) inset,
    0px 1px 1px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.12), oklch(16.2% 0 0 / 0.2)),
    0px 0px 0px 1px oklch(from var(--noora-purple-700) l c h / 0.9),
    0px 1px 3px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.16), oklch(0% 0 0 / 0.4));

  /* Divider */
  --noora-content-divider-line: light-dark(
    var(--noora-neutral-light-400),
    var(--noora-neutral-dark-900)
  );

  /* Charts */
  --noora-chart-primary: light-dark(
    var(--noora-purple-500),
    var(--noora-purple-400)
  );
  --noora-chart-secondary: light-dark(
    var(--noora-blue-500),
    var(--noora-blue-400)
  );
  --noora-chart-tertiary: light-dark(
    var(--noora-green-500),
    var(--noora-green-400)
  );
  --noora-chart-quaternary: light-dark(
    var(--noora-azure-500),
    var(--noora-azure-400)
  );
  --noora-chart-destructive: light-dark(
    var(--noora-red-400),
    var(--noora-red-300)
  );
  --noora-chart-flaky: light-dark(
    var(--noora-yellow-600),
    var(--noora-yellow-400)
  );
  --noora-chart-p99: light-dark(var(--noora-green-500), var(--noora-green-400));
  --noora-chart-p90: light-dark(var(--noora-pink-500), var(--noora-pink-400));
  --noora-chart-p50: light-dark(
    var(--noora-orange-400),
    var(--noora-orange-300)
  );
  --noora-chart-legend-primary: light-dark(
    var(--noora-purple-500),
    var(--noora-purple-400)
  );
  --noora-chart-legend-primary-translucent: light-dark(
    var(--noora-purple-200),
    var(--noora-purple-700)
  );
  --noora-chart-legend-secondary: light-dark(
    var(--noora-blue-500),
    var(--noora-blue-400)
  );
  --noora-chart-lines: light-dark(
    var(--noora-neutral-light-300),
    var(--noora-neutral-gray-16)
  );
  --noora-sunburst-binaries: var(--noora-purple-500);
  --noora-sunburst-localizations: var(--noora-orange-400);
  --noora-sunburst-fonts: var(--noora-yellow-500);
  --noora-sunburst-assets: var(--noora-green-500);
  --noora-sunburst-videos: var(--noora-azure-500);
  --noora-sunburst-duplicates: var(--noora-red-500);
  --noora-sunburst-unknown: var(--noora-pink-500);
  --noora-sunburst-directory: var(--noora-neutral-light-500);
  --noora-sunburst-files: var(--noora-azure-500);

  /* Icons */
  --noora-icon-destructive-background: light-dark(
    var(--noora-red-50),
    var(--noora-alpha-red-24)
  );
  --noora-icon-destructive-label: light-dark(
    var(--noora-red-600),
    var(--noora-red-500)
  );
  --noora-icon-warning-background: light-dark(
    var(--noora-orange-50),
    var(--noora-alpha-orange-24)
  );
  --noora-icon-warning-label: light-dark(
    var(--noora-orange-500),
    var(--noora-orange-400)
  );
  --noora-icon-success-background: light-dark(
    var(--noora-green-50),
    var(--noora-alpha-green-24)
  );
  --noora-icon-success-label: light-dark(
    var(--noora-green-700),
    var(--noora-green-400)
  );
  --noora-icon-info-background: light-dark(
    var(--noora-azure-50),
    var(--noora-alpha-azure-24)
  );
  --noora-icon-info-label: light-dark(
    var(--noora-azure-700),
    var(--noora-azure-400)
  );
  --noora-icon-primary-label: light-dark(
    var(--noora-purple-500),
    var(--noora-purple-400)
  );
  --noora-icon-primary-background: light-dark(
    var(--noora-purple-50),
    oklch(from var(--noora-purple-500) l c h / 0.24)
  );
  --noora-icon-neutral-label: light-dark(
    var(--noora-neutral-light-1000),
    var(--noora-neutral-dark-300)
  );
  --noora-icon-neutral-background: light-dark(
    var(--noora-neutral-light-300),
    var(--noora-neutral-gray-16)
  );

  /* Spacing */
  --noora-spacing-0: 0rem;
  --noora-spacing-1: 0.125rem;
  --noora-spacing-2: 0.25rem;
  --noora-spacing-3: 0.375rem;
  --noora-spacing-4: 0.5rem;
  --noora-spacing-5: 0.75rem;
  --noora-spacing-6: 1rem;
  --noora-spacing-7: 1.25rem;
  --noora-spacing-8: 1.5rem;
  --noora-spacing-9: 2rem;
  --noora-spacing-10: 2.5rem;
  --noora-spacing-11: 3rem;
  --noora-spacing-12: 3.5rem;
  --noora-spacing-13: 4rem;
  --noora-spacing-14: 4.5rem;
  --noora-spacing-15: 5rem;
  --noora-spacing-16: 6rem;
  --noora-spacing-17: 7rem;

  /* Z-index */
  --noora-z-index-0: auto;
  --noora-z-index-1: 100;
  --noora-z-index-2: 400;
  --noora-z-index-3: 510;
  --noora-z-index-4: 512;
  --noora-z-index-5: 513;
  --noora-z-index-6: 514;
  --noora-z-index-7: 515;
  --noora-z-index-8: 516;
  --noora-z-index-9: 517;
  --noora-z-index-10: 518;
  --noora-z-index-11: 519;
  --noora-z-index-12: 520;

  /* Borders */
  --noora-surface-border-primary: light-dark(
    var(--noora-neutral-light-500),
    var(--noora-neutral-dark-800)
  );

  --noora-border-small-default:
    0px 1px 1px 0px oklch(16.2% 0 0 / 0.05),
    0px 0px 0px 1px oklch(32% 0.005 247.968 / 0.08),
    0px 1px 1px 0px oklch(32% 0.005 247.968 / 0.1);
  --noora-border-small-focus:
    0px 1px 1px 0px oklch(from var(--noora-neutral-dark-1200) l c h / 0.05),
    0px 0px 0px 1px oklch(from var(--noora-neutral-light-1100) l c h / 0.08),
    0px 0px 0px 1px var(--noora-neutral-light-1000),
    0px 1px 3px 0px oklch(from var(--noora-neutral-light-1100) l c h / 0.1),
    0px 0px 0px 4px oklch(from var(--noora-neutral-light-1100) l c h / 0.12);
  --noora-border-small-error:
    0px 1px 1px 0px oklch(16.2% 0 0 / 0.05),
    0px 0px 0px 1px var(--noora-red-500),
    0px 1px 3px 0px oklch(32% 0.005 247.968 / 0.1);
  --noora-border-small-error-focus:
    0px 0px 0px 1.5px var(--noora-focus-ring-gap),
    0px 0px 0px 3px light-dark(var(--noora-red-500), var(--noora-red-300)),
    var(--noora-border-small-error);
  --noora-border-small-warning:
    0px 1px 1px 0px oklch(from var(--noora-neutral-dark-1200) l c h / 0.05),
    0px 0px 0px 1px var(--noora-orange-500),
    0px 1px 3px 0px oklch(from var(--noora-neutral-light-1100) l c h / 0.1);
  --noora-border-small-warning-focus:
    0px 0px 0px 1.5px var(--noora-focus-ring-gap),
    0px 0px 0px 3px light-dark(var(--noora-orange-400), var(--noora-orange-300)),
    var(--noora-border-small-warning);

  --noora-border-medium:
    0px 8px 6px 0px oklch(from var(--noora-neutral-dark-1200) l c h / 0.02),
    0px 0px 0px 1px oklch(from var(--noora-neutral-light-1100) l c h / 0.08),
    0px 2px 4px 0px oklch(from var(--noora-neutral-light-1100) l c h / 0.04);
  --noora-border-section: 0 0 0 1px oklch(32% 0.005 247.968 / 0.06);
  --noora-border-large:
    0px 4px 8px 0px oklch(from var(--noora-neutral-light-1100) l c h / 0.08),
    0px 0px 0px 1px oklch(from var(--noora-neutral-light-1100) l c h / 0.08),
    0px 2px 4px 0px oklch(from var(--noora-neutral-light-1100) l c h / 0.04);
  --noora-border-xlarge:
    0px 4px 8px 0px oklch(from var(--noora-neutral-light-1100) l c h / 0.08),
    0px 0px 0px 1px oklch(from var(--noora-neutral-light-1100) l c h / 0.08),
    0px 8px 12px 0px oklch(from var(--noora-neutral-light-1100) l c h / 0.06),
    0px 2px 4px 0px oklch(from var(--noora-neutral-light-1100) l c h / 0.04);

  /* Radius */
  --noora-radius-0: 0rem;
  --noora-radius-1: 0.125rem;
  --noora-radius-2: 0.25rem;
  --noora-radius-3: 0.375rem;
  --noora-radius-4: 0.5rem;
  --noora-radius-5: 0.625rem;
  --noora-radius-6: 0.75rem;
  --noora-radius-7: 0.875rem;
  --noora-radius-8: 1rem;
  --noora-radius-99: 1000px;

  /* Icon */
  --noora-icon-size-small: 0.75rem;
  --noora-icon-size-medium: 1rem;
  --noora-icon-size-large: 1.25rem;

  /* Typography */
  --noora-font-heading:
    "Inter Variable", "Noto Sans Georgian", "Noto Sans Arabic", sans-serif;
  --noora-font-body:
    "Inter Variable", "Noto Sans Georgian", "Noto Sans Arabic", sans-serif;
  --noora-font-code: "Geist Mono", monospace;

  --noora-font-weight-regular: 400;
  --noora-font-weight-medium: 500;
  --noora-font-weight-semibold: 600;
  --noora-font-weight-bold: 700;

  --noora-font-display-xlarge: 2.5rem/3rem var(--noora-font-heading);
  --noora-font-display-large: 2.375rem/2.875rem var(--noora-font-heading);
  --noora-font-display-medium: 2.25rem/2.625rem var(--noora-font-heading);
  --noora-font-display-small: 2.125rem/2.5rem var(--noora-font-heading);
  --noora-font-heading-2xlarge: 2rem/2.375rem var(--noora-font-heading);
  --noora-font-heading-xlarge: 1.5rem/2rem var(--noora-font-heading);
  --noora-font-heading-large: 1.25rem/1.625rem var(--noora-font-heading);
  --noora-font-heading-medium: 1.125rem/1.5rem var(--noora-font-heading);
  --noora-font-heading-small: 1rem/1.375rem var(--noora-font-heading);
  --noora-font-body-large: 1rem/1.5rem var(--noora-font-body);
  --noora-font-body-medium: 0.875rem/1.25rem var(--noora-font-body);
  --noora-font-body-small: 0.75rem/1rem var(--noora-font-body);
  --noora-font-body-xsmall: 0.625rem/0.75rem var(--noora-font-body);
  --noora-font-code-large: 0.875rem/1.25rem var(--noora-font-code);
  --noora-font-code-medium: 0.75rem/1rem var(--noora-font-code);
  --noora-font-code-small: 0.625rem/0.75rem var(--noora-font-code);

  &[data-theme="dark"] {
    --noora-button-border-primary-hover:
      0px 1px 0px 0px oklch(100% 0 0 / 0.1) inset,
      0px 1px 1px 0px oklch(16.2% 0 0 / 0.2),
      0px 0px 0px 1px oklch(from var(--noora-purple-600) l c h / 0.9),
      0px 2px 3px 0px oklch(0% 0 0 / 0.4);
    --noora-button-border-secondary-hover:
      0px 1px 0px 0px oklch(100% 0 0 / 0.24) inset,
      0px 1px 1px 0px oklch(16.2% 0 0 / 0.1),
      0px 0px 0px 1px oklch(34.8% 0 0 / 0.9),
      0px 2px 3px 0px oklch(0% 0 0 / 0.5);
  }

  &[data-theme="dark"] {
    --noora-choice-selector-uncheck-background:
      linear-gradient(
        180deg,
        oklch(100% 0 0 / 0.05) 0%,
        oklch(100% 0 0 / 0) 100%
      ),
      var(--noora-neutral-dark-1100);

    --noora-choice-selector-uncheck-background-hover:
      linear-gradient(
        180deg,
        oklch(100% 0 0 / 0.03) 0%,
        oklch(100% 0 0 / 0) 100%
      ),
      var(--noora-neutral-dark-1100);

    --noora-choice-selector-switch-off-background: var(
      --noora-neutral-dark-800
    );
    --noora-choice-selector-switch-off-background-hover: var(
      --noora-neutral-dark-900
    );
    --noora-choice-selector-check-background-hover:
      linear-gradient(
        180deg,
        oklch(100% 0 0 / 0.06) 0%,
        oklch(100% 0 0 / 0) 100%
      ),
      var(--noora-purple-500);
  }

  &[data-theme="dark"] {
    --noora-badge-light-fill-blend-mode: screen;
    --noora-border-small-default:
      0px 1px 1px 0px oklch(16.2% 0 0 / 0.3),
      0px 0px 0px 1px oklch(54.9% 0 0 / 0.45),
      0px 2px 3px 0px oklch(0% 0 0 / 0.3);
    --noora-border-small-focus:
      0px 1px 1px 0px oklch(from var(--noora-neutral-dark-1200) l c h / 0.2),
      0px 0px 0px 1px oklch(from var(--noora-neutral-dark-500) l c h / 0.3),
      0px 0px 0px 1px var(--noora-neutral-dark-200),
      0px 2px 3px 0px oklch(from var(--noora-alpha-black-80) l c h / 0.3),
      0px 0px 0px 4px oklch(from var(--noora-neutral-dark-500) l c h / 0.5);
    --noora-border-small-error:
      0px 1px 1px 0px oklch(16.2% 0 0 / 0.2),
      0px 0px 0px 1px var(--noora-red-300), 0px 2px 3px 0px oklch(0% 0 0 / 0.3);
    --noora-border-small-warning:
      0px 1px 1px 0px oklch(from var(--noora-neutral-dark-1200) l c h / 0.2),
      0px 0px 0px 1px var(--noora-orange-300),
      0px 2px 3px 0px oklch(from var(--noora-alpha-black-80) l c h / 0.3);
    --noora-border-medium:
      0px 2px 4px 0px oklch(from var(--noora-neutral-dark-1200) l c h / 0.12),
      0px 0px 0px 1px oklch(from var(--noora-neutral-dark-500) l c h / 0.45),
      0px 4px 8px 0px oklch(0% 0 0 / 0.24);
    --noora-border-section: 0 0 0 1px oklch(34.8% 0 0 / 0.55);
    --noora-border-large:
      0px 4px 8px 0px oklch(from var(--noora-alpha-black-80) l c h / 0.24),
      0px 0px 0px 1px oklch(from var(--noora-neutral-dark-500) l c h / 0.45),
      0px 2px 4px 0px oklch(from var(--noora-alpha-black-80) l c h / 0.4);
    --noora-border-xlarge:
      0px 4px 8px 0px oklch(from var(--noora-alpha-black-80) l c h / 0.16),
      0px 0px 0px 1px oklch(from var(--noora-neutral-dark-500) l c h / 0.45),
      0px 8px 16px 0px oklch(from var(--noora-alpha-black-80) l c h / 0.5),
      0px 2px 4px 0px oklch(from var(--noora-alpha-black-80) l c h / 0.4);
  }

  @media screen and (min-width: 768px) {
    --noora-font-display-xlarge: 4.5rem/4.875rem var(--noora-font-heading);
    --noora-font-display-large: 4rem/4.375rem var(--noora-font-heading);
    --noora-font-display-medium: 3.5rem/4rem var(--noora-font-heading);
    --noora-font-display-small: 3rem/3.5rem var(--noora-font-heading);
    --noora-font-heading-2xlarge: 2.5rem/2.875rem var(--noora-font-heading);
    --noora-font-heading-xlarge: 2rem/2.375rem var(--noora-font-heading);
    --noora-font-heading-large: 1.5rem/2rem var(--noora-font-heading);
    --noora-font-heading-medium: 1.25rem/1.625rem var(--noora-font-heading);
    --noora-font-heading-small: 1.125rem/1.5rem var(--noora-font-heading);
  }

  --noora-font-color-primary: light-dark(
    var(--noora-neutral-light-1100),
    var(--noora-neutral-light-100)
  );
  --noora-font-color-secondary: light-dark(
    var(--noora-neutral-light-1000),
    var(--noora-neutral-light-400)
  );
  --noora-font-color-disabled: light-dark(
    var(--noora-neutral-light-800),
    var(--noora-neutral-light-900)
  );
  --noora-font-color-information: light-dark(
    var(--noora-azure-500),
    var(--noora-azure-300)
  );
  --noora-font-color-success: light-dark(
    var(--noora-green-600),
    var(--noora-green-400)
  );
  --noora-font-color-warning: light-dark(
    var(--noora-orange-600),
    var(--noora-orange-300)
  );
  --noora-font-color-error: light-dark(
    var(--noora-red-500),
    var(--noora-red-300)
  );

  /* Easing */
  --ease-in-quad: cubic-bezier(0.55, 0.085, 0.68, 0.53);
  --ease-in-cubic: cubic-bezier(0.55, 0.055, 0.675, 0.19);
  --ease-in-quart: cubic-bezier(0.895, 0.03, 0.685, 0.22);
  --ease-in-quint: cubic-bezier(0.755, 0.05, 0.855, 0.06);
  --ease-in-expo: cubic-bezier(0.95, 0.05, 0.795, 0.035);
  --ease-in-circ: cubic-bezier(0.6, 0.04, 0.98, 0.335);

  --ease-out-quad: cubic-bezier(0.25, 0.46, 0.45, 0.94);
  --ease-out-cubic: cubic-bezier(0.215, 0.61, 0.355, 1);
  --ease-out-quart: cubic-bezier(0.165, 0.84, 0.44, 1);
  --ease-out-quint: cubic-bezier(0.23, 1, 0.32, 1);
  --ease-out-expo: cubic-bezier(0.19, 1, 0.22, 1);
  --ease-out-circ: cubic-bezier(0.075, 0.82, 0.165, 1);
  /* Hover and color changes on controls, such as buttons. */
  --noora-ease-hover: cubic-bezier(0.4, 0, 0.2, 1);
  /* Ease out with a slight overshoot before settling. Used by toasts. */
  --noora-ease-out-overshoot: cubic-bezier(0.21, 1.02, 0.73, 1);

  --ease-in-out-quad: cubic-bezier(0.455, 0.03, 0.515, 0.955);
  --ease-in-out-cubic: cubic-bezier(0.645, 0.045, 0.355, 1);
  --ease-in-out-quart: cubic-bezier(0.77, 0, 0.175, 1);
  --ease-in-out-quint: cubic-bezier(0.86, 0, 0.07, 1);
  --ease-in-out-expo: cubic-bezier(1, 0, 0, 1);
  --ease-in-out-circ: cubic-bezier(0.785, 0.135, 0.15, 0.86);
}

/* Wide-gamut overrides: same lightness and hue, more chroma on Display P3 screens.
   Steps without an entry already sit inside sRGB. */
@media (color-gamut: p3) {
  :root {
    --noora-purple-50: oklch(97.5% 0.014 291.5);
    --noora-purple-100: oklch(93.7% 0.035 290.8);
    --noora-purple-200: oklch(86.8% 0.076 290);
    --noora-purple-300: oklch(77.5% 0.133 289.2);
    --noora-purple-400: oklch(66.5% 0.2 288.3);
    --noora-purple-500: oklch(54.8% 0.283 287.4);
    --noora-pink-50: oklch(97.5% 0.016 5);
    --noora-pink-100: oklch(93.7% 0.038 5.5);
    --noora-pink-200: oklch(86.8% 0.088 6);
    --noora-pink-300: oklch(77.5% 0.162 6.5);
    --noora-pink-400: oklch(66.5% 0.26 7);
    --noora-pink-500: oklch(54.8% 0.245 7.5);
    --noora-pink-600: oklch(48.5% 0.215 7.8);
    --noora-pink-700: oklch(41.5% 0.182 8);
    --noora-pink-800: oklch(34.5% 0.145 8);
    --noora-pink-900: oklch(27.5% 0.112 8);
    --noora-red-50: oklch(97.5% 0.015 25);
    --noora-red-100: oklch(93.7% 0.04 25.4);
    --noora-red-200: oklch(86.8% 0.09 25.8);
    --noora-red-300: oklch(77.5% 0.16 26.2);
    --noora-red-400: oklch(66.5% 0.24 26.6);
    --noora-red-500: oklch(54.8% 0.25 27);
    --noora-red-600: oklch(48.5% 0.22 27.2);
    --noora-red-700: oklch(41.5% 0.185 27.4);
    --noora-red-800: oklch(34.5% 0.15 27.6);
    --noora-red-900: oklch(27.5% 0.115 27.8);
    --noora-orange-50: oklch(97.5% 0.016 58);
    --noora-orange-100: oklch(93.7% 0.042 57);
    --noora-orange-200: oklch(86.8% 0.095 55);
    --noora-orange-300: oklch(77.5% 0.17 52);
    --noora-orange-400: oklch(66.5% 0.205 48);
    --noora-orange-500: oklch(54.8% 0.18 44);
    --noora-orange-600: oklch(48.5% 0.165 42);
    --noora-orange-700: oklch(41.5% 0.144 41);
    --noora-orange-800: oklch(34.5% 0.115 41);
    --noora-orange-900: oklch(27.5% 0.09 41);
    --noora-orange-950: oklch(21.5% 0.07 41);
    --noora-yellow-200: oklch(93% 0.1 91.5);
    --noora-yellow-300: oklch(90.5% 0.135 90);
    --noora-yellow-400: oklch(87.5% 0.168 88);
    --noora-yellow-500: oklch(84.8% 0.195 86);
    --noora-yellow-600: oklch(72% 0.17 80);
    --noora-yellow-700: oklch(56.5% 0.135 74);
    --noora-yellow-800: oklch(44.5% 0.105 70);
    --noora-yellow-900: oklch(32.5% 0.078 68);
    --noora-yellow-950: oklch(21.5% 0.052 67);
    --noora-green-400: oklch(66.5% 0.2 148);
    --noora-green-500: oklch(54.8% 0.19 147);
    --noora-green-600: oklch(48.5% 0.172 147.5);
    --noora-green-700: oklch(41.5% 0.148 148);
    --noora-green-800: oklch(34.5% 0.118 149);
    --noora-green-900: oklch(27.5% 0.09 150);
    --noora-green-950: oklch(21.5% 0.068 151);
    --noora-azure-50: oklch(97.5% 0.015 236);
    --noora-azure-100: oklch(93.7% 0.038 236.5);
    --noora-azure-200: oklch(86.8% 0.08 237);
    --noora-azure-300: oklch(77.5% 0.14 238);
    --noora-azure-400: oklch(66.5% 0.185 240);
    --noora-azure-500: oklch(54.8% 0.169 242);
    --noora-azure-600: oklch(48.5% 0.154 243.5);
    --noora-azure-700: oklch(41.5% 0.135 245);
    --noora-azure-800: oklch(34.5% 0.11 246);
    --noora-azure-900: oklch(27.5% 0.088 247);
    --noora-azure-950: oklch(21.5% 0.068 248);
    --noora-blue-50: oklch(97.5% 0.013 256);
    --noora-blue-100: oklch(93.7% 0.033 256.5);
    --noora-blue-200: oklch(86.8% 0.071 257);
    --noora-blue-300: oklch(77.5% 0.125 258);
    --noora-blue-400: oklch(66.5% 0.188 259);
    --noora-blue-500: oklch(54.8% 0.24 260);
    --noora-blue-600: oklch(48.5% 0.225 261);
    --noora-blue-700: oklch(41.5% 0.195 262);

    --noora-alpha-red-24: oklch(54.8% 0.25 27 / 0.24);
    --noora-alpha-red-32: oklch(54.8% 0.25 27 / 0.32);
    --noora-alpha-orange-24: oklch(66.5% 0.205 48 / 0.24);
    --noora-alpha-yellow-24: oklch(84.8% 0.195 86 / 0.24);
    --noora-alpha-green-24: oklch(54.8% 0.19 147 / 0.24);
    --noora-alpha-azure-24: oklch(54.8% 0.169 242 / 0.24);
    --noora-alpha-blue-24: oklch(54.8% 0.24 260 / 0.24);
    --noora-alpha-purple-24: oklch(54.8% 0.283 287.4 / 0.24);
    --noora-alpha-purple-32: oklch(54.8% 0.283 287.4 / 0.32);
    --noora-alpha-pink-24: oklch(54.8% 0.245 7.5 / 0.24);
  }
}

/* Dark mode for Storybook only */
.noora-dark {
  color-scheme: dark;
}

/* alert.css */
.noora-alert {
  --noora-alert-default-icon: light-dark(
    var(--noora-neutral-light-1000),
    var(--noora-neutral-light-200)
  );
  --noora-alert-default-secondary-background: light-dark(
    var(--noora-neutral-light-100),
    var(--noora-neutral-gray-50)
  );
  --noora-alert-error-icon: light-dark(
    var(--noora-red-500),
    var(--noora-red-400)
  );
  --noora-alert-error-secondary-background: light-dark(
    var(--noora-red-50),
    var(--noora-alpha-red-24)
  );
  --noora-alert-success-icon: light-dark(
    var(--noora-green-500),
    var(--noora-green-400)
  );
  --noora-alert-success-secondary-background: light-dark(
    var(--noora-green-50),
    var(--noora-alpha-green-24)
  );
  --noora-alert-warning-icon: light-dark(
    var(--noora-orange-500),
    var(--noora-orange-400)
  );
  --noora-alert-warning-secondary-background: light-dark(
    var(--noora-orange-50),
    var(--noora-alpha-orange-24)
  );
  --noora-alert-information-icon: light-dark(
    var(--noora-azure-500),
    var(--noora-azure-400)
  );
  --noora-alert-information-secondary-background: light-dark(
    var(--noora-azure-50),
    var(--noora-alpha-azure-24)
  );
  display: flex;
  /* Everything lines up with the title's first line, so a wrapping title
     doesn't leave the icon, actions, and dismiss button at odd heights. The
     icon, dismiss button, and title line share a height at each size. */
  align-items: flex-start;

  border-radius: var(--noora-radius-4);

  /* In single-line alerts the title fills the row, so actions sit at the
     end next to the dismiss button. */
  & > [data-part="title"] {
    flex: 1;
    min-width: 0;
    color: var(--noora-surface-label-primary);
  }

  & [data-part="description"] {
    margin-top: var(--noora-spacing-2);
    color: var(--noora-surface-label-secondary);
    font: var(--noora-font-body-medium);
  }

  /* The dismiss button always sits at the end of the alert, whatever the
     length of the title and actions before it. */
  & [data-part="dismiss-icon"] {
    flex-shrink: 0;
    margin-inline-start: auto;
  }

  & [data-part="actions"] {
    display: flex;
    align-items: center;
    gap: var(--noora-spacing-4);

    & > [data-part="action"] {
      display: flex;
    }

    /* A single action, and every action after the first, renders without an
       underline regardless of the link button's \`underline\` attribute. Only
       the first of several actions is underlined. */
    & .noora-link-button:not(:disabled) {
      text-decoration: none;

      &:hover {
        text-decoration: underline;
      }
    }

    &
      > [data-part="action"]:first-child:not(:last-child)
      .noora-link-button:not(:disabled) {
      text-decoration: underline;

      &:hover {
        text-decoration-style: dotted;
      }
    }

    & > [data-part="action-separator"] {
      flex-shrink: 0;
      border-radius: 50%;
      background: var(--noora-surface-label-tertiary);
      width: 3px;
      height: 3px;
    }
  }

  &[data-type="primary"] {
    box-shadow: var(--noora-border-small-default);
    background: var(--noora-surface-background-primary);
  }

  &[data-type="secondary"] {
    &[data-status="default"] {
      background: var(--noora-alert-default-secondary-background);
    }
    &[data-status="information"] {
      background: var(--noora-alert-information-secondary-background);
    }
    &[data-status="success"] {
      background: var(--noora-alert-success-secondary-background);
    }
    &[data-status="warning"] {
      background: var(--noora-alert-warning-secondary-background);
    }
    &[data-status="error"] {
      background: var(--noora-alert-error-secondary-background);
    }
  }

  &[data-size="small"] {
    gap: var(--noora-spacing-4);
    padding: var(--noora-spacing-4);
    & > [data-part="icon"] {
      display: flex;
      flex-shrink: 0;
      width: var(--noora-icon-size-medium);
      height: var(--noora-icon-size-medium);

      & svg {
        width: 100%;
        height: 100%;
      }
    }

    /* Actions match the title's size, whatever button size is passed. */
    & [data-part="title"],
    & [data-part="actions"] .noora-link-button {
      font: var(--noora-font-body-small);
    }

    & [data-part="actions"] .noora-link-button {
      font-weight: var(--noora-font-weight-medium);
    }
  }

  &[data-size="medium"] {
    gap: var(--noora-spacing-5);
    padding: var(--noora-spacing-5);

    & > [data-part="icon"] {
      display: flex;
      flex-shrink: 0;
      width: var(--noora-icon-size-large);
      height: var(--noora-icon-size-large);

      & svg {
        width: 100%;
        height: 100%;
      }
    }

    & [data-part="title"],
    & [data-part="actions"] .noora-link-button {
      font: var(--noora-font-body-medium);
    }

    & [data-part="actions"] .noora-link-button {
      font-weight: var(--noora-font-weight-medium);
    }
  }

  &[data-size="large"] {
    gap: var(--noora-spacing-5);
    padding: var(--noora-spacing-5) var(--noora-spacing-5)
      var(--noora-spacing-6);

    & > [data-part="icon"] {
      display: flex;
      flex-shrink: 0;
      width: var(--noora-icon-size-large);
      height: var(--noora-icon-size-large);

      & svg {
        width: 100%;
        height: 100%;
      }
    }

    & > [data-part="column"] {
      display: flex;
      flex-direction: column;

      & > [data-part="title"] {
        font: var(--noora-font-weight-medium) var(--noora-font-body-medium);
      }

      & > [data-part="actions"] {
        margin-top: var(--noora-spacing-4);

        & .noora-link-button {
          font: var(--noora-font-weight-medium) var(--noora-font-body-medium);
        }
      }
    }
  }

  &[data-status="default"] {
    & [data-part="icon"] {
      color: var(--noora-alert-default-icon);
    }
  }
  &[data-status="information"] {
    & [data-part="icon"] {
      color: var(--noora-alert-information-icon);
    }
  }
  &[data-status="error"] {
    & [data-part="icon"] {
      color: var(--noora-alert-error-icon);
    }
  }
  &[data-status="success"] {
    & [data-part="icon"] {
      color: var(--noora-alert-success-icon);
    }
  }
  &[data-status="warning"] {
    & [data-part="icon"] {
      color: var(--noora-alert-warning-icon);
    }
  }
}

/* badge.css */
.noora-badge {
  display: inline-flex;
  justify-content: center;
  align-items: center;
  border-radius: var(--noora-radius-2);
  padding: var(--noora-spacing-1) var(--noora-spacing-4);

  &[data-disabled] {
    background: var(--noora-badge-disabled-background) !important;
    color: var(--noora-badge-disabled-label) !important;
  }

  &[data-icon] {
    padding-inline-start: var(--noora-spacing-2);
  }

  &[data-dot] {
    padding-inline-end: var(--noora-spacing-3);
    padding-inline-start: var(--noora-spacing-0);
  }

  &[data-size="small"] {
    font: var(--noora-font-weight-medium) var(--noora-font-body-xsmall);
    /* Optical balance: the xsmall step (10px) plus 1px reads as better
       centered in the small badge. Only the size changes; the token's 12px
       line height, and so the badge's height, stay as they are. */
    font-size: calc(0.625rem + 1px);

    &[data-icon] {
      gap: var(--noora-spacing-1);
    }

    & [data-part="icon"] {
      width: var(--noora-icon-size-small);
      height: var(--noora-icon-size-small);

      & svg {
        width: 100%;
        height: 100%;
      }
    }
  }

  &[data-size="medium"] {
    font: var(--noora-font-weight-medium) var(--noora-font-body-small);

    &[data-icon] {
      gap: var(--noora-spacing-2);
    }

    &[data-dot] {
      padding-inline-start: var(--noora-spacing-1);
    }

    /* Icons and dots sit in a 14px box, between Noora's 12px and 16px
       icon sizes. */
    & [data-part="icon"] {
      width: 14px;
      height: 14px;

      & svg {
        width: 100%;
        height: 100%;
      }
    }
  }

  &[data-size="large"] {
    font: var(--noora-font-weight-medium) var(--noora-font-body-medium);
    /* Optical balance, as in the small badge: the medium step (14px) minus
       1px. Only the size changes; the token's 20px line height, and so the
       badge's height, stay as they are. */
    font-size: calc(0.875rem - 1px);

    &[data-icon] {
      gap: var(--noora-spacing-2);
    }

    &[data-dot] {
      padding-inline-end: var(--noora-spacing-4);
      padding-inline-start: var(--noora-spacing-1);
    }

    & [data-part="icon"] {
      width: var(--noora-icon-size-medium);
      height: var(--noora-icon-size-medium);

      & svg {
        width: 100%;
        height: 100%;
      }
    }
  }

  &[data-style="fill"] {
    color: var(--noora-badge-fill-primary-label);

    &[data-color="neutral"] {
      background: var(--noora-badge-fill-neutral);
    }

    &[data-color="destructive"] {
      background: var(--noora-badge-fill-destructive);
    }

    &[data-color="warning"] {
      background: var(--noora-badge-fill-warning);
    }

    /* Yellow is too light for the white label, so the attention badge uses
       the dark secondary label, for its text and its icon or dot. */
    &[data-color="attention"] {
      background: var(--noora-badge-fill-attention);
      color: var(--noora-badge-fill-secondary-label);

      & [data-part="icon"] rect {
        fill: currentColor;
      }
    }

    &[data-color="success"] {
      background: var(--noora-badge-fill-success);
    }

    &[data-color="information"] {
      background: var(--noora-badge-fill-information);
    }

    &[data-color="focus"] {
      background: var(--noora-badge-fill-focus);
    }

    &[data-color="primary"] {
      background: var(--noora-badge-fill-primary);
    }

    &[data-color="secondary"] {
      background: var(--noora-badge-fill-secondary);
    }
  }

  /* The tint is drawn on a layer behind the content and blended with the
     surface under the badge; blending the badge itself would blend its label
     too. Where an ancestor isolates blending, the tint shows as it is. */
  &[data-style="light-fill"] {
    position: relative;

    &::before {
      position: absolute;
      inset: 0;
      border-radius: inherit;
      background: var(--noora-badge-light-fill-background);
      content: "";
      mix-blend-mode: var(--noora-badge-light-fill-blend-mode);
    }

    & > * {
      position: relative;
    }

    &[data-disabled]::before {
      display: none;
    }

    &[data-color="neutral"] {
      --noora-badge-light-fill-background: var(
        --noora-badge-light-fill-neutral-background
      );
      color: var(--noora-badge-light-fill-neutral-label);
    }

    &[data-color="destructive"] {
      --noora-badge-light-fill-background: var(
        --noora-badge-light-fill-destructive-background
      );
      color: var(--noora-badge-light-fill-destructive-label);
    }

    &[data-color="warning"] {
      --noora-badge-light-fill-background: var(
        --noora-badge-light-fill-warning-background
      );
      color: var(--noora-badge-light-fill-warning-label);
    }

    &[data-color="attention"] {
      --noora-badge-light-fill-background: var(
        --noora-badge-light-fill-attention-background
      );
      color: var(--noora-badge-light-fill-attention-label);
    }

    &[data-color="success"] {
      --noora-badge-light-fill-background: var(
        --noora-badge-light-fill-success-background
      );
      color: var(--noora-badge-light-fill-success-label);
    }

    &[data-color="information"] {
      --noora-badge-light-fill-background: var(
        --noora-badge-light-fill-information-background
      );
      color: var(--noora-badge-light-fill-information-label);
    }

    &[data-color="focus"] {
      --noora-badge-light-fill-background: var(
        --noora-badge-light-fill-focus-background
      );
      color: var(--noora-badge-light-fill-focus-label);
    }

    &[data-color="primary"] {
      --noora-badge-light-fill-background: var(
        --noora-badge-light-fill-primary-background
      );
      color: var(--noora-badge-light-fill-primary-label);
    }

    &[data-color="secondary"] {
      --noora-badge-light-fill-background: var(
        --noora-badge-light-fill-secondary-background
      );
      color: var(--noora-badge-light-fill-secondary-label);
    }
  }
}

.noora-status-badge {
  display: inline-flex;
  justify-content: center;
  align-items: center;
  gap: var(--noora-spacing-2);
  box-shadow: var(--noora-border-small-default);
  border-radius: var(--noora-radius-2);
  background: var(--noora-surface-background-primary);
  padding-block: var(--noora-spacing-1);
  padding-inline: var(--noora-spacing-2) var(--noora-spacing-4);

  & [data-part="icon"] {
    display: inline-flex;
    justify-content: center;
    align-items: center;

    & svg {
      width: var(--noora-icon-size-medium);
      height: var(--noora-icon-size-medium);
    }
  }

  /* Matches the large badge: the medium font step (14px) minus 1px, keeping
     the token's 20px line height. */
  & [data-part="label"] {
    font: var(--noora-font-weight-medium) var(--noora-font-body-medium);
    font-size: calc(0.875rem - 1px);
  }

  &:not([data-status="disabled"]) {
    color: var(--noora-surface-label-primary);
  }

  &[data-status="disabled"] {
    color: var(--noora-surface-label-disabled);
  }

  &[data-status="success"] [data-part="icon"] {
    color: var(--noora-badge-status-success);
  }
  &[data-status="error"] [data-part="icon"] {
    color: var(--noora-badge-status-error);
  }
  &[data-status="warning"] [data-part="icon"] {
    color: var(--noora-badge-status-warning);
  }
  &[data-status="attention"] [data-part="icon"] {
    color: var(--noora-badge-status-attention);
  }
  &[data-status="in_progress"] [data-part="icon"] {
    color: var(--noora-badge-status-in-progress);
  }

  /* A running dot blinks, between half and full opacity. */
  &[data-status="in_progress"][data-type="dot"] [data-part="icon"] {
    animation: noora-status-badge-blink 1.2s ease-in-out infinite;
  }
}

@keyframes noora-status-badge-blink {
  0%,
  100% {
    opacity: 1;
  }

  50% {
    opacity: 0.5;
  }
}

@media (prefers-reduced-motion: reduce) {
  .noora-status-badge[data-status="in_progress"][data-type="dot"]
    [data-part="icon"] {
    animation: none;
  }
}

/* button.css */
.noora-button,
.noora-link-button,
.noora-ghost-button {
  display: inline-flex;
  justify-content: center;
  align-items: center;
  box-sizing: border-box;
  -webkit-appearance: button;
  border: 0;
  border-radius: var(--noora-radius-3);
  padding: 0;
  text-decoration: none;

  & svg {
    pointer-events: none;
  }
}

.noora-button {
  position: relative;
  isolation: isolate;
  cursor: pointer;
  outline: unset;
  /* Hover eases in and out: the border shadow here, the background through
     the layer below. Focus rings stay instant; their shadow layers don't
     line up with the resting ones, so the browser swaps them. */
  transition:
    transform 150ms var(--ease-out-cubic),
    box-shadow 150ms var(--noora-ease-hover);
  /* Reserve space for box-shadow to ensure consistent height across variants */
  box-shadow:
    0px 0px 0px 0px transparent,
    0px 0px 0px 0px transparent,
    0px 0px 0px 0px transparent,
    0px 0px 0px 0px transparent;

  &[disabled] {
    cursor: not-allowed;
  }

  &:not(:disabled):active {
    transform: scale(0.97);
  }

  & > span {
    padding: 0rem var(--noora-spacing-2);
  }

  /* The hover background fades in over the resting one, under the label and
     icons: a gradient can't animate into another, a layer's opacity can. It
     starts 1px down so the top highlight, an inset shadow painted under it,
     stays visible. */
  &::before {
    position: absolute;
    inset: 1px 0 0;
    z-index: -1;
    opacity: 0;
    transition: opacity 150ms var(--noora-ease-hover);
    pointer-events: none;
    border-radius: inherit;
    background: var(--noora-button-hover-background);
    content: "";
  }

  &:not(:disabled):hover::before {
    opacity: 1;
  }

  /* Pressed shows its own background at once. */
  &:not(:disabled):active::before {
    opacity: 0;
    transition: none;
  }

  &[data-variant="primary"] {
    box-shadow: var(--noora-button-border-primary);
    --noora-button-hover-background: var(
      --noora-button-background-primary-hover
    );

    background: var(--noora-button-background-primary);
    color: var(--noora-button-primary-label);

    &:hover {
      box-shadow: var(--noora-button-border-primary-hover);
    }

    &:focus-visible {
      box-shadow: var(--noora-button-border-focus);
    }

    &[disabled] {
      box-shadow: var(--noora-button-border-disabled);
      background: var(--noora-button-background-disabled);
      color: var(--noora-button-disabled-label);
    }

    &:not(:disabled):active {
      box-shadow: var(--noora-button-border-primary-active);
      background: var(--noora-button-background-primary-active);
    }
  }

  &[data-variant="secondary"] {
    box-shadow: var(--noora-button-border-secondary);
    --noora-button-hover-background: var(
      --noora-button-background-secondary-hover
    );

    background: var(--noora-button-background-secondary);
    color: var(--noora-button-secondary-label);

    &:focus-visible {
      box-shadow: var(--noora-button-border-focus);
    }

    &[disabled] {
      box-shadow: var(--noora-button-border-disabled);
      background: var(--noora-button-background-disabled);
      color: var(--noora-button-disabled-label);
    }

    &:not(:disabled):active {
      box-shadow: var(--noora-button-border-secondary-active);
      background: var(--noora-button-background-secondary-active);
    }
  }

  &[data-variant="destructive"] {
    box-shadow: var(--noora-button-border-destructive);
    --noora-button-hover-background: var(
      --noora-button-background-destructive-hover
    );

    background: var(--noora-button-background-destructive);

    color: var(--noora-button-destructive-label);

    &:hover {
      box-shadow: var(--noora-button-border-destructive-hover);
    }

    &:focus-visible {
      box-shadow: var(--noora-button-border-focus);
    }

    &[disabled] {
      box-shadow: var(--noora-button-border-disabled);
      background: var(--noora-button-background-disabled);
      color: var(--noora-button-disabled-label);
    }

    &:not(:disabled):active {
      box-shadow: var(--noora-button-border-destructive-active);
      background: var(--noora-button-destructive-background);
    }
  }
}

.noora-link-button {
  --noora-link-button-primary-label: light-dark(
    var(--noora-purple-500),
    var(--noora-purple-300)
  );
  --noora-link-button-secondary-label: light-dark(
    var(--noora-neutral-light-1200),
    var(--noora-neutral-light-50)
  );
  --noora-link-button-destructive-label: light-dark(
    var(--noora-red-500),
    var(--noora-red-300)
  );
  --noora-link-button-disabled-label: light-dark(
    var(--noora-neutral-light-600),
    var(--noora-neutral-light-300)
  );

  display: inline-flex;
  gap: var(--noora-spacing-1);
  border-radius: var(--noora-radius-1);
  background: transparent;

  &:focus-visible {
    outline: var(--noora-focus-ring-width) solid var(--noora-focus-ring-color);
    outline-offset: var(--noora-focus-ring-offset);
  }

  &:disabled {
    cursor: not-allowed;
    color: var(--noora-link-button-disabled-label) !important;
  }

  &:not(:disabled)[data-underline] {
    text-decoration: underline;

    &:hover {
      text-decoration-style: dotted;
    }
  }

  &:not(:disabled):not([data-underline]):hover {
    text-decoration: underline;
  }

  &[data-variant="primary"] {
    color: var(--noora-link-button-primary-label);
  }

  &[data-variant="secondary"] {
    color: var(--noora-link-button-secondary-label);
  }

  &[data-variant="destructive"] {
    color: var(--noora-link-button-destructive-label);
  }

  &[data-size="small"] {
    font: var(--noora-font-weight-medium) var(--noora-font-body-xsmall);

    & svg {
      width: var(--noora-icon-size-small);
      height: var(--noora-icon-size-small);
    }
  }

  &[data-size="medium"] {
    font: var(--noora-font-weight-medium) var(--noora-font-body-small);

    & svg {
      width: var(--noora-icon-size-medium);
      height: var(--noora-icon-size-medium);
    }
  }

  /* A 16px icon beside the 14px label, as in large buttons. */
  &[data-size="large"] {
    font: var(--noora-font-weight-medium) var(--noora-font-body-medium);

    & svg {
      width: var(--noora-icon-size-medium);
      height: var(--noora-icon-size-medium);
    }
  }
}

.noora-ghost-button {
  display: inline-flex;
  justify-content: center;
  align-items: center;
  cursor: pointer;
  border-radius: var(--noora-radius-3);
  background: unset;
  padding: var(--noora-spacing-3);
  text-decoration: none;
  /* Hover and selected fill 1px past the edge, in the same color, so the
     fill reads the same size as a filled button with its outside ring. */
  transition:
    transform 150ms var(--ease-out-cubic),
    background-color 150ms var(--noora-ease-hover),
    box-shadow 150ms var(--noora-ease-hover),
    color 150ms var(--noora-ease-hover);

  &:not(:disabled):active {
    transform: scale(0.97);
  }

  &[data-variant="primary"] {
    color: var(--noora-button-ghost-primary-label);

    &:not(:disabled):hover {
      box-shadow: 0px 0px 0px 1px var(--noora-button-ghost-primary-hover);
      background: var(--noora-button-ghost-primary-hover);
    }

    &:not(:disabled):active {
      box-shadow: 0px 0px 0px 1px var(--noora-button-ghost-primary-selected);
      background: var(--noora-button-ghost-primary-selected);
    }
  }

  &[data-variant="secondary"] {
    color: var(--noora-button-ghost-secondary-label);

    &:not(:disabled):hover {
      box-shadow: 0px 0px 0px 1px var(--noora-button-ghost-secondary-hover);
      background: var(--noora-button-ghost-secondary-hover);
    }

    &:not(:disabled):active {
      box-shadow: 0px 0px 0px 1px var(--noora-button-ghost-secondary-selected);
      background: var(--noora-button-ghost-secondary-selected);
    }
  }

  &[data-variant="destructive"] {
    color: var(--noora-button-ghost-destructive-label);

    &:not(:disabled):hover {
      box-shadow: 0px 0px 0px 1px var(--noora-button-ghost-destructive-hover);
      background: var(--noora-button-ghost-destructive-hover);
    }

    &:not(:disabled):active {
      box-shadow: 0px 0px 0px 1px var(--noora-button-ghost-destructive-selected);
      background: var(--noora-button-ghost-destructive-selected);
    }
  }

  /* Secondary with a 1px border that stays in every state, and with it the
     size of a filled button. */
  &[data-variant="outline"] {
    box-shadow: 0px 0px 0px 1px var(--noora-button-ghost-outline-border);
    color: var(--noora-button-ghost-secondary-label);

    &:not(:disabled):hover {
      background: var(--noora-button-ghost-secondary-hover);
    }

    &:not(:disabled):active {
      background: var(--noora-button-ghost-secondary-selected);
    }
  }

  /* After the variants, so it wins over their label colors. */
  &[disabled] {
    cursor: not-allowed;
    color: var(--noora-button-disabled-label);
  }

  /* Same label inset as .noora-button's \`& > span\`, scoped to the label
     part so icons that arrive wrapped in spans keep their geometry. */
  & > [data-part="label"] {
    padding: 0rem var(--noora-spacing-2);
  }
}

/* Sizes, shared by buttons and ghost buttons so the two sit side by side
   (e.g. the navbar's action cluster) with the same geometry. A neutral
   button is icon-only when it has no label. */
:is(.noora-button, .noora-ghost-button) {
  --noora-button-icon-size: var(--noora-icon-size-medium);

  & svg {
    width: var(--noora-button-icon-size);
    height: var(--noora-button-icon-size);
  }

  /* 4px all round with a 16px icon and the 12px label: 24px tall,
     labelled or icon-only. */
  &[data-size="small"] {
    padding: var(--noora-spacing-2);
    font: var(--noora-font-weight-medium) var(--noora-font-body-small);
  }

  /* The 14px label with 4px padding all round: 28px tall. Icon-only ones
     keep 6px around the 16px icon to match. */
  &[data-size="medium"] {
    padding: var(--noora-spacing-2);
    font: var(--noora-font-weight-medium) var(--noora-font-body-medium);

    &:is([data-icon-only], .noora-ghost-button:not([data-with-label])) {
      padding: var(--noora-spacing-3);
    }
  }

  /* A 16px icon beside the 14px label; icon-only ones pad 8px to stay 32px
     square, the labelled height. */
  &[data-size="large"] {
    padding: var(--noora-spacing-3) var(--noora-spacing-4);
    font: var(--noora-font-weight-medium) var(--noora-font-body-medium);

    &:is([data-icon-only], .noora-ghost-button:not([data-with-label])) {
      padding: var(--noora-spacing-4);
    }
  }
}

@media (prefers-reduced-motion: reduce) {
  .noora-button,
  .noora-ghost-button {
    transition: none;

    &::before {
      transition: none;
    }

    &:not(:disabled):active {
      transform: none;
    }
  }
}

/* button_group.css */
.noora-button-group {
  display: flex;
  position: relative;
  flex-direction: row;
  align-items: center;
  /* The sliding tile sits behind the items but over the group's fill. */
  isolation: isolate;

  border-radius: var(--noora-radius-3);
  background-color: var(--noora-surface-background-secondary);
  /* Not clipped: a focused item's ring reaches past the group's padding. */
  padding: var(--noora-spacing-1);

  /* 2px between items, at every size. */
  gap: var(--noora-spacing-1);
}

/* The raised tile behind the selected item (js/ButtonGroup.js). It slides
   to each newly selected item; until it's in place, and without JavaScript,
   the selected item draws its own tile instead. */
.noora-button-group > [data-part="indicator"] {
  display: none;
  position: absolute;
  top: 0;
  left: 0;
  z-index: -1;
  box-shadow: var(--noora-border-small-default);
  border-radius: var(--noora-radius-2);
  background: var(--noora-surface-background-primary);
  pointer-events: none;

  &:state(active) {
    display: block;
  }
}

.noora-button-group:has(> [data-part="indicator"]:state(active))
  > .noora-button-group-item {
  &[data-selected],
  &:active {
    box-shadow: none;
    background: none;
  }

  &[data-selected]:focus-visible {
    box-shadow: var(--noora-focus-ring);
  }
}

.noora-button-group-item {
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: var(--noora-spacing-1);
  cursor: pointer;
  outline: unset;
  border: unset;
  border-radius: var(--noora-radius-2);

  background: none;
  overflow: hidden;
  color: var(--noora-surface-label-secondary);
  font: var(--noora-font-weight-medium) var(--noora-font-body-medium);
  user-select: none;
  text-decoration: unset;
  /* Paired with the sliding tile: the same duration and easing. */
  transition: color 200ms ease-out;

  &:hover {
    color: var(--noora-surface-label-primary);
  }

  /* The selected item, and an item while pressed, is a raised tile on the
     grey group. */
  &:active,
  &[data-selected] {
    box-shadow: var(--noora-border-small-default);
    background: var(--noora-surface-background-primary);
    color: var(--noora-surface-label-primary);
  }

  /* The standard focus ring, following the item's corners; a selected item
     keeps its raised tile under it. */
  &:focus-visible {
    box-shadow: var(--noora-focus-ring);
  }

  &[data-selected]:focus-visible {
    box-shadow: var(--noora-focus-ring), var(--noora-border-small-default);
  }

  &:disabled {
    cursor: not-allowed;
    box-shadow: none;
    background: none;
    color: var(--noora-surface-label-disabled);
  }

  & > [data-part="label"] {
    padding: var(--noora-spacing-0) var(--noora-spacing-2);
  }

  /* The 12px label or a 16px icon, 2px above and below: 20px tall, in a 24px
     group like a small button. */
  .noora-button-group[data-size="small"] & {
    padding: var(--noora-spacing-1) var(--noora-spacing-2);
    font: var(--noora-font-weight-medium) var(--noora-font-body-small);

    &[data-icon-only] {
      padding: var(--noora-spacing-1);
    }

    & svg {
      width: var(--noora-icon-size-medium);
      height: var(--noora-icon-size-medium);
    }
  }

  /* The 14px label, 2px above and below its 20px line: 24px tall, like the
     icon-only items (4px around a 16px icon). */
  .noora-button-group[data-size="medium"] & {
    gap: var(--noora-spacing-1);
    padding: var(--noora-spacing-1) var(--noora-spacing-2);
    font: var(--noora-font-weight-medium) var(--noora-font-body-medium);

    &[data-icon-only] {
      padding: var(--noora-spacing-2);
    }

    & > [data-part="label"] {
      padding: var(--noora-spacing-0) var(--noora-spacing-2);
    }

    & svg {
      width: var(--noora-icon-size-medium);
      height: var(--noora-icon-size-medium);
    }
  }

  /* A 16px icon beside the 14px label, as in large buttons; icon-only items
     pad 6px to stay 28px square, the labelled height. */
  .noora-button-group[data-size="large"] & {
    padding: var(--noora-spacing-2) var(--noora-spacing-4);
    font: var(--noora-font-weight-medium) var(--noora-font-body-medium);

    &[data-icon-only] {
      padding: var(--noora-spacing-3);
    }

    & svg {
      width: var(--noora-icon-size-medium);
      height: var(--noora-icon-size-medium);
    }
  }
}

@media (prefers-reduced-motion: reduce) {
  .noora-button-group-item {
    transition: none;
  }
}

/* content_divider.css */
.noora-content-divider {
  --noora-content-divider-line: light-dark(
    var(--noora-neutral-light-400),
    var(--noora-neutral-dark-900)
  );
  --noora-content-divider-label: light-dark(
    var(--noora-neutral-light-700),
    var(--noora-neutral-dark-500)
  );

  z-index: 1;
  width: 100%;
  height: 1px;
  background-color: var(--noora-content-divider-line);

  &:has([data-part="text"]) {
    display: flex;
    flex-direction: row;
    align-items: center;
    height: auto;
    background-color: transparent;

    &::before,
    &::after {
      content: "";
      flex: 1;
      height: 1px;
      background-color: var(--noora-content-divider-line);
    }
  }

  & [data-part="text"] {
    display: inline-flex;
    flex-shrink: 0;
    padding: var(--noora-spacing-0) var(--noora-spacing-2);
    color: var(--noora-content-divider-label);
    font: var(--noora-font-weight-regular) var(--noora-font-body-xsmall);
    text-transform: uppercase;
  }

  /* A label without a line, such as a group heading in a list. */
  &[data-variant="text"] {
    box-sizing: border-box;
    padding: var(--noora-spacing-4) var(--noora-spacing-2);
    height: auto;
    background-color: transparent;

    &::before,
    &::after {
      content: none;
    }

    & [data-part="text"] {
      padding: var(--noora-spacing-0);
    }
  }
}
`;
