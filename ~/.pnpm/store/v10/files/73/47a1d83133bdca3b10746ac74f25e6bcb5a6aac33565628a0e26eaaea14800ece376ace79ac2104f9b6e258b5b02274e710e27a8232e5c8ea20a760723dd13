'use strict';

var utils = require('@zag-js/utils');

var __defProp = Object.defineProperty;
var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
var __publicField = (obj, key, value) => __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);
var fallback = {
  itemToValue(item) {
    if (typeof item === "string") return item;
    if (utils.isObject(item) && utils.hasProp(item, "value")) return item.value;
    return "";
  },
  itemToString(item) {
    if (typeof item === "string") return item;
    if (utils.isObject(item) && utils.hasProp(item, "label")) return item.label;
    return fallback.itemToValue(item);
  },
  isItemDisabled(item) {
    if (utils.isObject(item) && utils.hasProp(item, "disabled")) return !!item.disabled;
    return false;
  }
};
var ListCollection = class _ListCollection {
  constructor(options) {
    this.options = options;
    /**
     * The items in the collection
     */
    __publicField(this, "items");
    __publicField(this, "copy", (items) => {
      return new _ListCollection({ ...this.options, items: items ?? [...this.items] });
    });
    __publicField(this, "isEqual", (other) => {
      return utils.isEqual(this.items, other.items);
    });
    /**
     * Function to update the collection items
     */
    __publicField(this, "setItems", (items) => {
      return this.copy(items);
    });
    /**
     * Returns all the values in the collection
     */
    __publicField(this, "getValues", (items = this.items) => {
      return Array.from(items).map((item) => this.getItemValue(item)).filter(Boolean);
    });
    /**
     * Get the item based on its value
     */
    __publicField(this, "find", (value) => {
      if (value == null) return null;
      const index = this.items.findIndex((item) => this.getItemValue(item) === value);
      return index != null ? this.items[index] : null;
    });
    /**
     * Get the items based on its values
     */
    __publicField(this, "findMany", (values) => {
      return Array.from(values).map((value) => this.find(value)).filter((item) => item != null);
    });
    /**
     * Get the item based on its index
     */
    __publicField(this, "at", (index) => {
      return this.items[index] ?? null;
    });
    __publicField(this, "sortFn", (valueA, valueB) => {
      const indexA = this.indexOf(valueA);
      const indexB = this.indexOf(valueB);
      return (indexA ?? 0) - (indexB ?? 0);
    });
    /**
     * Sort the values based on their index
     */
    __publicField(this, "sort", (values) => {
      return [...values].sort(this.sortFn.bind(this));
    });
    /**
     * Convert an item to a value
     */
    __publicField(this, "getItemValue", (item) => {
      if (item == null) return null;
      return this.options.itemToValue?.(item) ?? fallback.itemToValue(item);
    });
    /**
     * Whether an item is disabled
     */
    __publicField(this, "getItemDisabled", (item) => {
      if (item == null) return false;
      return this.options.isItemDisabled?.(item) ?? fallback.isItemDisabled(item);
    });
    /**
     * Convert an item to a string
     */
    __publicField(this, "stringifyItem", (item) => {
      if (item == null) return null;
      return this.options.itemToString?.(item) ?? fallback.itemToString(item);
    });
    /**
     * Convert a value to a string
     */
    __publicField(this, "stringify", (value) => {
      if (value == null) return null;
      return this.stringifyItem(this.find(value));
    });
    /**
     * Convert an array of items to a string
     */
    __publicField(this, "stringifyItems", (items, separator = ", ") => {
      return Array.from(items).map((item) => this.stringifyItem(item)).filter(Boolean).join(separator);
    });
    /**
     * Convert an array of items to a string
     */
    __publicField(this, "stringifyMany", (value, separator) => {
      return this.stringifyItems(this.findMany(value), separator);
    });
    /**
     * Whether the collection has a value
     */
    __publicField(this, "has", (value) => {
      return this.indexOf(value) !== -1;
    });
    /**
     * Whether the collection has an item
     */
    __publicField(this, "hasItem", (item) => {
      if (item == null) return false;
      return this.has(this.getItemValue(item));
    });
    /**
     * Returns the next value in the collection
     */
    __publicField(this, "getNextValue", (value, step = 1, clamp = false) => {
      let index = this.indexOf(value);
      if (index === -1) return null;
      index = clamp ? Math.min(index + step, this.size - 1) : index + step;
      while (index <= this.size && this.getItemDisabled(this.at(index))) index++;
      return this.getItemValue(this.at(index));
    });
    /**
     * Returns the previous value in the collection
     */
    __publicField(this, "getPreviousValue", (value, step = 1, clamp = false) => {
      let index = this.indexOf(value);
      if (index === -1) return null;
      index = clamp ? Math.max(index - step, 0) : index - step;
      while (index >= 0 && this.getItemDisabled(this.at(index))) index--;
      return this.getItemValue(this.at(index));
    });
    /**
     * Get the index of an item based on its key
     */
    __publicField(this, "indexOf", (value) => {
      if (value == null) return -1;
      return this.items.findIndex((item) => this.getItemValue(item) === value);
    });
    __publicField(this, "getByText", (text, current) => {
      let items = current != null ? wrap(this.items, this.indexOf(current)) : this.items;
      const isSingleKey = text.length === 1;
      if (isSingleKey) items = items.filter((item) => this.getItemValue(item) !== current);
      return items.find((item) => match(this.stringifyItem(item), text));
    });
    /**
     * Search for a value based on a query
     */
    __publicField(this, "search", (queryString, options) => {
      const { state, currentValue, timeout = 350 } = options;
      const search = state.keysSoFar + queryString;
      const isRepeated = search.length > 1 && Array.from(search).every((char) => char === search[0]);
      const query = isRepeated ? search[0] : search;
      const item = this.getByText(query, currentValue);
      const value = this.getItemValue(item);
      function cleanup() {
        clearTimeout(state.timer);
        state.timer = -1;
      }
      function update(value2) {
        state.keysSoFar = value2;
        cleanup();
        if (value2 !== "") {
          state.timer = +setTimeout(() => {
            update("");
            cleanup();
          }, timeout);
        }
      }
      update(search);
      return value;
    });
    __publicField(this, "update", (value, item) => {
      let index = this.items.findIndex((item2) => this.getItemValue(item2) === value);
      if (index === -1) return this;
      return this.copy([...this.items.slice(0, index), item, ...this.items.slice(index + 1)]);
    });
    __publicField(this, "insert", (index, ...items) => {
      return this.copy(insert(this.items, index, ...items));
    });
    __publicField(this, "insertBefore", (value, ...items) => {
      let toIndex = this.indexOf(value);
      if (toIndex === -1) {
        if (this.items.length === 0) toIndex = 0;
        else return this;
      }
      return this.copy(insert(this.items, toIndex, ...items));
    });
    __publicField(this, "insertAfter", (value, ...items) => {
      let toIndex = this.indexOf(value);
      if (toIndex === -1) {
        if (this.items.length === 0) toIndex = 0;
        else return this;
      }
      return this.copy(insert(this.items, toIndex + 1, ...items));
    });
    __publicField(this, "prepend", (...items) => {
      return this.copy(insert(this.items, 0, ...items));
    });
    __publicField(this, "append", (...items) => {
      return this.copy(insert(this.items, this.items.length, ...items));
    });
    __publicField(this, "filter", (fn) => {
      const filteredItems = this.items.filter((item, index) => fn(this.stringifyItem(item), index));
      return this.copy(filteredItems);
    });
    __publicField(this, "remove", (...itemsOrValues) => {
      const values = itemsOrValues.map(
        (itemOrValue) => typeof itemOrValue === "string" ? itemOrValue : this.getItemValue(itemOrValue)
      );
      return this.copy(
        this.items.filter((item) => {
          const value = this.getItemValue(item);
          if (value == null) return false;
          return !values.includes(value);
        })
      );
    });
    __publicField(this, "move", (value, toIndex) => {
      const fromIndex = this.indexOf(value);
      if (fromIndex === -1) return this;
      return this.copy(move(this.items, [fromIndex], toIndex));
    });
    __publicField(this, "reorder", (fromIndex, toIndex) => {
      return this.copy(move(this.items, [fromIndex], toIndex));
    });
    __publicField(this, "compareValue", (a, b) => {
      const indexA = this.indexOf(a);
      const indexB = this.indexOf(b);
      if (indexA < indexB) return -1;
      if (indexA > indexB) return 1;
      return 0;
    });
    __publicField(this, "range", (from, to) => {
      let keys = [];
      let key = from;
      while (key != null) {
        let item = this.find(key);
        if (item) keys.push(key);
        if (key === to) return keys;
        key = this.getNextValue(key);
      }
      return [];
    });
    __publicField(this, "getValueRange", (from, to) => {
      if (from && to) {
        if (this.compareValue(from, to) <= 0) {
          return this.range(from, to);
        }
        return this.range(to, from);
      }
      return [];
    });
    __publicField(this, "toString", () => {
      let result = "";
      for (const item of this.items) {
        const value = this.getItemValue(item);
        const label = this.stringifyItem(item);
        const disabled = this.getItemDisabled(item);
        const itemString = [value, label, disabled].filter(Boolean).join(":");
        result += itemString + ",";
      }
      return result;
    });
    __publicField(this, "toJSON", () => {
      return {
        size: this.size,
        first: this.firstValue,
        last: this.lastValue
      };
    });
    this.items = [...options.items];
  }
  /**
   * Returns the number of items in the collection
   */
  get size() {
    return this.items.length;
  }
  /**
   * Returns the first value in the collection
   */
  get firstValue() {
    let index = 0;
    while (this.getItemDisabled(this.at(index))) index++;
    return this.getItemValue(this.at(index));
  }
  /**
   * Returns the last value in the collection
   */
  get lastValue() {
    let index = this.size - 1;
    while (this.getItemDisabled(this.at(index))) index--;
    return this.getItemValue(this.at(index));
  }
  *[Symbol.iterator]() {
    yield* this.items;
  }
};
var match = (label, query) => {
  return !!label?.toLowerCase().startsWith(query.toLowerCase());
};
var wrap = (v, idx) => {
  return v.map((_, index) => v[(Math.max(idx, 0) + index) % v.length]);
};
function isListCollection(v) {
  return v instanceof ListCollection;
}
function insert(items, index, ...values) {
  return [...items.slice(0, index), ...values, ...items.slice(index)];
}
function move(items, indices, toIndex) {
  indices = [...indices].sort((a, b) => a - b);
  const itemsToMove = indices.map((i) => items[i]);
  for (let i = indices.length - 1; i >= 0; i--) {
    items = [...items.slice(0, indices[i]), ...items.slice(indices[i] + 1)];
  }
  toIndex = Math.max(0, toIndex - indices.filter((i) => i < toIndex).length);
  return [...items.slice(0, toIndex), ...itemsToMove, ...items.slice(toIndex)];
}

// src/grid-collection.ts
var GridCollection = class extends ListCollection {
  constructor(options) {
    const { columnCount } = options;
    super(options);
    __publicField(this, "columnCount");
    /**
     * Returns the row data in the grid
     */
    __publicField(this, "getRows", () => {
      return utils.chunk([...this.items], this.columnCount);
    });
    /**
     * Returns the number of rows in the grid
     */
    __publicField(this, "getRowCount", () => {
      return this.getRows().length;
    });
    /**
     * Returns the index of the specified row and column in the grid
     */
    __publicField(this, "getCellIndex", (row, column) => {
      return row * this.columnCount + column;
    });
    /**
     * Returns the item at the specified row and column in the grid
     */
    __publicField(this, "getCell", (row, column) => {
      return this.at(this.getCellIndex(row, column));
    });
    /**
     * Returns the row and column index for a given value
     */
    __publicField(this, "getValueCell", (value) => {
      const index = this.indexOf(value);
      if (index === -1) return null;
      const row = Math.floor(index / this.columnCount);
      const column = index % this.columnCount;
      return { row, column };
    });
    /**
     * Returns the value of the last enabled column in a row
     */
    __publicField(this, "getLastEnabledColumnIndex", (row) => {
      for (let col = this.columnCount - 1; col >= 0; col--) {
        const cell = this.getCell(row, col);
        if (cell && !this.getItemDisabled(cell)) {
          return col;
        }
      }
      return null;
    });
    /**
     * Returns the index of the first enabled column in a row
     */
    __publicField(this, "getFirstEnabledColumnIndex", (row) => {
      for (let col = 0; col < this.columnCount; col++) {
        const cell = this.getCell(row, col);
        if (cell && !this.getItemDisabled(cell)) {
          return col;
        }
      }
      return null;
    });
    /**
     * Returns the value of the previous row in the grid, based on the current value
     */
    __publicField(this, "getPreviousRowValue", (value, loop = false) => {
      const currentCell = this.getValueCell(value);
      if (currentCell === null) return null;
      const rows = this.getRows();
      const rowCount = this.getRowCount();
      let prevRowIndex = currentCell.row;
      let prevColumnIndex = currentCell.column;
      for (let i = 1; i <= rowCount; i++) {
        prevRowIndex = utils.prevIndex(rows, prevRowIndex, { loop });
        const prevRow = rows[prevRowIndex];
        if (!prevRow) continue;
        const prevCell = prevRow[prevColumnIndex];
        if (!prevCell) {
          const lastColumnIndex = this.getLastEnabledColumnIndex(prevRowIndex);
          if (lastColumnIndex != null) {
            prevColumnIndex = lastColumnIndex;
          }
        }
        const cell = this.getCell(prevRowIndex, prevColumnIndex);
        if (!this.getItemDisabled(cell)) {
          return this.getItemValue(cell);
        }
      }
      return this.firstValue;
    });
    /**
     * Returns the value of the next row in the grid, based on the current value
     */
    __publicField(this, "getNextRowValue", (value, loop = false) => {
      const currentCell = this.getValueCell(value);
      if (currentCell === null) return null;
      const rows = this.getRows();
      const rowCount = this.getRowCount();
      let nextRowIndex = currentCell.row;
      let nextColumnIndex = currentCell.column;
      for (let i = 1; i <= rowCount; i++) {
        nextRowIndex = utils.nextIndex(rows, nextRowIndex, { loop });
        const nextRow = rows[nextRowIndex];
        if (!nextRow) continue;
        const nextCell = nextRow[nextColumnIndex];
        if (!nextCell) {
          const lastColumnIndex = this.getLastEnabledColumnIndex(nextRowIndex);
          if (lastColumnIndex != null) {
            nextColumnIndex = lastColumnIndex;
          }
        }
        const cell = this.getCell(nextRowIndex, nextColumnIndex);
        if (!this.getItemDisabled(cell)) {
          return this.getItemValue(cell);
        }
      }
      return this.lastValue;
    });
    this.columnCount = columnCount;
  }
};
function isGridCollection(v) {
  return v instanceof GridCollection;
}

// src/tree-visit.ts
function access(node, indexPath, options) {
  for (let i = 0; i < indexPath.length; i++) node = options.getChildren(node, indexPath.slice(i + 1))[indexPath[i]];
  return node;
}
function ancestorIndexPaths(indexPaths) {
  const sortedPaths = sortIndexPaths(indexPaths);
  const result = [];
  const seen = /* @__PURE__ */ new Set();
  for (const indexPath of sortedPaths) {
    const key = indexPath.join();
    if (!seen.has(key)) {
      seen.add(key);
      result.push(indexPath);
    }
  }
  return result;
}
function compareIndexPaths(a, b) {
  for (let i = 0; i < Math.min(a.length, b.length); i++) {
    if (a[i] < b[i]) return -1;
    if (a[i] > b[i]) return 1;
  }
  return a.length - b.length;
}
function sortIndexPaths(indexPaths) {
  return indexPaths.sort(compareIndexPaths);
}
function find(node, options) {
  let found;
  visit(node, {
    ...options,
    onEnter: (child, indexPath) => {
      if (options.predicate(child, indexPath)) {
        found = child;
        return "stop";
      }
    }
  });
  return found;
}
function findIndexPath(node, options) {
  let found;
  visit(node, {
    onEnter: (child, indexPath) => {
      if (options.predicate(child, indexPath)) {
        found = [...indexPath];
        return "stop";
      }
    },
    getChildren: options.getChildren
  });
  return found;
}
function reduce(node, options) {
  let result = options.initialResult;
  visit(node, {
    ...options,
    onEnter: (child, indexPath) => {
      result = options.nextResult(result, child, indexPath);
    }
  });
  return result;
}
function flatMap(node, options) {
  return reduce(node, {
    ...options,
    initialResult: [],
    nextResult: (result, child, indexPath) => {
      result.push(...options.transform(child, indexPath));
      return result;
    }
  });
}
function insertOperation(index, nodes) {
  return { type: "insert", index, nodes };
}
function removeOperation(indexes) {
  return { type: "remove", indexes };
}
function replaceOperation() {
  return { type: "replace" };
}
function splitIndexPath(indexPath) {
  return [indexPath.slice(0, -1), indexPath[indexPath.length - 1]];
}
function getInsertionOperations(indexPath, nodes, operations = /* @__PURE__ */ new Map()) {
  const [parentIndexPath, index] = splitIndexPath(indexPath);
  for (let i = parentIndexPath.length - 1; i >= 0; i--) {
    const parentKey = parentIndexPath.slice(0, i).join();
    switch (operations.get(parentKey)?.type) {
      case "remove":
        continue;
    }
    operations.set(parentKey, replaceOperation());
  }
  const operation = operations.get(parentIndexPath.join());
  switch (operation?.type) {
    case "remove":
      operations.set(parentIndexPath.join(), {
        type: "removeThenInsert",
        removeIndexes: operation.indexes,
        insertIndex: index,
        insertNodes: nodes
      });
      break;
    default:
      operations.set(parentIndexPath.join(), insertOperation(index, nodes));
  }
  return operations;
}
function getRemovalOperations(indexPaths) {
  const operations = /* @__PURE__ */ new Map();
  const indexesToRemove = /* @__PURE__ */ new Map();
  for (const indexPath of indexPaths) {
    const parentKey = indexPath.slice(0, -1).join();
    const value = indexesToRemove.get(parentKey) ?? [];
    value.push(indexPath[indexPath.length - 1]);
    indexesToRemove.set(
      parentKey,
      value.sort((a, b) => a - b)
    );
  }
  for (const indexPath of indexPaths) {
    for (let i = indexPath.length - 2; i >= 0; i--) {
      const parentKey = indexPath.slice(0, i).join();
      if (!operations.has(parentKey)) {
        operations.set(parentKey, replaceOperation());
      }
    }
  }
  for (const [parentKey, indexes] of indexesToRemove) {
    operations.set(parentKey, removeOperation(indexes));
  }
  return operations;
}
function getReplaceOperations(indexPath, node) {
  const operations = /* @__PURE__ */ new Map();
  const [parentIndexPath, index] = splitIndexPath(indexPath);
  for (let i = parentIndexPath.length - 1; i >= 0; i--) {
    const parentKey = parentIndexPath.slice(0, i).join();
    operations.set(parentKey, replaceOperation());
  }
  operations.set(parentIndexPath.join(), {
    type: "removeThenInsert",
    removeIndexes: [index],
    insertIndex: index,
    insertNodes: [node]
  });
  return operations;
}
function mutate(node, operations, options) {
  return map(node, {
    ...options,
    getChildren: (node2, indexPath) => {
      const key = indexPath.join();
      const operation = operations.get(key);
      switch (operation?.type) {
        case "replace":
        case "remove":
        case "removeThenInsert":
        case "insert":
          return options.getChildren(node2, indexPath);
        default:
          return [];
      }
    },
    transform: (node2, children, indexPath) => {
      const key = indexPath.join();
      const operation = operations.get(key);
      switch (operation?.type) {
        case "remove":
          return options.create(
            node2,
            children.filter((_, index) => !operation.indexes.includes(index)),
            indexPath
          );
        case "removeThenInsert":
          const updatedChildren = children.filter((_, index) => !operation.removeIndexes.includes(index));
          const adjustedIndex = operation.removeIndexes.reduce(
            (index, removedIndex) => removedIndex < index ? index - 1 : index,
            operation.insertIndex
          );
          return options.create(node2, splice(updatedChildren, adjustedIndex, 0, ...operation.insertNodes), indexPath);
        case "insert":
          return options.create(node2, splice(children, operation.index, 0, ...operation.nodes), indexPath);
        case "replace":
          return options.create(node2, children, indexPath);
        default:
          return node2;
      }
    }
  });
}
function splice(array, start, deleteCount, ...items) {
  return [...array.slice(0, start), ...items, ...array.slice(start + deleteCount)];
}
function map(node, options) {
  const childrenMap = {};
  visit(node, {
    ...options,
    onLeave: (child, indexPath) => {
      const keyIndexPath = [0, ...indexPath];
      const key = keyIndexPath.join();
      const transformed = options.transform(child, childrenMap[key] ?? [], indexPath);
      const parentKey = keyIndexPath.slice(0, -1).join();
      const parentChildren = childrenMap[parentKey] ?? [];
      parentChildren.push(transformed);
      childrenMap[parentKey] = parentChildren;
    }
  });
  return childrenMap[""][0];
}
function insert2(node, options) {
  const { nodes, at } = options;
  if (at.length === 0) throw new Error(`Can't insert nodes at the root`);
  const state = getInsertionOperations(at, nodes);
  return mutate(node, state, options);
}
function replace(node, options) {
  if (options.at.length === 0) return options.node;
  const operations = getReplaceOperations(options.at, options.node);
  return mutate(node, operations, options);
}
function remove(node, options) {
  if (options.indexPaths.length === 0) return node;
  for (const indexPath of options.indexPaths) {
    if (indexPath.length === 0) throw new Error(`Can't remove the root node`);
  }
  const operations = getRemovalOperations(options.indexPaths);
  return mutate(node, operations, options);
}
function move2(node, options) {
  if (options.indexPaths.length === 0) return node;
  for (const indexPath of options.indexPaths) {
    if (indexPath.length === 0) throw new Error(`Can't move the root node`);
  }
  if (options.to.length === 0) throw new Error(`Can't move nodes to the root`);
  const _ancestorIndexPaths = ancestorIndexPaths(options.indexPaths);
  const nodesToInsert = _ancestorIndexPaths.map((indexPath) => access(node, indexPath, options));
  const operations = getInsertionOperations(options.to, nodesToInsert, getRemovalOperations(_ancestorIndexPaths));
  return mutate(node, operations, options);
}
function visit(node, options) {
  const { onEnter, onLeave, getChildren } = options;
  let indexPath = [];
  let stack = [{ node }];
  const getIndexPath = options.reuseIndexPath ? () => indexPath : () => indexPath.slice();
  while (stack.length > 0) {
    let wrapper = stack[stack.length - 1];
    if (wrapper.state === void 0) {
      const enterResult = onEnter?.(wrapper.node, getIndexPath());
      if (enterResult === "stop") return;
      wrapper.state = enterResult === "skip" ? -1 : 0;
    }
    const children = wrapper.children || getChildren(wrapper.node, getIndexPath());
    wrapper.children || (wrapper.children = children);
    if (wrapper.state !== -1) {
      if (wrapper.state < children.length) {
        let currentIndex = wrapper.state;
        indexPath.push(currentIndex);
        stack.push({ node: children[currentIndex] });
        wrapper.state = currentIndex + 1;
        continue;
      }
      const leaveResult = onLeave?.(wrapper.node, getIndexPath());
      if (leaveResult === "stop") return;
    }
    indexPath.pop();
    stack.pop();
  }
}

// src/tree-collection.ts
var TreeCollection = class {
  constructor(options) {
    this.options = options;
    __publicField(this, "rootNode");
    __publicField(this, "isEqual", (other) => {
      return utils.isEqual(this.rootNode, other.rootNode);
    });
    __publicField(this, "getNodeChildren", (node) => {
      return this.options.nodeToChildren?.(node) ?? fallback2.nodeToChildren(node) ?? [];
    });
    __publicField(this, "getNodeValue", (node) => {
      return this.options.nodeToValue?.(node) ?? fallback2.nodeToValue(node);
    });
    __publicField(this, "getNodeDisabled", (node) => {
      return this.options.isNodeDisabled?.(node) ?? fallback2.isNodeDisabled(node);
    });
    __publicField(this, "stringify", (value) => {
      const node = this.findNode(value);
      if (!node) return null;
      return this.stringifyNode(node);
    });
    __publicField(this, "stringifyNode", (node) => {
      return this.options.nodeToString?.(node) ?? fallback2.nodeToString(node);
    });
    __publicField(this, "getFirstNode", (rootNode = this.rootNode) => {
      let firstChild;
      visit(rootNode, {
        getChildren: this.getNodeChildren,
        onEnter: (node, indexPath) => {
          if (!firstChild && indexPath.length > 0 && !this.getNodeDisabled(node)) {
            firstChild = node;
            return "stop";
          }
        }
      });
      return firstChild;
    });
    __publicField(this, "getLastNode", (rootNode = this.rootNode, opts = {}) => {
      let lastChild;
      visit(rootNode, {
        getChildren: this.getNodeChildren,
        onEnter: (node, indexPath) => {
          const nodeValue = this.getNodeValue(node);
          if (opts.skip?.({ value: nodeValue, node, indexPath })) return "skip";
          if (indexPath.length > 1) return "skip";
          if (!this.getNodeDisabled(node)) {
            lastChild = node;
          }
        }
      });
      return lastChild;
    });
    __publicField(this, "at", (indexPath) => {
      return access(this.rootNode, indexPath, {
        getChildren: this.getNodeChildren
      });
    });
    __publicField(this, "findNode", (value, rootNode = this.rootNode) => {
      return find(rootNode, {
        getChildren: this.getNodeChildren,
        predicate: (node) => this.getNodeValue(node) === value
      });
    });
    __publicField(this, "sort", (values) => {
      return values.reduce(
        (acc, value) => {
          const indexPath = this.getIndexPath(value);
          if (indexPath != null) acc.push({ value, indexPath });
          return acc;
        },
        []
      ).sort((a, b) => compareIndexPaths(a.indexPath, b.indexPath)).map(({ value }) => value);
    });
    __publicField(this, "getIndexPath", (value) => {
      return findIndexPath(this.rootNode, {
        getChildren: this.getNodeChildren,
        predicate: (node) => this.getNodeValue(node) === value
      });
    });
    __publicField(this, "getValue", (indexPath) => {
      const node = this.at(indexPath);
      return node ? this.getNodeValue(node) : void 0;
    });
    __publicField(this, "getValuePath", (indexPath) => {
      if (!indexPath) return [];
      const valuePath = [];
      let currentPath = [...indexPath];
      while (currentPath.length > 0) {
        const node = this.at(currentPath);
        if (node) valuePath.unshift(this.getNodeValue(node));
        currentPath.pop();
      }
      return valuePath;
    });
    __publicField(this, "getDepth", (value) => {
      const indexPath = findIndexPath(this.rootNode, {
        getChildren: this.getNodeChildren,
        predicate: (node) => this.getNodeValue(node) === value
      });
      return indexPath?.length ?? 0;
    });
    __publicField(this, "isRootNode", (node) => {
      return this.getNodeValue(node) === this.getNodeValue(this.rootNode);
    });
    __publicField(this, "contains", (parentIndexPath, valueIndexPath) => {
      if (!parentIndexPath || !valueIndexPath) return false;
      return valueIndexPath.slice(0, parentIndexPath.length).every((_, i) => parentIndexPath[i] === valueIndexPath[i]);
    });
    __publicField(this, "getNextNode", (value, opts = {}) => {
      let found = false;
      let nextNode;
      visit(this.rootNode, {
        getChildren: this.getNodeChildren,
        onEnter: (node, indexPath) => {
          if (this.isRootNode(node)) return;
          const nodeValue = this.getNodeValue(node);
          if (opts.skip?.({ value: nodeValue, node, indexPath })) {
            if (nodeValue === value) {
              found = true;
            }
            return "skip";
          }
          if (found && !this.getNodeDisabled(node)) {
            nextNode = node;
            return "stop";
          }
          if (nodeValue === value) {
            found = true;
          }
        }
      });
      return nextNode;
    });
    __publicField(this, "getPreviousNode", (value, opts = {}) => {
      let previousNode;
      let found = false;
      visit(this.rootNode, {
        getChildren: this.getNodeChildren,
        onEnter: (node, indexPath) => {
          if (this.isRootNode(node)) return;
          const nodeValue = this.getNodeValue(node);
          if (opts.skip?.({ value: nodeValue, node, indexPath })) {
            return "skip";
          }
          if (nodeValue === value) {
            found = true;
            return "stop";
          }
          if (!this.getNodeDisabled(node)) {
            previousNode = node;
          }
        }
      });
      return found ? previousNode : void 0;
    });
    __publicField(this, "getParentNodes", (values) => {
      const result = [];
      let indexPath = this.getIndexPath(values);
      while (indexPath && indexPath.length > 0) {
        indexPath.pop();
        const parentNode = this.at(indexPath);
        if (parentNode && !this.isRootNode(parentNode)) {
          result.unshift(parentNode);
        }
      }
      return result;
    });
    __publicField(this, "getParentIndexPath", (indexPath) => {
      return indexPath.slice(0, -1);
    });
    __publicField(this, "getParentNode", (valueOrIndexPath) => {
      const indexPath = typeof valueOrIndexPath === "string" ? this.getIndexPath(valueOrIndexPath) : valueOrIndexPath;
      return indexPath ? this.at(this.getParentIndexPath(indexPath)) : void 0;
    });
    __publicField(this, "visit", (opts) => {
      const { skip, ...rest } = opts;
      visit(this.rootNode, {
        ...rest,
        getChildren: this.getNodeChildren,
        onEnter: (node, indexPath) => {
          if (this.isRootNode(node)) return;
          if (skip?.({ value: this.getNodeValue(node), node, indexPath })) return "skip";
          return rest.onEnter?.(node, indexPath);
        }
      });
    });
    __publicField(this, "getPreviousSibling", (indexPath) => {
      const parentNode = this.getParentNode(indexPath);
      if (!parentNode) return;
      const siblings = this.getNodeChildren(parentNode);
      let idx = siblings.findIndex((sibling) => this.getValue(indexPath) === this.getNodeValue(sibling));
      while (--idx >= 0) {
        const sibling = siblings[idx];
        if (!this.getNodeDisabled(sibling)) return sibling;
      }
      return;
    });
    __publicField(this, "getNextSibling", (indexPath) => {
      const parentNode = this.getParentNode(indexPath);
      if (!parentNode) return;
      const siblings = this.getNodeChildren(parentNode);
      let idx = siblings.findIndex((sibling) => this.getValue(indexPath) === this.getNodeValue(sibling));
      while (++idx < siblings.length) {
        const sibling = siblings[idx];
        if (!this.getNodeDisabled(sibling)) return sibling;
      }
      return;
    });
    __publicField(this, "getSiblingNodes", (indexPath) => {
      const parentNode = this.getParentNode(indexPath);
      return parentNode ? this.getNodeChildren(parentNode) : [];
    });
    __publicField(this, "getValues", (rootNode = this.rootNode) => {
      const values = flatMap(rootNode, {
        getChildren: this.getNodeChildren,
        transform: (node) => [this.getNodeValue(node)]
      });
      return values.slice(1);
    });
    __publicField(this, "isSameDepth", (indexPath, depth) => {
      if (depth == null) return true;
      return indexPath.length === depth;
    });
    __publicField(this, "isBranchNode", (node) => {
      return this.getNodeChildren(node).length > 0;
    });
    __publicField(this, "getBranchValues", (rootNode = this.rootNode, opts = {}) => {
      let values = [];
      visit(rootNode, {
        getChildren: this.getNodeChildren,
        onEnter: (node, indexPath) => {
          const nodeValue = this.getNodeValue(node);
          if (opts.skip?.({ value: nodeValue, node, indexPath })) return "skip";
          if (this.getNodeChildren(node).length > 0 && this.isSameDepth(indexPath, opts.depth)) {
            values.push(this.getNodeValue(node));
          }
        }
      });
      return values.slice(1);
    });
    __publicField(this, "flatten", (rootNode = this.rootNode) => {
      const nodes = flatMap(rootNode, {
        getChildren: this.getNodeChildren,
        transform: (node, indexPath) => {
          const children = this.getNodeChildren(node).map((child) => this.getNodeValue(child));
          return [
            utils.compact({
              label: this.stringifyNode(node),
              value: this.getNodeValue(node),
              indexPath,
              children: children.length > 0 ? children : void 0
            })
          ];
        }
      });
      return nodes.slice(1);
    });
    __publicField(this, "_create", (node, children) => {
      return utils.compact({ ...node, children });
    });
    __publicField(this, "_insert", (rootNode, indexPath, nodes) => {
      return insert2(rootNode, { at: indexPath, nodes, getChildren: this.getNodeChildren, create: this._create });
    });
    __publicField(this, "_replace", (rootNode, indexPath, node) => {
      return replace(rootNode, { at: indexPath, node, getChildren: this.getNodeChildren, create: this._create });
    });
    __publicField(this, "_move", (rootNode, indexPaths, to) => {
      return move2(rootNode, { indexPaths, to, getChildren: this.getNodeChildren, create: this._create });
    });
    __publicField(this, "_remove", (rootNode, indexPaths) => {
      return remove(rootNode, { indexPaths, getChildren: this.getNodeChildren, create: this._create });
    });
    __publicField(this, "replace", (indexPath, node) => {
      return this._replace(this.rootNode, indexPath, node);
    });
    __publicField(this, "remove", (indexPaths) => {
      return this._remove(this.rootNode, indexPaths);
    });
    __publicField(this, "insertBefore", (indexPath, nodes) => {
      const parentNode = this.getParentNode(indexPath);
      return parentNode ? this._insert(this.rootNode, indexPath, nodes) : void 0;
    });
    __publicField(this, "insertAfter", (indexPath, nodes) => {
      const parentNode = this.getParentNode(indexPath);
      if (!parentNode) return;
      const nextIndex2 = [...indexPath.slice(0, -1), indexPath[indexPath.length - 1] + 1];
      return this._insert(this.rootNode, nextIndex2, nodes);
    });
    __publicField(this, "move", (fromIndexPaths, toIndexPath) => {
      return this._move(this.rootNode, fromIndexPaths, toIndexPath);
    });
    __publicField(this, "toJSON", () => {
      return this.getValues(this.rootNode);
    });
    this.rootNode = options.rootNode;
  }
};
function flattenedToTree(nodes) {
  let rootNode = {
    value: "ROOT"
  };
  nodes.map((node) => {
    const { indexPath, label, value } = node;
    if (!indexPath.length) {
      Object.assign(rootNode, { label, value, children: [] });
      return;
    }
    rootNode = insert2(rootNode, {
      at: indexPath,
      nodes: [utils.compact({ label, value })],
      getChildren: (node2) => node2.children ?? [],
      create: (node2, children) => {
        return utils.compact({ ...node2, children });
      }
    });
  });
  return new TreeCollection({ rootNode });
}
function filePathToTree(paths) {
  const rootNode = {
    label: "",
    value: "ROOT",
    children: []
  };
  paths.forEach((path) => {
    const parts = path.split("/");
    let currentNode = rootNode;
    parts.forEach((part) => {
      let childNode = currentNode.children?.find((child) => child.label === part);
      if (!childNode) {
        childNode = {
          value: parts.slice(0, parts.indexOf(part) + 1).join("/"),
          label: part
        };
        currentNode.children || (currentNode.children = []);
        currentNode.children.push(childNode);
      }
      currentNode = childNode;
    });
  });
  return new TreeCollection({ rootNode });
}
var fallback2 = {
  nodeToValue(node) {
    if (typeof node === "string") return node;
    if (utils.isObject(node) && utils.hasProp(node, "value")) return node.value;
    return "";
  },
  nodeToString(node) {
    if (typeof node === "string") return node;
    if (utils.isObject(node) && utils.hasProp(node, "label")) return node.label;
    return fallback2.nodeToValue(node);
  },
  isNodeDisabled(node) {
    if (utils.isObject(node) && utils.hasProp(node, "disabled")) return !!node.disabled;
    return false;
  },
  nodeToChildren(node) {
    return node.children;
  }
};
var Selection = class _Selection extends Set {
  constructor(values = []) {
    super(values);
    __publicField(this, "selectionMode", "single");
    __publicField(this, "deselectable", true);
    __publicField(this, "copy", () => {
      const clone = new _Selection([...this]);
      return this.sync(clone);
    });
    __publicField(this, "sync", (other) => {
      other.selectionMode = this.selectionMode;
      other.deselectable = this.deselectable;
      return other;
    });
    __publicField(this, "isEmpty", () => {
      return this.size === 0;
    });
    __publicField(this, "isSelected", (value) => {
      if (this.selectionMode === "none" || value == null) {
        return false;
      }
      return this.has(value);
    });
    __publicField(this, "canSelect", (collection, value) => {
      return this.selectionMode !== "none" || !collection.getItemDisabled(collection.find(value));
    });
    __publicField(this, "firstSelectedValue", (collection) => {
      let firstValue = null;
      for (let value of this) {
        if (!firstValue || collection.compareValue(value, firstValue) < 0) {
          firstValue = value;
        }
      }
      return firstValue;
    });
    __publicField(this, "lastSelectedValue", (collection) => {
      let lastValue = null;
      for (let value of this) {
        if (!lastValue || collection.compareValue(value, lastValue) > 0) {
          lastValue = value;
        }
      }
      return lastValue;
    });
    __publicField(this, "extendSelection", (collection, anchorValue, targetValue) => {
      if (this.selectionMode === "none") {
        return this;
      }
      if (this.selectionMode === "single") {
        return this.replaceSelection(collection, targetValue);
      }
      const selection = this.copy();
      const lastSelected = Array.from(this).pop();
      for (let key of collection.getValueRange(anchorValue, lastSelected ?? targetValue)) {
        selection.delete(key);
      }
      for (let key of collection.getValueRange(targetValue, anchorValue)) {
        if (this.canSelect(collection, key)) {
          selection.add(key);
        }
      }
      return selection;
    });
    __publicField(this, "toggleSelection", (collection, value) => {
      if (this.selectionMode === "none") {
        return this;
      }
      if (this.selectionMode === "single" && !this.isSelected(value)) {
        return this.replaceSelection(collection, value);
      }
      const selection = this.copy();
      if (selection.has(value)) {
        selection.delete(value);
      } else if (selection.canSelect(collection, value)) {
        selection.add(value);
      }
      return selection;
    });
    __publicField(this, "replaceSelection", (collection, value) => {
      if (this.selectionMode === "none") {
        return this;
      }
      if (value == null) {
        return this;
      }
      if (!this.canSelect(collection, value)) {
        return this;
      }
      const selection = new _Selection([value]);
      return this.sync(selection);
    });
    __publicField(this, "setSelection", (values) => {
      if (this.selectionMode === "none") {
        return this;
      }
      let selection = new _Selection();
      for (let value of values) {
        if (value != null) {
          selection.add(value);
          if (this.selectionMode === "single") {
            break;
          }
        }
      }
      return this.sync(selection);
    });
    __publicField(this, "clearSelection", () => {
      const selection = this.copy();
      if (selection.deselectable && selection.size > 0) {
        selection.clear();
      }
      return selection;
    });
    __publicField(this, "select", (collection, value, forceToggle) => {
      if (this.selectionMode === "none") {
        return this;
      }
      if (this.selectionMode === "single") {
        if (this.isSelected(value) && this.deselectable) {
          return this.toggleSelection(collection, value);
        } else {
          return this.replaceSelection(collection, value);
        }
      } else if (this.selectionMode === "multiple" || forceToggle) {
        return this.toggleSelection(collection, value);
      } else {
        return this.replaceSelection(collection, value);
      }
    });
    __publicField(this, "deselect", (value) => {
      const selection = this.copy();
      selection.delete(value);
      return selection;
    });
    __publicField(this, "isEqual", (other) => {
      return utils.isEqual(Array.from(this), Array.from(other));
    });
  }
};

exports.GridCollection = GridCollection;
exports.ListCollection = ListCollection;
exports.Selection = Selection;
exports.TreeCollection = TreeCollection;
exports.filePathToTree = filePathToTree;
exports.flattenedToTree = flattenedToTree;
exports.isGridCollection = isGridCollection;
exports.isListCollection = isListCollection;
