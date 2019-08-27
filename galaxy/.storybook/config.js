import { configure } from '@storybook/react'
// automatically import all files ending in *.stories.tsx
console.log('yolo')

function loadStories() {
  require('../stories')
}

configure(loadStories, module)
