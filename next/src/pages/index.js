import * as React from 'react'
import MainLayout from '../layouts/MainLayout'
import tw from 'twin.macro'
import featureManifestImage from './images/feature-manifest.svg'
import featureHelpersImage from './images/feature-helpers.svg'
import featureScaffoldImage from './images/feature-scaffold.svg'
import communityGitHubImage from './images/community-github.svg'
import communitySlackImage from './images/community-slack.svg'
import companiesImage from './images/companies.svg'

const Features = () => {
  const featureCSS = [tw`space-y-4`]
  const featureTermCSS = [
    tw`text-white text-center font-tuist-mono text-lg md:text-xl md:text-left`,
  ]
  const featureDefinitionCSS = [
    tw`font-tuist text-gray-600 text-lg text-center md:text-left md:text-xl`,
  ]
  const featureImageCSS = [tw`mx-auto`]

  return (
    <section css={[tw`bg-primary-dark px-10 py-10 md:py-20`]}>
      <div css={[tw`mx-auto w-full md:max-w-5xl`]}>
        <div css={[tw`space-y-10`]}>
          <h3
            css={[
              tw`text-white font-bold text-2xl text-center md:text-left md:font-extrabold md:text-3xl font-tuist`,
            ]}
          >
            Feature highlights
          </h3>
          <dl
            css={[
              tw`grid gap-4 justify-items-center grid-rows-3 grid-cols-1 md:grid-rows-1 md:grid-cols-3`,
            ]}
          >
            <div css={featureCSS}>
              <img src={featureManifestImage} css={featureImageCSS} />
              <dt css={featureTermCSS}>Swift Manifest</dt>
              <dd css={featureDefinitionCSS}>
                Define projects using a simple Swift DSL inside Xcode
              </dd>
            </div>
            <div css={featureCSS}>
              <img src={featureHelpersImage} css={featureImageCSS} />
              <dt css={featureTermCSS}>Project description helpers</dt>
              <dd css={featureDefinitionCSS}>
                Create abstractions to define your projects consistently
              </dd>
            </div>
            <div css={featureCSS}>
              <img src={featureScaffoldImage} css={featureImageCSS} />
              <dt css={featureTermCSS}>Scaffold</dt>
              <dd css={featureDefinitionCSS}>
                Automate feature creation by generating a target pre-configured
                with everything you need
              </dd>
            </div>
          </dl>
        </div>
      </div>
    </section>
  )
}

const Companies = () => {
  return (
    <section css={tw`px-10 py-10 md:py-20 relative`}>
      <div css={tw`mx-auto w-full md:max-w-5xl relative`}>
        <div css={[tw`static z-0 grid grid-cols-2 grid-rows-1`]}>
          <h2 css={tw`text-primary font-extrabold text-5xl font-tuist`}>
            You'll be in great company
          </h2>
          <figure
            css={tw`bg-primary text-white rounded-lg p-8 font-tuist space-y-5`}
          >
            <blockquote css={tw`text-2xl`}>
              Everyone in my team can create their own frameworks in a few
              seconds which is amazing and really helps to speed up things and
              work efficiently!
            </blockquote>
            <figcaption css={tw`text-xl text-purple-100 text-right`}>
              iOS lead @ Bloomberg
            </figcaption>
          </figure>
        </div>
        <div css={[tw`absolute z-10 w-full grid grid-cols-8 grid-rows-6`]}>
          <img
            css={tw`col-start-1 col-end-5 row-start-2 row-end-6 object-contain bg-green-200`}
            src={companiesImage}
          />
        </div>
      </div>
    </section>
  )
}

const Community = () => {
  const textCSS = tw`text-xl text-center font-tuist md:text-2xl md:text-left`
  const highlightCSS = tw`bg-purple-200 font-bold p-1`
  const sectionCSS = tw`space-y-10`
  return (
    <section css={tw`px-10 py-10 md:py-20`}>
      <div
        css={tw`mx-auto w-full md:max-w-5xl grid justify-items-center gap-4 grid-cols-1 grid-rows-2 md:gap-10 md:grid-cols-2 md:grid-rows-1`}
      >
        <div css={sectionCSS}>
          <div css={textCSS}>
            Benefit from extensive documentation and our{' '}
            <span css={highlightCSS}>Slack community</span> for support to scale
            Xcode projects at any stage
          </div>
          <img css={tw`mx-auto`} src={communitySlackImage} />
        </div>
        <div css={sectionCSS}>
          <img css={tw`mx-auto`} src={communityGitHubImage} />
          <div css={textCSS}>
            <span css={highlightCSS}>Join contributors</span> from all over the
            world to shape the next versions of Tuist. From small contributions
            to important features, mentors will help you go get started.
          </div>
        </div>
      </div>
    </section>
  )
}
const IndexPage = () => {
  return (
    <MainLayout>
      <Features />
      <Companies />
      <Community />
    </MainLayout>
  )
}

export default IndexPage
