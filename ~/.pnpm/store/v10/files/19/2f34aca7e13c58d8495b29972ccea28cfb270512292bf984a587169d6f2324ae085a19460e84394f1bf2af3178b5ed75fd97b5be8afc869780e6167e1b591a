# @zag-js/core

This package contains a minimal implementation of [XState FSM](https://github.com/statelyai/xstate) for **finite state
machines** with addition of extra features we need for our components.

## Features

- Finite states (non-nested)
- Initial state
- Transitions (object or strings)
- Context
- Entry actions
- Exit actions
- Delayed timeout actions (basically `setTimeout`)
- Delayed interval actions (basically `setInterval`)
- Transition actions
- Boolean guard helpers (`and`, `or`, `not`)
- Basic spawn helpers
- Activities (for state nodes)

> To better understand the state machines, we strongly recommend going though the
> [xstate docs](https://xstate.js.org/docs/) and videos. It'll give you the foundations you need.

## Quick start

**Installation**

```bash
npm i @zag-js/core
# or
yarn add @zag-js/core
```

**Usage (machine):**

```js
import { createMachine } from "@zag-js/core"

const toggleMachine = createMachine({
  id: "toggle",
  initialState() {
    return "inactive"
  },
  states: {
    inactive: { on: { TOGGLE: "active" } },
    active: { on: { TOGGLE: "inactive" } },
  },
})

toggleMachine.start()
console.log(toggleMachine.state.value) // => "inactive"

toggleMachine.send("TOGGLE")
console.log(toggleMachine.state.value) // => "active"

toggleMachine.send("TOGGLE")
console.log(toggleMachine.state.value) // => "inactive"
```

**Usage (service):**

```js
import { createMachine } from "@zag-js/core"

const toggleMachine = createMachine({...})
toggleMachine.start()

toggleService.subscribe((state) => {
  console.log(state.value)
})

toggleService.send("TOGGLE")
toggleService.send("TOGGLE")
toggleService.stop()
```

## API

### `createMachine(config, options)`

Creates a new finite state machine from the config.

| Argument  | Type               | Description                                 |
| --------- | ------------------ | ------------------------------------------- |
| `config`  | object (see below) | The config object for creating the machine. |
| `options` | object (see below) | The optional options object.                |

**Returns:**

A `Machine`, which provides:

- `machine.initialState`: the machine's resolved initial state
- `machine.start()`: the function to start the machine in the specified initial state.
- `machine.stop()`: the function to stop the machine completely. It also cleans up all scheduled actions and timeouts.
- `machine.transition(state, event)`: a transition function that returns the next state given the current `state` and
  `event`. It also performs any delayed, entry or exit side-effects.
- `machine.send(event)`: a transition function instructs the machine to execute a transition based on the event.
- `machine.onTransition(fn)`: a function that gets called when the machine transition function instructs the machine to
  execute a transition based on the event.
- `machine.onChange(fn)`: a function that gets called when the machine's context value changes.
- `machine.state`: the state object that describes the machine at a specific point in time. It contains the following
  properties:
  - `value`: the current state value
  - `previousValue`: the previous state value
  - `event`: the event that triggered the transition to the current state
  - `nextEvents`: the list of events the machine can respond to at its current state
  - `tags`: the tags associated with this state
  - `done`: whether the machine that reached its final state
  - `context`: the current context value
  - `matches(...)`: a function used to test whether the current state matches one or more state values

The machine config has this schema:

### Machine config

- `id` (string) - an identifier for the type of machine this is. Useful for debugging.
- `context` (object) - the extended state data that represents quantitative data (string, number, objects, etc) that can
  be modified in the machine.
- `initial` (string) - the key of the initial state.
- `states` (object) - an object mapping state names (keys) to states
- `on` (object) - an global mapping of event types to transitions. If specified, this event will called if the state
  node doesn't handle the emitted event.

### State config

- `on` (object) - an object mapping event types (keys) to [transitions](#transition-config)

### Transition config

String syntax:

- (string) - the state name to transition to.
  - Same as `{ target: stateName }`

Object syntax:

- `target` (string) - the state name to transition to.
- `actions` (Action | Action[]) - the [action(s)](#action-config) to execute when this transition is taken.
- `guard` (Guard) - the condition (predicate function) to test. If it returns `true`, the transition will be taken.

### Machine options

- `actions?` (object) - a lookup object for your string actions.
- `guards?` (object) - a lookup object for your string guards specified as `guard` in the machine.
- `activities?` (object) - a lookup object for your string activities.
- `delays?` (object) - a lookup object for your string delays used in `after` and `every` config.

### Action config

The action function to execute while transitioning from one state to another. It takes the following arguments:

- `context` (any) - the machine's current `context`.
- `event` (object) - the event that caused the action to be executed.
