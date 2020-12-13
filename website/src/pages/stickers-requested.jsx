/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import OldLayout from '../components/old-layout'
import Main from '../components/main'
import { GatsbySeo } from 'gatsby-plugin-next-seo'
import SEO from '../components/SEO'
import Stickers from '../../assets/stickers.svg'

export default () => {
  return (
    <OldLayout>
      <SEO title="Stickers" />
      <GatsbySeo
        title="Stickers requested"
        description={`Wanna get some nice-looking free stickers for your laptop? You can request some from this page.`}
      />
      <Main>
        <Styled.h1>Request placed</Styled.h1>

        <Styled.p>
          We received your request. We'll prepare the stickers and send them
          your way!
        </Styled.p>
        <div>
          <Stickers sx={{ height: 200, width: 200, margin: 'auto' }} />
        </div>
      </Main>
    </OldLayout>
  )
}
