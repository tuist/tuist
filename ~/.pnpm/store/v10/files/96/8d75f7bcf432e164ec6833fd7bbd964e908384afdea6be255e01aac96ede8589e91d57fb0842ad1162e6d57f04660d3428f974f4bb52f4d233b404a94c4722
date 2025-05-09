import tippy from 'tippy.js';
import { shallowRef, ref, watchEffect } from 'vue';
import { isMacOS } from './isMacOS.js';

/**
 * A Vue hook to use a tooltip for a specific element.
 */
function useTooltip(props = {}) {
    const elementRef = shallowRef(null);
    const tooltip = ref(null);
    watchEffect(() => {
        tooltip.value?.destroy();
        if (elementRef.value && props.content) {
            tooltip.value = tippy(elementRef.value, {
                allowHTML: true,
                theme: 'app-tooltip',
                arrow: false,
                delay: 400,
                duration: [100, 200],
                offset: [0, 5],
                placement: 'top',
                ...props,
            });
        }
    });
    return elementRef;
}
/** Mocked tagged template string to support lit-html syntax highlighting */
function html(strings, ...values) {
    let str = '';
    strings.forEach((string, i) => {
        str += string + (values[i] || '');
    });
    return str;
}
/** Mocked tagged template string to support lit-html syntax highlighting */
function css(strings, ...values) {
    let str = '';
    strings.forEach((string, i) => {
        str += string + (values[i] || '');
    });
    return str;
}
/** Tooltip content for keyboard shortcuts */
function keyboardShortcutTooltip(keys, title) {
    // 'mod+b' -> 'command+b'/'control+b' (depending on the OS)
    const differentKeyboardShortcutsForMacOS = (k) => k
        .split('+')
        .map((key) => {
        if (key === 'mod') {
            if (isMacOS()) {
                return 'command';
            }
            return 'ctrl';
        }
        return key;
    })
        .join('+');
    // 'command+b' -> '⌘B'
    const formattedKeyboardShortcuts = (k) => differentKeyboardShortcutsForMacOS(k)
        .split('+')
        .map((key) => {
        const keyMap = {
            escape: 'ESC',
            command: '⌘',
            shift: '⇧',
            ctrl: '⌃',
            alt: '⌥',
        };
        // command -> ⌘
        if (key in keyMap) {
            return keyMap[key];
        }
        // b -> B
        return key.charAt(0).toUpperCase() + key.slice(1);
    });
    const formattedKeys = formattedKeyboardShortcuts(keys);
    const itemStyle = css `
    border: 1px solid var(--background-2);
    padding: 2px;
    display: inline-block;
    background: rgba(255, 255, 255, 0.2);
    border-radius: 2px;
    min-width: 20px;
    text-align: center;
  `;
    const item = (val = '') => html `<span style="${itemStyle}">${val}</span>`;
    const titleElement = title ? html `<span style="margin: 0 6px 0 3px">${title}</span>` : '';
    return html `
    <div style="display: flex; align-items: center">
      ${titleElement}
      <div style="display: flex; gap: 3px">
        ${formattedKeys.map((k) => item(k)).join('')}
      </div>
    </div>
  `;
}

export { keyboardShortcutTooltip, useTooltip };
