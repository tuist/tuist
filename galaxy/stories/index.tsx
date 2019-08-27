import * as React from 'react'
import { storiesOf } from '@storybook/react'
import HomePage from '../frontend/components/pages/home'

const stories = storiesOf('Components', module)

stories.add('Home', () => <HomePage />, { info: { inline: true } })
