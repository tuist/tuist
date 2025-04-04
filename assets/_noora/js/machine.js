// Zag.js does not offer a vanilla JS package, just a reference implementation.
// This file has been adapted for our project structure and was originally taken from their repository.
// Source: https://github.com/chakra-ui/zag/blob/e5ba28a01ccab8afa2f11a82b67031a82e2675f5/examples/vanilla-ts/src/lib/machine.ts
//
// MIT License
//
// Copyright (c) 2021 Chakra UI
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import { createScope, INIT_STATE, MachineStatus } from "@zag-js/core";
import { subscribe } from "@zag-js/store";
import { compact, identity, isEqual, isFunction, isString, toArray, warn } from "@zag-js/utils";
import { bindable } from "./bindable";

export class VanillaMachine {
  constructor(machine, userProps = {}) {
    this.machine = machine;
    this.event = { type: "" };
    this.previousEvent = null;
    this.effects = new Map();
    this.transition = null;
    this.cleanups = [];
    this.subscriptions = [];
    this.trackers = [];

    const { id, ids, getRootNode } = userProps;
    this.scope = createScope({ id, ids, getRootNode });

    const props = machine.props?.({ props: compact(userProps), scope: this.scope }) ?? userProps;
    this.prop = (key) => props[key];

    const context = machine.context?.({
      prop: this.prop,
      bindable,
      scope: this.scope,
      flush(fn) {
        queueMicrotask(fn);
      },
      getContext: () => this.ctx,
      getComputed: () => this.computed,
      getRefs: () => this.refs,
    });

    if (context) {
      Object.values(context).forEach((item) => {
        const unsub = subscribe(item.ref, () => this.notify());
        this.cleanups.push(unsub);
      });
    }

    this.ctx = {
      get: (key) => context?.[key].get(),
      set: (key, value) => context?.[key].set(value),
      initial: (key) => context?.[key].initial,
      hash: (key) => {
        const current = context?.[key].get();
        return context?.[key].hash(current);
      },
    };

    this.computed = (key) => {
      return (
        machine.computed?.[key]({
          context: this.ctx,
          event: this.getEvent(),
          prop: this.prop,
          refs: this.refs,
          scope: this.scope,
          computed: this.computed,
        }) ?? {}
      );
    };

    this.refs = createRefs(machine.refs?.({ prop: this.prop, context: this.ctx }) ?? {});

    this.state = bindable(() => ({
      defaultValue: machine.initialState({ prop: this.prop }),
      onChange: (nextState, prevState) => {
        if (prevState) {
          const exitEffects = this.effects.get(prevState);
          exitEffects?.();
          this.effects.delete(prevState);
        }

        if (prevState) {
          this.action(machine.states[prevState]?.exit);
        }

        this.action(this.transition?.actions);

        const cleanup = this.effect(machine.states[nextState]?.effects);
        if (cleanup) this.effects.set(nextState, cleanup);

        if (prevState === INIT_STATE) {
          this.action(machine.entry);
          const cleanup = this.effect(machine.effects);
          if (cleanup) this.effects.set(INIT_STATE, cleanup);
        }

        this.action(machine.states[nextState]?.entry);
      },
    }));
    this.cleanups.push(subscribe(this.state.ref, () => this.notify()));
  }

  send = (event) => {
    if (this.status !== MachineStatus.Started) return;

    queueMicrotask(() => {
      this.previousEvent = this.event;
      this.event = event;

      let currentState = this.state.get();

      const transitions = this.machine.states[currentState].on?.[event.type] ?? this.machine.on?.[event.type];

      const transition = this.choose(transitions);
      if (!transition) return;

      this.transition = transition;
      const target = transition.target ?? currentState;

      const changed = target !== currentState;
      if (changed) {
        this.state.set(target);
      } else {
        this.action(transition.actions);
      }
    });
  };

  start() {
    this.status = MachineStatus.Started;
    this.state.invoke(this.state.initial, INIT_STATE);
    this.setupTrackers();
  }

  stop() {
    this.effects.forEach((fn) => fn?.());
    this.effects.clear();
    this.transition = null;
    this.action(this.machine.exit);

    this.cleanups.forEach((unsub) => unsub());
    this.cleanups = [];

    this.status = MachineStatus.Stopped;
  }

  subscribe = (fn) => {
    this.subscriptions.push(fn);
  };

  status = MachineStatus.NotStarted;

  get service() {
    return {
      state: this.getState(),
      send: this.send,
      context: this.ctx,
      prop: this.prop,
      scope: this.scope,
      refs: this.refs,
      computed: this.computed,
      event: this.getEvent(),
      getStatus: () => this.status,
    };
  }

  publish = () => {
    this.callTrackers();
    this.subscriptions.forEach((fn) => fn(this.service));
  };

  setupTrackers = () => {
    this.machine.watch?.(this.getParams());
  };

  callTrackers = () => {
    this.trackers.forEach(({ deps, fn }) => {
      const next = deps.map((dep) => dep());
      if (!isEqual(fn.prev, next)) {
        fn();
        fn.prev = next;
      }
    });
  };

  getParams = () => ({
    state: this.getState(),
    context: this.ctx,
    event: this.getEvent(),
    prop: this.prop,
    send: this.send,
    action: this.action,
    guard: this.guard,
    track: (deps, fn) => {
      fn.prev = deps.map((dep) => dep());
      this.trackers.push({ deps, fn });
    },
    refs: this.refs,
    computed: this.computed,
    flush: identity,
    scope: this.scope,
    choose: this.choose,
  });

  action = (keys) => {
    const strs = isFunction(keys) ? keys(this.getParams()) : keys;
    if (!strs) return;
    const fns = strs.map((s) => {
      const fn = this.machine.implementations?.actions?.[s];
      if (!fn) warn(`[zag-js] No implementation found for action "${JSON.stringify(s)}"`);
      return fn;
    });
    for (const fn of fns) {
      fn?.(this.getParams());
    }
  };

  guard = (str) => {
    if (isFunction(str)) return str(this.getParams());
    return this.machine.implementations?.guards?.[str](this.getParams());
  };

  effect = (keys) => {
    const strs = isFunction(keys) ? keys(this.getParams()) : keys;
    if (!strs) return;
    const fns = strs.map((s) => {
      const fn = this.machine.implementations?.effects?.[s];
      if (!fn) warn(`[zag-js] No implementation found for effect "${JSON.stringify(s)}"`);
      return fn;
    });
    const cleanups = [];
    for (const fn of fns) {
      const cleanup = fn?.(this.getParams());
      if (cleanup) cleanups.push(cleanup);
    }
    return () => cleanups.forEach((fn) => fn?.());
  };

  choose = (transitions) => {
    return toArray(transitions).find((t) => {
      let result = !t.guard;
      if (isString(t.guard)) result = !!this.guard(t.guard);
      else if (isFunction(t.guard)) result = t.guard(this.getParams());
      return result;
    });
  };

  notify = () => {
    this.publish();
  };

  getEvent = () => ({
    ...this.event,
    current: () => this.event,
    previous: () => this.previousEvent,
  });

  getState = () => ({
    ...this.state,
    matches: (...values) => values.includes(this.state.get()),
    hasTag: (tag) => !!this.machine.states[this.state.get()]?.tags?.includes(tag),
  });
}

function createRefs(refs) {
  const ref = { current: refs };
  return {
    get(key) {
      return ref.current[key];
    },
    set(key, value) {
      ref.current[key] = value;
    },
  };
}
