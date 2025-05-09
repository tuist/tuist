/**
 * Copyright 2022 Joe Bell. All rights reserved.
 *
 * This file is licensed to you under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with the
 * License. You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR REPRESENTATIONS OF ANY KIND, either express or implied. See the
 * License for the specific language governing permissions and limitations under
 * the License.
 */ "use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
function _export(target, all) {
    for(var name in all)Object.defineProperty(target, name, {
        enumerable: true,
        get: all[name]
    });
}
_export(exports, {
    compose: function() {
        return compose;
    },
    cva: function() {
        return cva;
    },
    cx: function() {
        return cx;
    },
    defineConfig: function() {
        return defineConfig;
    }
});
const _clsx = require("clsx");
/* Exports
  ============================================ */ const falsyToString = (value)=>typeof value === "boolean" ? `${value}` : value === 0 ? "0" : value;
const defineConfig = (options)=>{
    const cx = function() {
        for(var _len = arguments.length, inputs = new Array(_len), _key = 0; _key < _len; _key++){
            inputs[_key] = arguments[_key];
        }
        var _options_hooks, _options_hooks1;
        if (typeof (options === null || options === void 0 ? void 0 : (_options_hooks = options.hooks) === null || _options_hooks === void 0 ? void 0 : _options_hooks["cx:done"]) !== "undefined") return options === null || options === void 0 ? void 0 : options.hooks["cx:done"]((0, _clsx.clsx)(inputs));
        if (typeof (options === null || options === void 0 ? void 0 : (_options_hooks1 = options.hooks) === null || _options_hooks1 === void 0 ? void 0 : _options_hooks1.onComplete) !== "undefined") return options === null || options === void 0 ? void 0 : options.hooks.onComplete((0, _clsx.clsx)(inputs));
        return (0, _clsx.clsx)(inputs);
    };
    const cva = (config)=>(props)=>{
            var _config_compoundVariants;
            if ((config === null || config === void 0 ? void 0 : config.variants) == null) return cx(config === null || config === void 0 ? void 0 : config.base, props === null || props === void 0 ? void 0 : props.class, props === null || props === void 0 ? void 0 : props.className);
            const { variants, defaultVariants } = config;
            const getVariantClassNames = Object.keys(variants).map((variant)=>{
                const variantProp = props === null || props === void 0 ? void 0 : props[variant];
                const defaultVariantProp = defaultVariants === null || defaultVariants === void 0 ? void 0 : defaultVariants[variant];
                const variantKey = falsyToString(variantProp) || falsyToString(defaultVariantProp);
                return variants[variant][variantKey];
            });
            const defaultsAndProps = {
                ...defaultVariants,
                // remove `undefined` props
                ...props && Object.entries(props).reduce((acc, param)=>{
                    let [key, value] = param;
                    return typeof value === "undefined" ? acc : {
                        ...acc,
                        [key]: value
                    };
                }, {})
            };
            const getCompoundVariantClassNames = config === null || config === void 0 ? void 0 : (_config_compoundVariants = config.compoundVariants) === null || _config_compoundVariants === void 0 ? void 0 : _config_compoundVariants.reduce((acc, param)=>{
                let { class: cvClass, className: cvClassName, ...cvConfig } = param;
                return Object.entries(cvConfig).every((param)=>{
                    let [cvKey, cvSelector] = param;
                    const selector = defaultsAndProps[cvKey];
                    return Array.isArray(cvSelector) ? cvSelector.includes(selector) : selector === cvSelector;
                }) ? [
                    ...acc,
                    cvClass,
                    cvClassName
                ] : acc;
            }, []);
            return cx(config === null || config === void 0 ? void 0 : config.base, getVariantClassNames, getCompoundVariantClassNames, props === null || props === void 0 ? void 0 : props.class, props === null || props === void 0 ? void 0 : props.className);
        };
    const compose = function() {
        for(var _len = arguments.length, components = new Array(_len), _key = 0; _key < _len; _key++){
            components[_key] = arguments[_key];
        }
        return (props)=>{
            const propsWithoutClass = Object.fromEntries(Object.entries(props || {}).filter((param)=>{
                let [key] = param;
                return ![
                    "class",
                    "className"
                ].includes(key);
            }));
            return cx(components.map((component)=>component(propsWithoutClass)), props === null || props === void 0 ? void 0 : props.class, props === null || props === void 0 ? void 0 : props.className);
        };
    };
    return {
        compose,
        cva,
        cx
    };
};
const { compose, cva, cx } = defineConfig();


//# sourceMappingURL=index.js.map