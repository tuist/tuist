export const NOORA_CSS = String.raw`

/* tokens.css */
:root {
  color-scheme: light dark;

  /* Color palette */
  --noora-purple-50: oklch(97% 0.015 286.1);
  --noora-purple-100: oklch(88.3% 0.06 287.2);
  --noora-purple-200: oklch(79.4% 0.11 287.1);
  --noora-purple-300: oklch(70.7% 0.161 286.8);
  --noora-purple-400: oklch(62% 0.217 287);
  --noora-purple-500: oklch(53.2% 0.276 286.9);
  --noora-purple-600: oklch(46.9% 0.27 286.9);
  --noora-purple-700: oklch(38.1% 0.22 286.8);
  --noora-purple-800: oklch(29.1% 0.168 286.8);
  --noora-purple-900: oklch(21% 0.121 287);

  --noora-pink-50: oklch(97% 0.015 7.5);
  --noora-pink-100: oklch(89% 0.06 6.7);
  --noora-pink-200: oklch(81.2% 0.11 7.8);
  --noora-pink-300: oklch(73.2% 0.171 7.9);
  --noora-pink-400: oklch(65.3% 0.215 7.9);
  --noora-pink-500: oklch(57.4% 0.218 7.8);
  --noora-pink-600: oklch(50.2% 0.201 7.8);
  --noora-pink-700: oklch(40.4% 0.162 7.8);
  --noora-pink-800: oklch(30.2% 0.121 8.4);
  --noora-pink-900: oklch(21.1% 0.084 7.9);

  --noora-red-50: oklch(95% 0.02 32.5);
  --noora-red-100: oklch(89.4% 0.056 30.5);
  --noora-red-200: oklch(81.7% 0.104 31.1);
  --noora-red-300: oklch(74% 0.159 30.9);
  --noora-red-400: oklch(66.3% 0.224 30.7);
  --noora-red-500: oklch(58.7% 0.23 30.7);
  --noora-red-600: oklch(51.2% 0.201 30.7);
  --noora-red-700: oklch(41% 0.161 30.8);
  --noora-red-800: oklch(30.4% 0.12 30.6);
  --noora-red-900: oklch(21% 0.082 31);

  --noora-orange-50: oklch(97% 0.016 46.6);
  --noora-orange-100: oklch(91.9% 0.045 47.5);
  --noora-orange-200: oklch(87% 0.077 49.1);
  --noora-orange-300: oklch(81.9% 0.111 48.6);
  --noora-orange-400: oklch(76.9% 0.149 48.6);
  --noora-orange-500: oklch(71.9% 0.185 48.7);
  --noora-orange-600: oklch(62% 0.1659 48.81);
  --noora-orange-700: oklch(48% 0.129 49);
  --noora-orange-800: oklch(33.7% 0.091 48.5);
  --noora-orange-900: oklch(20.9% 0.057 48.2);

  --noora-yellow-50: oklch(97% 0.032 85.5);
  --noora-yellow-100: oklch(94.6% 0.059 86);
  --noora-yellow-200: oklch(92.2% 0.088 86.6);
  --noora-yellow-300: oklch(89.7% 0.116 86.2);
  --noora-yellow-400: oklch(87.3% 0.144 86.2);
  --noora-yellow-500: oklch(84.8% 0.174 86.1);
  --noora-yellow-600: oklch(71.9% 0.147 86);
  --noora-yellow-700: oklch(54.8% 0.112 85.9);
  --noora-yellow-800: oklch(36.9% 0.075 86.3);
  --noora-yellow-900: oklch(20.8% 0.043 84.8);

  --noora-green-50: oklch(97% 0.05 147);
  --noora-green-100: oklch(90.5% 0.115 146.9);
  --noora-green-200: oklch(83.8% 0.171 146.8);
  --noora-green-300: oklch(77.2% 0.171 146.7);
  --noora-green-400: oklch(70.7% 0.171 146.8);
  --noora-green-500: oklch(64% 0.175 146.7);
  --noora-green-600: oklch(53.7% 0.1613 146.6);
  --noora-green-700: oklch(43.8% 0.131 146.8);
  --noora-green-800: oklch(31.7% 0.095 146.6);
  --noora-green-900: oklch(20.8% 0.062 146.7);

  --noora-azure-50: oklch(97% 0.016 238.1);
  --noora-azure-100: oklch(88.9% 0.061 238.8);
  --noora-azure-200: oklch(81% 0.108 238.6);
  --noora-azure-300: oklch(73% 0.153 238.5);
  --noora-azure-400: oklch(65.1% 0.123 238);
  --noora-azure-500: oklch(57% 0.127 238.5);
  --noora-azure-600: oklch(49.8% 0.111 238.3);
  --noora-azure-700: oklch(40.3% 0.09 238.4);
  --noora-azure-800: oklch(30.1% 0.066 237.6);
  --noora-azure-900: oklch(21.1% 0.046 237.6);

  --noora-blue-50: oklch(97.1% 0.014 256.3);
  --noora-blue-100: oklch(90.2% 0.048 259.1);
  --noora-blue-200: oklch(83.4% 0.083 259.8);
  --noora-blue-300: oklch(76.6% 0.12 259.9);
  --noora-blue-400: oklch(69.7% 0.169 259.9);
  --noora-blue-500: oklch(63% 0.182 259.5);
  --noora-blue-600: oklch(54.6% 0.208 259.6);
  --noora-blue-700: oklch(43.4% 0.172 259.4);
  --noora-blue-800: oklch(31.4% 0.125 259.5);
  --noora-blue-900: oklch(20.9% 0.083 259.4);

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

  --noora-alpha-red: oklch(58.7% 0.23 30.7 / 0.18);
  --noora-alpha-orange: oklch(71.9% 0.185 48.7 / 0.16);
  --noora-alpha-yellow: oklch(84.8% 0.174 86.1 / 0.16);
  --noora-alpha-green: oklch(64% 0.175 146.7 / 0.16);
  --noora-alpha-azure: oklch(57% 0.127 238.5 / 0.16);
  --noora-alpha-blue: oklch(63% 0.182 259.5 / 0.2);
  --noora-alpha-purple: oklch(53.2% 0.276 286.9 / 0.2);
  --noora-alpha-pink: oklch(57.4% 0.218 7.8 / 0.24);
  --noora-alpha-black: oklch(0% 0 0 / 0.8);

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
  --noora-surface-overlay: light-dark(
    var(--noora-neutral-gray-24),
    var(--noora-neutral-gray-16)
  );

  /* Label */
  --noora-surface-label-primary: light-dark(
    var(--noora-neutral-light-1200),
    var(--noora-neutral-light-50)
  );
  --noora-surface-label-secondary: light-dark(
    var(--noora-neutral-light-1000),
    var(--noora-neutral-light-500)
  );
  --noora-surface-label-tertiary: light-dark(
    var(--noora-neutral-light-700),
    var(--noora-neutral-dark-500)
  );
  --noora-surface-label-destructive: light-dark(
    var(--noora-red-500),
    var(--noora-red-300)
  );
  --noora-surface-label-disabled: light-dark(
    var(--noora-neutral-light-600),
    var(--noora-neutral-dark-300)
  );

  /* Button */
  --noora-button-primary-background: var(--noora-purple-500);
  --noora-button-primary-label: var(--noora-neutral-light-50);
  --noora-button-primary-disabled-background: var(--noora-purple-300);
  --noora-button-primary-disabled-label: var(--noora-neutral-light-200);
  --noora-button-secondary-background: light-dark(
    var(--noora-neutral-light-50),
    var(--noora-neutral-dark-1100)
  );
  --noora-button-secondary-label: light-dark(
    var(--noora-neutral-light-1200),
    var(--noora-neutral-light-50)
  );
  --noora-button-secondary-disabled-background: light-dark(
    var(--noora-neutral-light-100),
    var(--noora-neutral-dark-1000)
  );
  --noora-button-neutral-background-hover: light-dark(
    var(--noora-neutral-light-200),
    var(--noora-neutral-dark-1000)
  );
  --noora-button-neutral-background-active: light-dark(
    var(--noora-neutral-light-300),
    var(--noora-neutral-dark-900)
  );
  --noora-button-secondary-disabled-label: light-dark(
    var(--noora-neutral-light-600),
    var(--noora-neutral-dark-600)
  );
  --noora-button-destructive-background: var(--noora-red-500);
  --noora-button-destructive-label: var(--noora-neutral-light-50);
  --noora-button-destructive-disabled-background: var(--noora-red-300);
  --noora-button-destructive-disabled-label: var(--noora-neutral-light-200);
  --noora-button-neutral-label: light-dark(
    var(--noora-neutral-light-1200),
    var(--noora-neutral-light-50)
  );
  --noora-button-neutral-disabled-label: light-dark(
    var(--noora-neutral-light-600),
    var(--noora-neutral-dark-600)
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
    var(--noora-button-secondary-disabled-background);

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
  --noora-button-background-primary-disabled:
    linear-gradient(
      180deg,
      light-dark(oklch(100% 0 0 / 0.16), oklch(32% 0.005 247.968 / 0.25)),
      light-dark(oklch(100% 0 0 / 0), oklch(32% 0.005 247.968 / 0.5))
    ),
    var(--noora-button-primary-disabled-background);
  --noora-button-border-primary:
    0px 1px 0px 0px oklch(100% 0 0 / 0.2) inset,
    0px 1px 1px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.05), oklch(16.2% 0 0 / 0.2)),
    0px 0px 0px 1px oklch(46.9% 0.27 286.9 / 0.9),
    0px 1px 3px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.16), oklch(0% 0 0 / 0.4));
  --noora-button-border-primary-hover:
    0px 1px 1px oklch(32% 0.005 247.968 / 0.12),
    0px 0px 0px 1px oklch(46.9% 0.27 286.9 / 0.9),
    0px 2px 3px oklch(32% 0.005 247.968 / 0.16),
    0px 1px 0px oklch(100% 0 0 / 0.1) inset;
  --noora-button-border-primary-focus:
    0px 0px 0px 1px
      light-dark(var(--noora-neutral-light-50), var(--noora-neutral-dark-1200)),
    0px 0px 0px 2.5px
      light-dark(var(--noora-purple-500), var(--noora-purple-400)),
    0px 1px 0px 0px oklch(100% 0 0 / 0.2) inset,
    0px 1px 1px 0px oklch(32% 0.005 247.968 / 0.12),
    0px 0px 0px 1px oklch(46.9% 0.27 286.9 / 0.9),
    0px 2px 3px 0px oklch(32% 0.005 247.968 / 0.16);
  --noora-button-border-primary-active:
    0px 0px 0px 1px oklch(46.9% 0.27 286.9 / 0.9),
    0px 1px 4px 0px light-dark(oklch(0% 0 0 / 0.3), oklch(0% 0 0 / 0.4)) inset;
  --noora-button-border-primary-disabled:
    0px 1px 0px 0px oklch(100% 0 0 / 0.2) inset,
    0px 1px 1px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.12), oklch(16.2% 0 0 / 0.2)),
    0px 0px 0px 1px oklch(46.9% 0.27 286.9 / 0.4),
    0px 2px 3px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.16), oklch(0% 0 0 / 0.4));

  --noora-button-background-secondary:
    linear-gradient(
      180deg,
      light-dark(oklch(78.4% 0.005 247.894 / 0), oklch(100% 0 0 / 0.04)),
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
  --noora-button-background-secondary-disabled:
    linear-gradient(
      180deg,
      light-dark(oklch(78.4% 0.005 247.894 / 0), oklch(100% 0 0 / 0.06)),
      light-dark(oklch(78.4% 0.005 247.894 / 0.08), oklch(100% 0 0 / 0))
    ),
    var(--noora-button-secondary-disabled-background);
  --noora-button-border-secondary:
    0px 1px 0px 0px light-dark(oklch(100% 0 0 / 0.9), oklch(100% 0 0 / 0.16))
      inset,
    0px 1px 1px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.05), oklch(16.2% 0 0 / 0.1)),
    0px 0px 0px 1px
      light-dark(oklch(32% 0.005 247.968 / 0.08), oklch(34.8% 0 0 / 0.9)),
    0px 2px 3px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.06), oklch(0% 0 0 / 0.5));
  --noora-button-border-secondary-disabled:
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
  --noora-button-border-secondary-focus:
    0px 0px 0px 1px
      light-dark(
        var(--noora-neutral-light-1000),
        var(--noora-neutral-dark-1200)
      ),
    0px 0px 0px 2.5px
      light-dark(oklch(32% 0.005 247.968 / 0.25), oklch(54.9% 0 0 / 0.8)),
    0px 1px 0px 0px light-dark(oklch(100% 0 0 / 0.9), oklch(100% 0 0 / 0.16))
      inset,
    0px 1px 1px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.05), oklch(16.2% 0 0 / 0.1)),
    0px 0px 0px 1px
      light-dark(oklch(32% 0.005 247.968 / 0.08), oklch(34.8% 0 0 / 0.9)),
    0px 2px 3px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.06), oklch(0% 0 0 / 0.5));
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
    0px 0px 0px 1px oklch(51.2% 0.201 30.7 / 0.8),
    0px 2px 3px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.16), oklch(0% 0 0 / 0.4));
  --noora-button-background-destructive-hover:
    linear-gradient(180deg, oklch(100% 0 0 / 0.24), oklch(100% 0 0 / 0)),
    var(--noora-button-destructive-background);
  --noora-button-border-destructive-hover:
    0px 1px 0px 0px oklch(100% 0 0 / 0.1) inset,
    0px 1px 1px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.12), oklch(16.2% 0 0 / 0.2)),
    0px 0px 0px 1px oklch(51.2% 0.201 30.7 / 0.8),
    0px 2px 3px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.16), oklch(0% 0 0 / 0.4));
  --noora-button-background-destructive-disabled:
    linear-gradient(
      180deg,
      light-dark(oklch(100% 0 0 / 0.06), oklch(32% 0.005 247.968 / 0.25)),
      light-dark(oklch(100% 0 0 / 0), oklch(32% 0.005 247.968 / 0.5))
    ),
    var(--noora-button-destructive-disabled-background);
  --noora-button-border-destructive-disabled:
    0px 1px 0px 0px oklch(100% 0 0 / 0.2) inset,
    0px 1px 1px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.12), oklch(16.2% 0 0 / 0.2)),
    0px 0px 0px 1px oklch(51.2% 0.201 30.7 / 0.5),
    0px 2px 3px 0px
      light-dark(oklch(32% 0.005 247.968 / 0.16), oklch(0% 0 0 / 0.4));
  --noora-button-border-destructive-active:
    0px 0px 0px 1px oklch(51.2% 0.201 30.7 / 0.8),
    0px 1px 4px 0px light-dark(oklch(0% 0 0 / 0.3), oklch(0% 0 0 / 0.4)) inset;
  --noora-button-border-destructive-focus:
    0px 0px 0px 1px
      light-dark(var(--noora-neutral-light-50), var(--noora-neutral-dark-1200)),
    0px 0px 0px 2.5px
      light-dark(oklch(58.7% 0.23 30.7 / 0.75), oklch(66.3% 0.224 30.7 / 0.8)),
    0px 1px 0px 0px oklch(100% 0 0 / 0.2) inset,
    0px 1px 1px 0px oklch(32% 0.005 247.968 / 0.12),
    0px 0px 0px 1px oklch(51.2% 0.201 30.7 / 0.8),
    0px 2px 3px 0px oklch(32% 0.005 247.968 / 0.16);

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
  --noora-badge-fill-label: light-dark(
    var(--noora-neutral-light-50),
    var(--noora-neutral-light-100)
  );
  --noora-badge-fill-neutral: light-dark(
    var(--noora-neutral-light-800),
    var(--noora-neutral-dark-600)
  );
  --noora-badge-fill-destructive: light-dark(
    var(--noora-red-500),
    var(--noora-red-700)
  );
  --noora-badge-fill-warning: light-dark(
    var(--noora-orange-500),
    var(--noora-orange-600)
  );
  --noora-badge-fill-attention: light-dark(
    var(--noora-yellow-600),
    var(--noora-yellow-600)
  );
  --noora-badge-fill-success: light-dark(
    var(--noora-green-500),
    var(--noora-green-600)
  );
  --noora-badge-fill-information: light-dark(
    var(--noora-azure-500),
    var(--noora-azure-700)
  );
  --noora-badge-fill-focus: light-dark(
    var(--noora-blue-500),
    var(--noora-blue-700)
  );
  --noora-badge-fill-primary: light-dark(
    var(--noora-purple-500),
    var(--noora-purple-700)
  );
  --noora-badge-fill-secondary: light-dark(
    var(--noora-pink-500),
    var(--noora-pink-700)
  );

  --noora-badge-light-fill-neutral-background: light-dark(
    var(--noora-neutral-light-300),
    var(--noora-neutral-gray-50)
  );
  --noora-badge-light-fill-neutral-label: light-dark(
    var(--noora-neutral-light-1100),
    var(--noora-neutral-light-100)
  );
  --noora-badge-light-fill-destructive-background: light-dark(
    var(--noora-red-50),
    var(--noora-alpha-red)
  );
  --noora-badge-light-fill-destructive-label: light-dark(
    var(--noora-red-600),
    var(--noora-red-400)
  );
  --noora-badge-light-fill-warning-background: light-dark(
    var(--noora-orange-50),
    var(--noora-alpha-orange)
  );
  --noora-badge-light-fill-warning-label: light-dark(
    var(--noora-orange-600),
    var(--noora-orange-400)
  );
  --noora-badge-light-fill-attention-background: light-dark(
    var(--noora-yellow-50),
    var(--noora-alpha-yellow)
  );
  --noora-badge-light-fill-attention-label: light-dark(
    var(--noora-yellow-700),
    var(--noora-yellow-400)
  );
  --noora-badge-light-fill-success-background: light-dark(
    var(--noora-green-50),
    var(--noora-alpha-green)
  );
  --noora-badge-light-fill-success-label: light-dark(
    var(--noora-green-700),
    var(--noora-green-400)
  );
  --noora-badge-light-fill-information-background: light-dark(
    var(--noora-azure-50),
    var(--noora-alpha-azure)
  );
  --noora-badge-light-fill-information-label: light-dark(
    var(--noora-azure-700),
    var(--noora-azure-400)
  );
  --noora-badge-light-fill-focus-background: light-dark(
    var(--noora-blue-50),
    var(--noora-alpha-blue)
  );
  --noora-badge-light-fill-focus-label: light-dark(
    var(--noora-blue-700),
    var(--noora-blue-400)
  );
  --noora-badge-light-fill-primary-background: light-dark(
    var(--noora-purple-50),
    var(--noora-alpha-purple)
  );
  --noora-badge-light-fill-primary-label: light-dark(
    var(--noora-purple-700),
    var(--noora-purple-400)
  );
  --noora-badge-light-fill-secondary-background: light-dark(
    var(--noora-pink-50),
    var(--noora-alpha-pink)
  );
  --noora-badge-light-fill-secondary-label: light-dark(
    var(--noora-pink-600),
    var(--noora-pink-400)
  );

  --noora-badge-disabled-background: light-dark(
    var(--noora-neutral-light-200),
    var(--noora-neutral-light-1000)
  );
  --noora-badge-disabled-label: light-dark(
    var(--noora-neutral-light-600),
    var(--noora-neutral-light-300)
  );

  --noora-badge-status-success: var(--noora-green-600);
  --noora-badge-status-warning: var(--noora-orange-600);
  --noora-badge-status-error: light-dark(
    var(--noora-red-500),
    var(--noora-red-600)
  );
  --noora-badge-status-attention: light-dark(
    var(--noora-yellow-600),
    var(--noora-yellow-500)
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
  --noora-light-border-default:
    0px 1px 1px 0px oklch(16.2% 0 0 / 0.05),
    0px 0px 0px 1px oklch(32% 0.005 247.968 / 0.08),
    0px 1px 1px 0px oklch(32% 0.005 247.968 / 0.1);

  --noora-light-border-focus:
    0px 1px 1px 0px oklch(16.2% 0 0 / 0.05),
    0px 0px 0px 1px oklch(32% 0.005 247.968 / 0.08),
    0px 1px 3px 0px oklch(32% 0.005 247.968 / 0.1),
    0px 0px 0px 3px oklch(32% 0.005 247.968 / 0.12);

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
    0px 0px 0px 1px oklch(37.5% 0.27 286.9 / 0.9),
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
    var(--noora-orange-600),
    var(--noora-orange-400)
  );
  --noora-chart-legend-primary: light-dark(
    var(--noora-purple-500),
    var(--noora-purple-400)
  );
  --noora-chart-legend-primary-translucent: light-dark(
    var(--noora-purple-100),
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
  --noora-sunburst-localizations: var(--noora-orange-500);
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
    var(--noora-alpha-red)
  );
  --noora-icon-destructive-label: light-dark(
    var(--noora-red-600),
    var(--noora-red-500)
  );
  --noora-icon-warning-background: light-dark(
    var(--noora-orange-50),
    var(--noora-alpha-orange)
  );
  --noora-icon-warning-label: light-dark(
    var(--noora-orange-600),
    var(--noora-orange-500)
  );
  --noora-icon-success-background: light-dark(
    var(--noora-green-50),
    var(--noora-alpha-green)
  );
  --noora-icon-success-label: light-dark(
    var(--noora-green-700),
    var(--noora-green-500)
  );
  --noora-icon-info-background: light-dark(
    var(--noora-azure-50),
    var(--noora-alpha-azure)
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

  --noora-border-light-default:
    0px 1px 1px 0px oklch(16.2% 0 0 / 0.05),
    0px 0px 0px 1px oklch(32% 0.005 247.968 / 0.08),
    0px 1px 1px 0px oklch(32% 0.005 247.968 / 0.1);
  --noora-border-light-focus:
    0px 1px 1px 0px oklch(16.2% 0 0 / 0.05),
    0px 0px 0px 1px oklch(32% 0.005 247.968 / 0.08),
    0px 1px 3px 0px oklch(32% 0.005 247.968 / 0.1),
    0px 0px 0px 3px oklch(32% 0.005 247.968 / 0.12);
  --noora-border-light-error:
    0px 1px 1px 0px oklch(16.2% 0 0 / 0.05),
    0px 0px 0px 1px oklch(58.7% 0.23 30.7),
    0px 1px 3px 0px oklch(32% 0.005 247.968 / 0.1);
  --noora-border-light-error-focus:
    0px 1px 1px 0px oklch(16.2% 0 0 / 0.05),
    0px 0px 0px 1px oklch(58.7% 0.23 30.7),
    0px 1px 3px 0px oklch(32% 0.005 247.968 / 0.1),
    0px 0px 0px 3px oklch(58.7% 0.23 30.7 / 0.2);
  --noora-border-light-warning-focus:
    0px 1px 1px 0px oklch(16.2% 0 0 / 0.05),
    0px 0px 0px 1px oklch(71.9% 0.185 48.7),
    0px 1px 3px 0px oklch(32% 0.005 247.968 / 0.1),
    0px 0px 0px 3px oklch(71.9% 0.185 48.7 / 0.2);

  --noora-border-medium:
    0px 0px 0px 1px oklch(32% 0.005 247.968 / 0.08) inset,
    0px -1px 0px 0px oklch(32% 0.005 247.968 / 0.16) inset,
    0px 8px 6px 0px oklch(32% 0.005 247.968 / 0.02),
    0px 2px 4px 0px oklch(32% 0.005 247.968 / 0.04);
  --noora-border-section: 0 0 0 1px oklch(32% 0.005 247.968 / 0.06);
  --noora-border-heavy:
    0px 0px 0px 1.5px oklch(32% 0.005 247.968 / 0.1) inset,
    0px -1.5px 0px 0px oklch(32% 0.005 247.968 / 0.12) inset,
    0px 4px 8px 0px oklch(32% 0.005 247.968 / 0.08),
    0px 2px 4px 0px oklch(32% 0.005 247.968 / 0.04);

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
  --noora-font-heading: "Inter Variable", "Noto Sans Georgian", sans-serif;
  --noora-font-body: "Inter Variable", "Noto Sans Georgian", sans-serif;
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
      0px 0px 0px 1px oklch(46.9% 0.27 286.9 / 0.9),
      0px 2px 3px 0px oklch(0% 0 0 / 0.4);
    --noora-button-border-secondary-hover:
      0px 1px 0px 0px oklch(100% 0 0 / 0.24) inset,
      0px 1px 1px 0px oklch(16.2% 0 0 / 0.1),
      0px 0px 0px 1px oklch(34.8% 0 0 / 0.9),
      0px 2px 3px 0px oklch(0% 0 0 / 0.5);
  }

  &[data-theme="dark"] {
    --noora-light-border-default:
      0px 1px 1px 0px oklch(16.2% 0 0 / 0.3),
      0px 0px 0px 1px oklch(54.9% 0 0 / 0.45),
      0px 2px 3px 0px oklch(0% 0 0 / 0.3);

    --noora-light-border-focus:
      0px 1px 1px 0px oklch(16.2% 0 0 / 0.2),
      0px 0px 0px 1px oklch(54.9% 0 0 / 0.3),
      0px 2px 3px 0px oklch(0% 0 0 / 0.3),
      0px 0px 0px 3px oklch(54.9% 0 0 / 0.4);
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
    --noora-border-light-default:
      0px 1px 1px 0px oklch(16.2% 0 0 / 0.3),
      0px 0px 0px 1px oklch(54.9% 0 0 / 0.45),
      0px 2px 3px 0px oklch(0% 0 0 / 0.3);
    --noora-border-light-focus:
      0px 1px 1px 0px oklch(16.2% 0 0 / 0.2),
      0px 0px 0px 1px oklch(54.9% 0 0 / 0.3),
      0px 2px 3px 0px oklch(0% 0 0 / 0.3),
      0px 0px 0px 3px oklch(54.9% 0 0 / 0.4);
    --noora-border-light-error:
      0px 1px 1px 0px oklch(16.2% 0 0 / 0.2),
      0px 0px 0px 1px oklch(74% 0.159 30.9), 0px 2px 3px 0px oklch(0% 0 0 / 0.3);
    --noora-border-light-error-focus:
      0px 1px 1px 0px oklch(16.2% 0 0 / 0.2),
      0px 0px 0px 1px oklch(74% 0.159 30.9),
      0px 2px 3px 0px oklch(0% 0 0 / 0.3),
      0px 0px 0px 3px oklch(74% 0.159 30.9 / 0.25);
    --noora-border-light-warning-focus:
      0px 1px 1px 0px oklch(16.2% 0 0 / 0.2),
      0px 0px 0px 1px oklch(82% 0.111 48.6),
      0px 2px 3px 0px oklch(0% 0 0 / 0.3),
      0px 0px 0px 3px oklch(82% 0.111 48.6 / 0.25);
    --noora-border-medium:
      0px 1px 0px 0px oklch(54.9% 0 0 / 0.3) inset,
      0px 0px 0px 1px oklch(54.9% 0 0 / 0.2) inset,
      0px 2px 4px 0px oklch(0% 0 0 / 0.12), 0px 4px 8px 0px oklch(0% 0 0 / 0.24);
    --noora-border-section: 0 0 0 1px oklch(34.8% 0 0 / 0.55);
    --noora-border-heavy:
      0px 1.5px 0px 0px oklch(54.9% 0 0 / 0.3) inset,
      0px 0px 0px 1.5px oklch(54.9% 0 0 / 0.2) inset,
      0px 4px 8px 0px oklch(0% 0 0 / 0.16), 0px 2px 4px 0px oklch(0% 0 0 / 0.24);
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
    var(--noora-orange-400)
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

  --ease-in-out-quad: cubic-bezier(0.455, 0.03, 0.515, 0.955);
  --ease-in-out-cubic: cubic-bezier(0.645, 0.045, 0.355, 1);
  --ease-in-out-quart: cubic-bezier(0.77, 0, 0.175, 1);
  --ease-in-out-quint: cubic-bezier(0.86, 0, 0.07, 1);
  --ease-in-out-expo: cubic-bezier(1, 0, 0, 1);
  --ease-in-out-circ: cubic-bezier(0.785, 0.135, 0.15, 0.86);
}

/* Dark mode for Storybook only */
.noora-dark {
  color-scheme: dark;
}

/* alert.css */
.noora-alert {
  --noora-alert-error-icon: var(--noora-red-500);
  --noora-alert-error-secondary-background: light-dark(
    var(--noora-red-50),
    var(--noora-alpha-red)
  );
  --noora-alert-success-icon: var(--noora-green-600);
  --noora-alert-success-secondary-background: light-dark(
    var(--noora-green-50),
    var(--noora-alpha-green)
  );
  --noora-alert-warning-icon: var(--noora-orange-600);
  --noora-alert-warning-secondary-background: light-dark(
    var(--noora-orange-50),
    var(--noora-alpha-orange)
  );
  --noora-alert-information-icon: var(--noora-azure-500);
  --noora-alert-information-secondary-background: light-dark(
    var(--noora-azure-50),
    var(--noora-alpha-azure)
  );
  display: flex;

  border-radius: var(--noora-radius-4);

  & > [data-part="title"] {
    color: var(--noora-surface-label-primary);
  }

  & [data-part="description"] {
    margin-top: var(--noora-spacing-2);
    color: var(--noora-surface-label-secondary);
    font: var(--noora-font-body-medium);
  }

  & [data-part="dismiss-icon"] {
    flex-shrink: 0;
  }

  &[data-type="primary"] {
    box-shadow: var(--noora-border-medium);
    background: var(--noora-surface-background-primary);
  }

  &[data-type="secondary"] {
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

  &[data-size="small"],
  &[data-size="medium"] {
    & > [data-part="actions"] {
      display: flex;
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

    & [data-part="title"] {
      font: var(--noora-font-body-small);
    }
  }

  &[data-size="medium"] {
    gap: var(--noora-spacing-5);
    padding: var(--noora-spacing-4) var(--noora-spacing-5);

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

    & [data-part="title"] {
      font: var(--noora-font-body-medium);
    }
  }

  &[data-size="large"] {
    gap: var(--noora-spacing-6);
    padding: var(--noora-spacing-6);

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
      }
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
    padding-left: var(--noora-spacing-2);
  }

  &[data-dot] {
    padding-left: var(--noora-spacing-0);
  }

  &[data-icon-only] {
    padding: var(--noora-spacing-1);
  }

  &[data-size="small"] {
    font: var(--noora-font-weight-medium) var(--noora-font-body-xsmall);

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

  &[data-size="large"] {
    font: var(--noora-font-weight-medium) var(--noora-font-body-small);

    &[data-icon] {
      gap: var(--noora-spacing-2);
    }

    &[data-icon-only] {
      padding: var(--noora-spacing-2);
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
    color: var(--noora-badge-fill-label);

    &[data-color="neutral"] {
      background: var(--noora-badge-fill-neutral);
    }

    &[data-color="destructive"] {
      background: var(--noora-badge-fill-destructive);
    }

    &[data-color="warning"] {
      background: var(--noora-badge-fill-warning);
    }

    &[data-color="attention"] {
      background: var(--noora-badge-fill-attention);
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

  &[data-style="light-fill"] {
    &[data-color="neutral"] {
      background: var(--noora-badge-light-fill-neutral-background);
      color: var(--noora-badge-light-fill-neutral-label);
      box-shadow: 0 0 0 1px
        light-dark(
          color-mix(in oklch, var(--noora-neutral-light-1100) 40%, transparent),
          color-mix(in oklch, var(--noora-neutral-light-100) 20%, transparent)
        );
    }

    &[data-color="destructive"] {
      background: var(--noora-badge-light-fill-destructive-background);
      color: var(--noora-badge-light-fill-destructive-label);
      box-shadow: 0 0 0 1px
        color-mix(
          in oklch,
          var(--noora-badge-light-fill-destructive-label) 40%,
          transparent
        );
    }

    &[data-color="warning"] {
      background: var(--noora-badge-light-fill-warning-background);
      color: var(--noora-badge-light-fill-warning-label);
      box-shadow: 0 0 0 1px
        color-mix(
          in oklch,
          var(--noora-badge-light-fill-warning-label) 40%,
          transparent
        );
    }

    &[data-color="attention"] {
      background: var(--noora-badge-light-fill-attention-background);
      color: var(--noora-badge-light-fill-attention-label);
      box-shadow: 0 0 0 1px
        color-mix(
          in oklch,
          var(--noora-badge-light-fill-attention-label) 40%,
          transparent
        );
    }

    &[data-color="success"] {
      background: var(--noora-badge-light-fill-success-background);
      color: var(--noora-badge-light-fill-success-label);
      box-shadow: 0 0 0 1px
        color-mix(
          in oklch,
          var(--noora-badge-light-fill-success-label) 40%,
          transparent
        );
    }

    &[data-color="information"] {
      background: var(--noora-badge-light-fill-information-background);
      color: var(--noora-badge-light-fill-information-label);
      box-shadow: 0 0 0 1px
        color-mix(
          in oklch,
          var(--noora-badge-light-fill-information-label) 40%,
          transparent
        );
    }

    &[data-color="focus"] {
      background: var(--noora-badge-light-fill-focus-background);
      color: var(--noora-badge-light-fill-focus-label);
      box-shadow: 0 0 0 1px
        color-mix(
          in oklch,
          var(--noora-badge-light-fill-focus-label) 40%,
          transparent
        );
    }

    &[data-color="primary"] {
      background: var(--noora-badge-light-fill-primary-background);
      color: var(--noora-badge-light-fill-primary-label);
      box-shadow: 0 0 0 1px
        color-mix(
          in oklch,
          var(--noora-badge-light-fill-primary-label) 40%,
          transparent
        );
    }

    &[data-color="secondary"] {
      background: var(--noora-badge-light-fill-secondary-background);
      color: var(--noora-badge-light-fill-secondary-label);
      box-shadow: 0 0 0 1px
        color-mix(
          in oklch,
          var(--noora-badge-light-fill-secondary-label) 40%,
          transparent
        );
    }
  }
}

.noora-status-badge {
  display: inline-flex;
  justify-content: center;
  align-items: center;
  gap: var(--noora-spacing-2);
  box-shadow: var(--noora-border-light-default);
  border-radius: var(--noora-radius-3);
  background: var(--noora-surface-background-primary);
  padding: var(--noora-spacing-2) var(--noora-spacing-4) var(--noora-spacing-2)
    var(--noora-spacing-2);

  & [data-part="icon"] {
    display: inline-flex;
    justify-content: center;
    align-items: center;

    & svg {
      width: var(--noora-icon-size-medium);
      height: var(--noora-icon-size-medium);
    }
  }

  & [data-part="label"] {
    font: var(--noora-font-weight-medium) var(--noora-font-body-small);
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
}

/* button.css */
.noora-button,
.noora-link-button,
.noora-neutral-button {
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
  --noora-button-icon-size: var(--noora-icon-size-large);

  cursor: pointer;
  outline: unset;
  transition: transform 150ms var(--ease-out-cubic);
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

  &[data-variant="primary"] {
    box-shadow: var(--noora-button-border-primary);
    background: var(--noora-button-background-primary);
    color: var(--noora-button-primary-label);

    &:hover {
      box-shadow: var(--noora-button-border-primary-hover);
      background: var(--noora-button-background-primary-hover);
    }

    &:focus-visible {
      box-shadow: var(--noora-button-border-primary-focus);
    }

    &[disabled] {
      box-shadow: var(--noora-button-border-primary-disabled);
      background: var(--noora-button-background-primary-disabled);
      color: var(--noora-button-primary-disabled-label);
    }

    &:not(:disabled):active {
      box-shadow: var(--noora-button-border-primary-active);
      background: var(--noora-button-background-primary-active);
    }
  }

  &[data-variant="secondary"] {
    box-shadow: var(--noora-button-border-secondary);
    background: var(--noora-button-background-secondary);
    color: var(--noora-button-secondary-label);

    &:hover {
      background: var(--noora-button-background-secondary-hover);
    }

    &:focus-visible {
      box-shadow: var(--noora-button-border-secondary-focus);
    }

    &[disabled] {
      box-shadow: var(--noora-button-border-secondary-disabled);
      background: var(--noora-button-background-secondary-disabled);
      color: var(--noora-button-secondary-disabled-label);
    }

    &:not(:disabled):active {
      box-shadow: var(--noora-button-border-secondary-active);
      background: var(--noora-button-background-secondary-active);
    }
  }

  &[data-variant="destructive"] {
    box-shadow: var(--noora-button-border-destructive);
    background: var(--noora-button-background-destructive);

    color: var(--noora-button-destructive-label);

    &:hover {
      box-shadow: var(--noora-button-border-destructive-hover);
      background: var(--noora-button-background-destructive-hover);
    }

    &:focus-visible {
      box-shadow: var(--noora-button-border-destructive-focus);
    }

    &[disabled] {
      box-shadow: var(--noora-button-border-destructive-disabled);
      background: var(--noora-button-background-destructive-disabled);
      color: var(--noora-button-destructive-disabled-label);
    }

    &:not(:disabled):active {
      box-shadow: var(--noora-button-border-destructive-active);
      background: var(--noora-button-destructive-background);
    }
  }

  &[data-icon-only] {
    padding: var(--noora-spacing-3);
  }

  &[data-size="small"] {
    --noora-button-icon-size: var(--noora-icon-size-small);

    font: var(--noora-font-weight-medium) var(--noora-font-body-xsmall);

    &:not([data-icon-only]) {
      padding: var(--noora-spacing-3) var(--noora-spacing-2);
    }

    & svg {
      width: var(--noora-button-icon-size);
      height: var(--noora-button-icon-size);
    }
  }

  &[data-size="medium"],
  &[data-size="large"] {
    &:not([data-icon-only]) {
      padding: var(--noora-spacing-3);
    }
  }

  &[data-size="medium"] {
    --noora-button-icon-size: var(--noora-icon-size-medium);

    font: var(--noora-font-weight-medium) var(--noora-font-body-small);

    & svg {
      width: var(--noora-button-icon-size);
      height: var(--noora-button-icon-size);
    }
  }

  &[data-size="large"] {
    --noora-button-icon-size: var(--noora-icon-size-large);

    font: var(--noora-font-weight-medium) var(--noora-font-body-medium);

    & svg {
      width: var(--noora-button-icon-size);
      height: var(--noora-button-icon-size);
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
    outline: 2px solid currentColor;
    outline-offset: 2px;
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

  &[data-size="large"] {
    font: var(--noora-font-weight-medium) var(--noora-font-body-medium);

    & svg {
      width: var(--noora-icon-size-large);
      height: var(--noora-icon-size-large);
    }
  }
}

.noora-neutral-button {
  cursor: pointer;
  border-radius: var(--noora-radius-3);
  background: unset;
  padding: var(--noora-spacing-3);
  color: var(--noora-button-neutral-label);
  transition: transform 150ms var(--ease-out-cubic);

  &:not(:disabled):hover {
    background: var(--noora-button-neutral-background-hover);
  }

  &:not(:disabled):active {
    background: var(--noora-button-neutral-background-active);
    transform: scale(0.97);
  }

  &[disabled] {
    cursor: not-allowed;
    color: var(--noora-button-neutral-disabled-label);
  }

  &[data-size="large"] {
    & > svg {
      width: var(--noora-icon-size-large);
      height: var(--noora-icon-size-large);
    }
  }

  &[data-size="medium"] {
    & > svg {
      width: var(--noora-icon-size-medium);
      height: var(--noora-icon-size-medium);
    }
  }

  &[data-size="small"] {
    & > svg {
      width: var(--noora-icon-size-small);
      height: var(--noora-icon-size-small);
    }
  }
}

@media (prefers-reduced-motion: reduce) {
  .noora-button,
  .noora-neutral-button {
    transition: none;

    &:not(:disabled):active {
      transform: none;
    }
  }
}

/* button_group.css */
.noora-button-group {
  --noora-button-group-background: light-dark(
    var(--noora-neutral-light-50),
    var(--noora-neutral-dark-1200)
  );
  --noora-button-group-label: light-dark(
    var(--noora-neutral-light-1000),
    var(--noora-neutral-light-50)
  );
  --noora-button-group-hover-background: light-dark(
    var(--noora-neutral-light-100),
    var(--noora-neutral-dark-1100)
  );
  --noora-button-group-hover-label: light-dark(
    var(--noora-neutral-light-1100),
    var(--noora-neutral-light-100)
  );
  --noora-button-group-active-background: light-dark(
    var(--noora-neutral-light-200),
    var(--noora-neutral-dark-1000)
  );
  --noora-button-group-active-label: light-dark(
    var(--noora-neutral-light-1200),
    var(--noora-neutral-light-50)
  );
  --noora-button-group-disabled-background: light-dark(
    var(--noora-neutral-light-100),
    var(--noora-neutral-dark-1000)
  );
  --noora-button-group-disabled-label: light-dark(
    var(--noora-neutral-light-600),
    var(--noora-neutral-dark-600)
  );
  display: flex;
  flex-direction: row;
  align-items: center;

  box-shadow: var(--noora-border-light-default);
  border-radius: var(--noora-radius-3);
  background-color: var(--noora-button-group-background);
  padding: var(--noora-spacing-1);
  overflow: hidden;

  &[data-size="small"] {
    gap: var(--noora-spacing-1);
  }
  &[data-size="medium"],
  &[data-size="large"] {
    gap: var(--noora-spacing-2);
  }
}

.noora-button-group-item {
  --noora-border-button-group:
    inset 0px 2px 2px 0px oklch(32% 0.005 247.968 / 0.06),
    inset 0px 1px 1px 0px oklch(32% 0.005 247.968 / 0.08);
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: var(--noora-spacing-1);
  cursor: pointer;
  outline: unset;
  border: unset;
  border-radius: var(--noora-radius-2);

  background-color: unset;
  overflow: hidden;
  color: var(--noora-button-group-label);
  font: var(--noora-font-weight-medium) var(--noora-font-body-medium);
  user-select: none;
  text-decoration: unset;

  html[data-theme="dark"] & {
    --noora-border-button-group:
      inset 0px 3px 3px 0px oklch(0% 0 0 / 0.3),
      inset 0px 1px 1px 0px oklch(0% 0 0 / 0.3);
  }

  &:hover {
    background-color: var(--noora-button-group-hover-background);
    color: var(--noora-button-group-hover-label);
  }

  &:active,
  &[data-selected] {
    box-shadow: var(--noora-border-button-group);
    background-color: var(--noora-button-group-active-background);
    color: var(--noora-button-group-active-label);
  }

  &:disabled {
    cursor: not-allowed;
    background: var(--noora-button-group-disabled-background) !important;
    color: var(--noora-button-group-disabled-label) !important;
  }

  & > [data-part="label"] {
    padding: var(--noora-spacing-0) var(--noora-spacing-2);
  }

  .noora-button-group[data-size="small"] & {
    padding: var(--noora-spacing-3) var(--noora-spacing-4);
    font: var(--noora-font-weight-medium) var(--noora-font-body-xsmall);

    & svg {
      width: var(--noora-icon-size-small);
      height: var(--noora-icon-size-small);
    }
  }

  .noora-button-group[data-size="medium"] & {
    gap: var(--noora-spacing-1);
    padding: var(--noora-spacing-2) var(--noora-spacing-2);
    font: var(--noora-font-weight-medium) var(--noora-font-body-small);

    & > [data-part="label"] {
      padding: var(--noora-spacing-0) var(--noora-spacing-2);
    }

    & svg {
      width: var(--noora-icon-size-medium);
      height: var(--noora-icon-size-medium);
    }
  }

  .noora-button-group[data-size="large"] & {
    padding: var(--noora-spacing-2) var(--noora-spacing-4);
    font: var(--noora-font-weight-medium) var(--noora-font-body-medium);

    & svg {
      width: var(--noora-icon-size-large);
      height: var(--noora-icon-size-large);
    }
  }
}

/* line_divider.css */
.noora-line-divider {
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
  }
}
`;
