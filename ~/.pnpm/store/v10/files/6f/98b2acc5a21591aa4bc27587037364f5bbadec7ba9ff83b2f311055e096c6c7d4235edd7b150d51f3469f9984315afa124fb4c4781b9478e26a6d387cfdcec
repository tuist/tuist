# Sonner for Vue

[![NPM][npmBadge]][npmUrl]
[![Minzip Package][bundlePhobiaBadge]][bundlePhobiaUrl]
[![NPM Download][npmDtBadge]][npmDtUrl]

[npmBadge]: https://img.shields.io/npm/v/vue-sonner.svg?maxAge=2592000
[npmUrl]: https://www.npmjs.com/package/vue-sonner
[npmDtBadge]: https://img.shields.io/npm/dt/vue-sonner.svg
[npmDtUrl]: https://www.npmjs.com/package/vue-sonner
[bundlePhobiaBadge]: https://img.shields.io/bundlephobia/minzip/vue-sonner
[bundlePhobiaUrl]: https://bundlephobia.com/package/vue-sonner@latest

> An opinionated toast component for Vue. It's a Vue port of Sonner

## Preview

https://user-images.githubusercontent.com/6118824/228208185-be5aefd4-7fa8-4f95-a41c-88a60c0e2800.mp4

## Introduction

`Vue Sonner` is an opinionated toast component for Vue. It's customizable, but styled by default. Comes with a swipe to dismiss animation.

## Table of Contents

<details>

<summary>TOC</summary>

- [Sonner for Vue](#sonner-for-vue)
  - [Preview](#preview)
  - [Introduction](#introduction)
  - [Table of Contents](#table-of-contents)
  - [Installation](#installation)
  - [Test](#test)
    - [Launching the test](#launching-the-test)
    - [Build and watch for change in order to fix the test](#build-and-watch-for-change-in-order-to-fix-the-test)
  - [Usage](#usage)
    - [For Vue 3](#for-vue-3)
    - [For Nuxt 3](#for-nuxt-3)
    - [CDN Link](#cdn-link)
  - [Types](#types)
    - [Default](#default)
    - [Success](#success)
    - [Error](#error)
    - [Action](#action)
    - [Promise](#promise)
    - [Custom Component](#custom-component)
  - [Customization](#customization)
    - [Headless](#headless)
    - [Theme](#theme)
    - [Position](#position)
    - [Expanded](#expanded)
    - [Styling for all toasts](#styling-for-all-toasts)
    - [Styling for individual toast](#styling-for-individual-toast)
    - [Tailwind CSS](#tailwind-css)
    - [Changing Icon](#changing-icon)
    - [Close button](#close-button)
    - [Rich colors](#rich-colors)
    - [Custom offset](#custom-offset)
    - [On Close Callback](#on-close-callback)
    - [Persisting toasts](#persisting-toasts)
    - [Dismissing toasts programmatically](#dismissing-toasts-programmatically)
    - [Keyboard focus](#keyboard-focus)
  - [Inspiration](#inspiration)
  - [License](#license)

</details>

## Installation

To start using the library, install it in your project:

```bash
pnpm install vue-sonner
or
yarn add vue-sonner
```

## Test

To run the test you need two separate CLI window :

### Launching the test

To launch the test, you need to go in the test directory

```bash
cd ./test
```

and launch the following command

```bash
cd ./test
pnpm test:e2e --ui
```

### Build and watch for change in order to fix the test

This command will build the vue-sonner library in lib mode, and add a watch so every time you modify the code of the library, you will have a new bundle and can run the test again.

```bash
pnpm build:dev
```

## Usage

### For Vue 3

```html
<!-- App.vue -->
<template>
  <Toaster />
  <button @click="() => toast('My first toast')">Render a toast</button>
</template>

<script lang="ts" setup>
  import { Toaster, toast } from 'vue-sonner'
</script>
```

### For Nuxt 3

Use `vue-sonner/nuxt` module

```ts
// nuxt.config.ts
export default defineNuxtConfig({
  ...
  modules: ['vue-sonner/nuxt']
})
```

Use `Toaster` component and `$toast` function anywhere in the Vue SFC

```html
<!-- app.vue -->
<template>
  <div>
    <Toaster position="top-right" />
    <button @click="() => $toast('My first toast')">Render a toast</button>
  </div>
</template>

<script setup lang="ts">
  const { $toast } = useNuxtApp()
</script>
```

### CDN Link

**EMS version**

```ts
https://cdn.jsdelivr.net/npm/vue-sonner/+esm
```

**UMD version**

```ts
https://www.unpkg.com/vue-sonner@0.3.1/lib/vue-sonner.umd.cjs
```

## Types

### Default

Most basic toast. You can customize it (and any other type) by passing an options object as the second argument.

```ts
toast('Event has been created')
```

With custom description:

```ts
toast('Event has been created', {
  description: 'Monday, January 3rd at 6:00pm'
})
```

### Success

Renders a checkmark icon in front of the message.

```ts
toast.success('Event has been created')
```

### Error

Renders an error icon in front of the message.

```ts
toast.error('Event has not been created')
```

### Action

Renders a button.

```ts
toast('Event has been created', {
  action: {
    label: 'Undo',
    onClick: () => console.log('Undo')
  }
})
```

### Promise

Starts in a loading state and will update automatically after the promise resolves or fails.

You can pass a function to the success/error messages to incorporate the result/error of the promise.

```ts
toast.promise(() => new Promise((resolve) => setTimeout(resolve, 2000)), {
  loading: 'Loading',
  success: (data: any) => 'Success',
  error: (data: any) => 'Error'
})
```

### Custom Component

You can pass a Vue Component as the first argument instead of a string to render custom Component while maintaining default styling. You can use the headless version below for a custom, unstyled toast.

```html
<script lang="ts" setup>
  import { defineComponent, h, markRaw } from 'vue'

  const CustomDiv = defineComponent({
    setup() {
      return () =>
        h('div', {
          innerHTML: 'A custom toast with unstyling'
        })
    }
  })

  toast(markRaw(CustomDiv))
</script>
```

## Customization

### Headless

You can use `toast.custom` to render an unstyled toast with custom jsx while maintaining the functionality.

```vue
<script lang="ts" setup>
import { markRaw } from 'vue'

import HeadlessToast from './HeadlessToast.vue'

toast.custom(markRaw(HeadlessToast), { duration: 999999 })
</script>
```

### Theme

You can change the theme using the `theme` prop. Default theme is light.

```html
<Toaster theme="dark" />
```

### Position

You can change the position through the `position` prop on the `<Toaster />` component. Default is `top-right`.

```html
<!-- Available positions -->
<!-- top-left, top-center, top-right, bottom-left, bottom-center, bottom-right -->

<Toaster position="top-center" />
```

### Expanded

Toasts can also be expanded by default through the `expand` prop. You can also change the amount of visible toasts which is 3 by default.

```html
<Toaster expand :visibleToasts="9" />
```

### Styling for all toasts

You can style your toasts globally with the `toastOptions` prop in the `Toaster` component.

```html
<Toaster
  :toastOptions="{
    style: { background: 'red' },
    class: 'my-toast',
    descriptionClass: 'my-toast-description'
  }"
/>
```

### Styling for individual toast

```ts
toast('Event has been created', {
  style: {
    background: 'red'
  },
  class: 'my-toast',
  descriptionClass: 'my-toast-description'
})
```

### Tailwind CSS

The preferred way to style the toasts with tailwind is by using the `unstyled` prop. That will give you an unstyled toast which you can then style with tailwind.

```vue
<Toaster
  :toastOptions="{
    unstyled: true,
    classes: {
      toast: 'bg-blue-400',
      title: 'text-red-400',
      description: 'text-red-400',
      actionButton: 'bg-zinc-400',
      cancelButton: 'bg-orange-400',
      closeButton: 'bg-lime-400'
    }
  }"
/>
```

You can do the same when calling `toast()`.

```ts
toast('Hello World', {
  unstyled: true,
  classes: {
    toast: 'bg-blue-400',
    title: 'text-red-400 text-2xl',
    description: 'text-red-400',
    actionButton: 'bg-zinc-400',
    cancelButton: 'bg-orange-400',
    closeButton: 'bg-lime-400'
  }
})
```

Styling per toast type is also possible.

```vue
<Toaster
  :toastOptions="{
    unstyled: true,
    classes: {
      error: 'bg-red-400',
      success: 'text-green-400',
      warning: 'text-yellow-400',
      info: 'bg-blue-400'
    }
  }"
/>
```

### Changing Icon

You can change the default icons using slots:

```vue
<Toaster>
  <template #loading-icon>
    <LoadingIcon />
  </template>
  <template #success-icon>
    <SuccessIcon />
  </template>
  <template #error-icon>
    <ErrorIcon />
  </template>
  <template #info-icon>
    <InfoIcon />
  </template>
  <template #warning-icon>
    <WarningIcon />
  </template>
</Toaster>
```

### Close button

Add a close button to all toasts that shows on hover by adding the `closeButton` prop.

```html
<Toaster closeButton />
```

### Rich colors

You can make error and success state more colorful by adding the `richColors` prop.

```html
<Toaster richColors />
```

### Custom offset

Offset from the edges of the screen.

```html
<Toaster offset="80px" />
```

### On Close Callback

You can pass `onDismiss` and `onAutoClose` callbacks. `onDismiss` gets fired when either the close button gets clicked or the toast is swiped. `onAutoClose` fires when the toast disappears automatically after it's timeout (`duration` prop).

```ts
toast('Event has been created', {
  onDismiss: (t) => console.log(`Toast with id ${t.id} has been dismissed`),
  onAutoClose: (t) =>
    console.log(`Toast with id ${t.id} has been closed automatically`)
})
```

### Persisting toasts

You can change the duration of each toast by using the duration property, or change the duration of all toasts like this:

```html
<Toaster :duration="10000" />
```

```ts
toast('Event has been created', {
  duration: 10000
})

If you want a toast to stay on screen forever, you can set the duration to `Infinity`.

// Persisent toast
toast('Event has been created', {
  duration: Infinity
})
```

### Dismissing toasts programmatically

To remove a toast programmatically use `toast.dismiss(id)`.

```ts
const toastId = toast('Event has been created')

toast.dismiss(toastId)
```

You can also dismiss all toasts at once by calling `toast.dismiss()` without an id.

```ts
toast.dismiss()
```

### Keyboard focus

You can focus on the toast area by pressing ⌥/alt + T. You can override it by providing an array of event.code values for each key.

```html
<Toaster hotkey="['KeyC']" />
```

## Inspiration

- [sonner](https://github.com/emilkowalski/sonner) - An opinionated toast component for React.

## License

MIT [@xiaoluoboding](https://github.com/xiaoluoboding)
