import React from 'react'

import Highlights from './highlights'
import renderer from 'react-test-renderer'

describe('Higlights', () => {
  it('renders the right HTML', () => {
    const tree = renderer.create(<Highlights />).toJSON()
    expect(tree).toMatchSnapshot()
  })
})
