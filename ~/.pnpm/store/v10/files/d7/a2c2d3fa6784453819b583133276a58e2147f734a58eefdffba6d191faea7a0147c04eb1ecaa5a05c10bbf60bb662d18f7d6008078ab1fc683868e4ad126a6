/**
 * Check for duplicate titles, and iterate title
 */
const iterateTitle = (title, checkDuplicates, separator = ' #') => {
    // If the title is not a duplicate return
    if (!checkDuplicates(title))
        return title;
    const split = title.split(separator);
    const newTitle = split.length > 1
        ? `${split.slice(0, -1).join()}${separator}${Number(split.at(-1)) + 1}`
        : `${split.join()}${separator}2`;
    return iterateTitle(newTitle, checkDuplicates, separator);
};

export { iterateTitle };
