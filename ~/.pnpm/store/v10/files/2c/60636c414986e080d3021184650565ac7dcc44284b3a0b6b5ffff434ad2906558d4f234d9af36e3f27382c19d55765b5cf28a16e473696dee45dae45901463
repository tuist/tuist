/** Date sorting for arrays */
function timeSort(a, b, key) {
    const valA = ((key ? a[key] : a) ?? '');
    const valB = ((key ? b[key] : b) ?? '');
    return new Date(valA).getTime() - new Date(valB).getTime();
}
/** Sort alphanumerically */
function alphaSort(a, b, key) {
    const valA = String((key ? a[key] : a) ?? '');
    const valB = String((key ? b[key] : b) ?? '');
    return valA.localeCompare(valB);
}
/**
 * Immutably sorts a list by another list with O(n) time
 * Returns a sorted copy with any unsorted items at the end of list
 */
function sortByOrder(arr, order, idKey) {
    // Map the order to keep a single lookup table
    const orderMap = {};
    order.forEach((e, idx) => (orderMap[e] = idx));
    const sorted = [];
    const untagged = [];
    arr.forEach((e) => {
        const sortedIdx = orderMap[e[idKey]] ?? -1;
        if (sortedIdx >= 0) {
            sorted[sortedIdx] = e;
        }
        else {
            untagged.push(e);
        }
    });
    return sorted.concat(...untagged);
}

export { alphaSort, sortByOrder, timeSort };
