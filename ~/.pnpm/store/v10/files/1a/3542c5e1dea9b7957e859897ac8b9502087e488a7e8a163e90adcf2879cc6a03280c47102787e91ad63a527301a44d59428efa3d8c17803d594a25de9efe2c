/**
 * Dependency-less debounce function with max wait
 * derived from @url https://dev.to/cantem/how-to-write-a-debounce-function-1bdf
 *
 * @param fn - any function to debounce
 * @param wait - time in ms to wait after function call to invoke function
 * @param {number} maxWait - time in ms to wait after function call to invoke function even if it's still being called
 */
function debounce(fn, wait, { maxWait } = {}) {
    let timer = null;
    let maxTimer = null;
    return function (...args) {
        if (timer)
            clearTimeout(timer);
        timer = setTimeout(() => {
            maxTimer !== null ? clearTimeout(maxTimer) : null;
            maxTimer = null;
            fn.apply(this, args);
        }, wait);
        if (maxWait && !maxTimer)
            maxTimer = setTimeout(() => {
                timer !== null ? clearTimeout(timer) : null;
                maxTimer = null;
                fn.apply(this, args);
            }, maxWait);
    };
}

export { debounce };
