# @zag-js/checkbox

Core logic for the checkbox widget implemented as a state machine

## **Installation**

```sh
yarn add @zag-js/checkbox
# or
npm i @zag-js/checkbox
```

## Technical Considerations

- When the checkbox is surrounded by a form, we consider the effect of form "reset" event with a `trackFormReset`
  activity in the machine.
- When the checkbox is surrounded by fieldset and the fieldset is disabled, we react to set sync the disabled state
  accordingly with a `trackFieldsetDisabled` activity in the machine.
- A name can be passed to the machine object during initialization, which we pass to the input, to ease use in forms.
- The API exposes a `setChecked` method to programmatically control the checkbox's state. We automatically dispatch a
  native event when this is done, so when used in a form, the form can detect those changes.
- The checkbox machine accepts an `indeterminate` key, to make it indeterminate by default. The API also exposes a
  `setIndeterminate` method, to toggle this programmatically.
- The API exposed a `view` variable of type `"checked" | "unchecked" | "mixed"` so you can render parts, based on the
  current visual state of the checkbox. `mixed` is when the checkbox is indeterminate.

## Contribution

Yes please! See the [contributing guidelines](https://github.com/chakra-ui/zag/blob/main/CONTRIBUTING.md) for details.

## Licence

This project is licensed under the terms of the [MIT license](https://github.com/chakra-ui/zag/blob/main/LICENSE).
