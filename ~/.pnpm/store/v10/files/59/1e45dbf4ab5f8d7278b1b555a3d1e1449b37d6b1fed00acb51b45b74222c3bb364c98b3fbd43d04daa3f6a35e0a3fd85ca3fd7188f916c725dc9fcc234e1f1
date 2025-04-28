'use strict';

var utils = require('@zag-js/utils');
var domQuery = require('@zag-js/dom-query');

// src/merge-props.ts
var clsx = (...args) => args.map((str) => str?.trim?.()).filter(Boolean).join(" ");
var CSS_REGEX = /((?:--)?(?:\w+-?)+)\s*:\s*([^;]*)/g;
var serialize = (style) => {
  const res = {};
  let match;
  while (match = CSS_REGEX.exec(style)) {
    res[match[1]] = match[2];
  }
  return res;
};
var css = (a, b) => {
  if (utils.isString(a)) {
    if (utils.isString(b)) return `${a};${b}`;
    a = serialize(a);
  } else if (utils.isString(b)) {
    b = serialize(b);
  }
  return Object.assign({}, a ?? {}, b ?? {});
};
function mergeProps(...args) {
  let result = {};
  for (let props of args) {
    for (let key in result) {
      if (key.startsWith("on") && typeof result[key] === "function" && typeof props[key] === "function") {
        result[key] = utils.callAll(props[key], result[key]);
        continue;
      }
      if (key === "className" || key === "class") {
        result[key] = clsx(result[key], props[key]);
        continue;
      }
      if (key === "style") {
        result[key] = css(result[key], props[key]);
        continue;
      }
      result[key] = props[key] !== void 0 ? props[key] : result[key];
    }
    for (let key in props) {
      if (result[key] === void 0) {
        result[key] = props[key];
      }
    }
  }
  return result;
}
function memo(getDeps, fn, opts) {
  let deps = [];
  let result;
  return (depArgs) => {
    const newDeps = getDeps(depArgs);
    const depsChanged = newDeps.length !== deps.length || newDeps.some((dep, index) => !utils.isEqual(deps[index], dep));
    if (!depsChanged) return result;
    deps = newDeps;
    result = fn(...newDeps);
    opts?.onChange?.(result);
    return result;
  };
}

// src/create-machine.ts
function createGuards() {
  return {
    and: (...guards) => {
      return function andGuard(params) {
        return guards.every((str) => params.guard(str));
      };
    },
    or: (...guards) => {
      return function orGuard(params) {
        return guards.some((str) => params.guard(str));
      };
    },
    not: (guard) => {
      return function notGuard(params) {
        return !params.guard(guard);
      };
    }
  };
}
function createMachine(config) {
  return config;
}
function setup() {
  return {
    guards: createGuards(),
    createMachine: (config) => {
      return createMachine(config);
    },
    choose: (transitions) => {
      return function chooseFn({ choose }) {
        return choose(transitions)?.actions;
      };
    }
  };
}

// src/types.ts
var MachineStatus = /* @__PURE__ */ ((MachineStatus2) => {
  MachineStatus2["NotStarted"] = "Not Started";
  MachineStatus2["Started"] = "Started";
  MachineStatus2["Stopped"] = "Stopped";
  return MachineStatus2;
})(MachineStatus || {});
var INIT_STATE = "__init__";
function createScope(props) {
  const getRootNode = () => props.getRootNode?.() ?? document;
  const getDoc = () => domQuery.getDocument(getRootNode());
  const getWin = () => getDoc().defaultView ?? window;
  const getActiveElementFn = () => domQuery.getActiveElement(getRootNode());
  const isActiveElement = (elem) => elem === getActiveElementFn();
  const getById = (id) => getRootNode().getElementById(id);
  return {
    ...props,
    getRootNode,
    getDoc,
    getWin,
    getActiveElement: getActiveElementFn,
    isActiveElement,
    getById
  };
}

exports.INIT_STATE = INIT_STATE;
exports.MachineStatus = MachineStatus;
exports.createGuards = createGuards;
exports.createMachine = createMachine;
exports.createScope = createScope;
exports.memo = memo;
exports.mergeProps = mergeProps;
exports.setup = setup;
