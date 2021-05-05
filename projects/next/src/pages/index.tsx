/** @jsx jsx */
import { jsx } from 'theme-ui'
import * as React from 'react'
import MainLayout from '../layouts/MainLayout'
import featureManifestImage from './images/feature-manifest.svg'
import featureHelpersImage from './images/feature-helpers.svg'
import featureScaffoldImage from './images/feature-scaffold.svg'
import communityGitHubImage from './images/community-github.svg'
import communitySlackImage from './images/community-slack.svg'
import companiesImage from './images/companies.svg'

const FeaturesSection = (): React.ReactElement => {
  return <section sx={{ bg: 'red' }}>Yolo</section>
}
const IndexPage = (): React.ReactElement => {
  return (
    <MainLayout>
      <FeaturesSection />
    </MainLayout>
  )
}

export default IndexPage
