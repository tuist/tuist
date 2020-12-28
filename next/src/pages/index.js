import * as React from 'react'
import MainLayout from '../layouts/MainLayout'
import tw from 'twin.macro'

const Features = () => {
  return <div css={[tw`bg-primary`]}>Features</div>
}
const IndexPage = () => {
  return (
    <MainLayout>
      <Features />
    </MainLayout>
  )
}

export default IndexPage
