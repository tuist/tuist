/** @jsx jsx */
import { jsx, Styled, useThemeUI } from 'theme-ui'
import Layout from '../components/layout'
import Main from '../components/main'
import { Link, useStaticQuery, graphql } from 'gatsby'
import Heart from '../../assets/heart.svg'
import Paper from '../../assets/paper.svg'
import Eye from '../../assets/eye.svg'
import Warning from '../../assets/warning.svg'
import Message from '../../assets/message.svg'
import Framework from '../../assets/framework.svg'
import Arrow from '../../assets/arrow.svg'
import Swift from '../../assets/swift.svg'
import posed from 'react-pose'
import Code from '../gatsby-plugin-theme-ui/code'
import SEO from '../components/SEO'
import Soundcloud from '../../assets/soundcloud.svg'
import Devengo from '../../assets/devengo.svg'
import FreeNow from '../../assets/freenow.svg'
import Ackee from '../../assets/ackee.svg'
import { lighten } from '@theme-ui/color'
import stream from "../logos/stream.svg"

const PressableButton = posed.div({
  hoverable: true,
  pressable: true,
  init: { scale: 1 },
  hover: { scale: 1.1 },
  press: { scale: 1.05 },
})

const GradientButton = ({ title, link }) => {
  return (
    <Link to={link} sx={{ textDecoration: 'none' }}>
      <PressableButton
        sx={{
          fontSize: 2,
          mt: 4,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: (theme) =>
            `linear-gradient(90deg, ${theme.colors.primary} 0%, ${theme.colors.secondary} 100%)`,
          color: 'background',
          p: 4,
          height: '40px',
          borderRadius: '40px',
        }}
      >
        {title}
      </PressableButton>
    </Link>
  )
}

const Steroids = () => {
  const { theme } = useThemeUI()
  return (
    <div>
      <Main>
        <div
          sx={{
            display: 'flex',
            flexDirection: ['column-reverse', 'row'],
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <div>
            <Framework sx={{ mr: [0, 3], mt: [3, 0] }} />
          </div>
          <div
            sx={{
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
            }}
          >
            <h1
              className="mt-2 text-3xl leading-8 font-extrabold tracking-tight sm:text-5xl sm:leading-10"
              sx={{ color: 'text' }}
            >
              Xcode on steroids
            </h1>
            <div
              className="mt-3 text-3xl leading-8 font-extrabold tracking-tight sm:text-4xl sm:leading-10"
              sx={{
                textAlign: 'center',
                color: 'primary',
              }}
            >
              <span>Easy</span> and <span>fast</span>
            </div>
            <div
              className="mt-4 max-w-2xl text-xl leading-7 lg:mx-auto"
              sx={{
                color: 'gray',
                mt: [4, 4],
                textAlign: 'center',
              }}
            >
              Bootstrap, maintain, and interact with
              <br /> Xcode projects at any scale
            </div>
            <GradientButton title="GET STARTED" link="https://docs.tuist.io/" />

            <div
              sx={{ color: 'gray', mt: 5, textAlign: 'center' }}
              className="mt-2 text-base leading-6"
            >
              Trusted by the following companies and projects:
            </div>
            <div
              sx={{
                mt: 3,
                display: 'flex',
                flexDirection: 'row',
                alignItems: 'center',
                justifyContent: 'center',
                flexWrap: 'wrap',
              }}
            >
              <a href="https://soundcloud.com" target="__blank">
                <Soundcloud
                  sx={{ height: 30, path: { fill: theme.colors.gray } }}
                />
              </a>
              <Devengo
                sx={{
                  ml: 3,
                  height: 30,
                  width: 150,
                  path: { fill: theme.colors.gray },
                }}
              />
              <a href="https://free-now.com/" target="__blank" sx={{ ml: 2 }}>
                <FreeNow
                  sx={{
                    height: 25,
                    width: 110,
                    path: { fill: theme.colors.gray },
                  }}
                />
              </a>
              <a
                href="https://www.ackee.cz/en"
                target="__blank"
                sx={{ ml: 1, mt: 2 }}
              >
                <Ackee
                  sx={{
                    height: 33,
                    width: 95,
                    path: { fill: theme.colors.gray },
                  }}
                />
              </a>
            </div>
          </div>
          <div sx={{ display: 'block' }}>
            <Swift sx={{ alignSelf: 'flex-start', ml: [0, 6] }} />
          </div>
        </div>
      </Main>
    </div>
  )
}

const SectionTitle = ({ title, subtitle, description }) => {
  return (
    <div
      sx={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        zIndex: 1,
      }}
    >
      <div sx={{ fontSize: 0, color: 'primary', textAlign: 'center' }}>
        {subtitle}
      </div>
      <div sx={{ fontSize: 3, fontWeight: 'heading', textAlign: 'center' }}>
        {title}
      </div>
      <div
        sx={{ color: 'text', mt: 2, textAlign: 'center', textAlign: 'center' }}
      >
        {description}
      </div>
    </div>
  )
}

const ManifestWindow = () => {
  const exampleCode = `
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.featureFramework(
  name: "Home",
  dependencies: [
    .project(target: "Features", path: "../Features"),
    .framework(path: "Carthage/Build/iOS/SnapKit.framework")
    .package(product: "KeychainSwift")
  ]
)
  `
  const buttonStyle = { width: 4, height: 4, borderRadius: 2 }
  const radius = 1
  return (
    <div
      sx={{
        display: 'flex',
        flexDirection: 'column',
        width: ['95%', '70%'],
        mt: 5,
      }}
    >
      <div
        sx={{
          bg: 'muted',
          height: 20,
          borderTopLeftRadius: radius,
          borderTopRightRadius: radius,
          display: 'flex',
          flexDirection: 'row',
          alignItems: 'center',
          borderColor: 'accent',
          borderStyle: 'solid',
          borderWidth: 1,
          flex: 1,
          py: 1,
          px: 2,
        }}
      >
        <div sx={{ ...buttonStyle, bg: 'red' }} />
        <div sx={{ ...buttonStyle, ml: 1, bg: 'yellow' }} />
        <div sx={{ ...buttonStyle, ml: 1, bg: 'green' }} />
        <div sx={{ fontSize: 1, color: 'text', ml: 3 }}>Project.swift</div>
      </div>
      <div
        sx={{
          bg: 'muted',
          borderBottomLeftRadius: radius,
          borderBottomRightRadius: radius,
          borderColor: 'accent',
          borderStyle: 'solid',
          borderWidth: '0px 1px 1px 1px',
        }}
      >
        <Code className="language-swift" my="0" showCopy={false} bg="muted">
          {exampleCode}
        </Code>
      </div>
    </div>
  )
}

const Workspaces = () => {
  return (
    <div sx={{ position: 'relative', overflow: 'hidden', mt: 5 }}>
      <Main>
        <div
          sx={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
          }}
        >
          <div className="lg:text-center">
            <p
              className="text-base leading-6 font-semibold tracking-wide uppercase"
              sx={{ color: 'primary' }}
            >
              A user-friendly language
            </p>
            <h3
              className="mt-2 text-3xl leading-8 font-extrabold tracking-tight sm:text-4xl sm:leading-10"
              sx={{ color: 'text' }}
            >
              Project.swift
            </h3>
            <p
              className="mt-4 max-w-2xl text-xl leading-7 lg:mx-auto"
              sx={{ color: 'gray' }}
            >
              Make maintaining projects everyone's task by describing them using
              a plain language. And... no more Git conflicts!
            </p>
          </div>
          <ManifestWindow />
        </div>
      </Main>
    </div>
  )
}

const PosedFeature = posed.div({
  hidden: { opacity: 0 },
  shown: { opacity: 1 },
})

const Feature = ({ color, name, description, children }) => {
  return (
    <PosedFeature
      sx={{
        flex: '0 0 30%',
        display: 'flex',
        flexDirection: 'column',
        width: ['100%', '33%'],
        alignItems: 'center',
        mb: 3,
      }}
    >
      <div
        sx={{
          width: 56,
          height: 56,
          borderRadius: 33,
          bg: color,
          display: 'flex',
          justifyContent: 'center',
          alignItems: 'center',
        }}
      >
        {children}
      </div>
      <div sx={{ mt: 3, fontWeight: 'heading' }}>{name}</div>
      <div sx={{ textAlign: 'center', color: 'text' }}>{description}</div>
    </PosedFeature>
  )
}

const Testimonies = () => {
  const { theme } = useThemeUI()
  const testimonies = [
    {
      name: 'Kassem Wridan',
      testimony:
        'By leveraging Tuist libraries, we’ve built tooling to help us manage and scale our Xcode projects in a safe and consistent manner. Our team has also contributed back to the community to help other developers tame their large projects.',
      role: 'iOS developer',
      company: 'Bloomberg',
      avatarUrl: 'https://avatars1.githubusercontent.com/u/11914919?s=460',
    },
    {
      name: 'Romain Boulay',
      testimony:
        'Tuist has delivered more than the SoundCloud iOS Collective expected! We aimed to make modularization more accessible and maintainable. We got this... and better build times!.',
      role: 'iOS lead',
      company: 'SoundCloud',
      avatarUrl: 'https://avatars2.githubusercontent.com/u/169323?s=460',
    },
    {
      name: 'Oliver Atkinson',
      testimony:
        'It has really helped out the team and project by creating an environment where defining new modules is easy, modularity allows us to focus and become experts in our individual domains.',
      role: 'Senior iOS developer',
      company: 'Sky',
      avatarUrl:
        'https://en.gravatar.com/userimage/41347978/456ffd8f0ef3f52c6e38f9003f4c51fa.jpg?size=460',
    },
    {
      name: 'Natan Rolnik',
      testimony:
        'Tuist brings many advantages to our routines when working with Xcode. The first is saying goodbye to Xcode project merge conflicts, which is a result of the project generation. We don’t need to stop using Xcode, on the contrary, we take the good parts, and leave the complicated ones to Tuist: dealing with targets’ dependencies, declaring Swift packages or xcframeworks, and structuring our source files in a more organized way towards a better modularization.\n\nWe’re looking forward to use Tuist’s upcoming caching feature, which will drastically improve build times, in our workflow and in the CI.',
      role: 'iOS infrastructure',
      company: 'Houzz',
      avatarUrl:
        'https://gravatar.com/avatar/c7af4f539e54c0c2b159b8d35c506306?s=600',
    },
    {
      name: 'Tyler Neveldine',
      testimony:
        'Tuist centralizes our entire workspace’s configuration and describes it in a language that we all understand. This increases the readability and approachability of our project tenfold.',
      role: 'iOS lead',
      company: 'Dynamic Signal',
      avatarUrl:
        'https://pbs.twimg.com/profile_images/999765687777148928/wSJxk3Ni_400x400.jpg',
    },
  ]
  const testimony = testimonies[Math.floor(Math.random() * testimonies.length)]
  return (
    <div
      sx={{
        position: 'relative',
        flexDirection: 'column',
        alignItems: 'stretch',
      }}
    >
      <div>
        <Main py="0">
          <div
            sx={{
              display: 'flex',
              flexDirection: 'column',
              pt: 4,
            }}
          >
            <div className="lg:text-center">
              <p
                className="text-base leading-6 font-semibold tracking-wide uppercase"
                sx={{ color: 'primary' }}
              >
                Testimonies
              </p>
              <h3
                className="mt-2 text-3xl leading-8 font-extrabold tracking-tight sm:text-4xl sm:leading-10"
                sx={{ color: 'text' }}
              >
                You don't need a tooling team
              </h3>
              <p
                className="mt-4 max-w-2xl text-xl leading-7 lg:mx-auto"
                sx={{ color: 'gray' }}
              >
                Tuist is already trusted by companies that let us do the
                heavy-lifting and complex work for them.
              </p>
            </div>

            <section className="overflow-hidden" sx={{ bg: 'background' }}>
              <div className="relative max-w-screen-xl mx-auto pt-20 pb-12 px-4 sm:px-6 lg:px-8 lg:py-20">
                <svg
                  className="absolute top-full left-0 transform translate-x-80 -translate-y-24 lg:hidden"
                  width={784}
                  height={404}
                  fill="none"
                  viewBox="0 0 784 404"
                >
                  <defs>
                    <pattern
                      id="e56e3f81-d9c1-4b83-a3ba-0d0ac8c32f32"
                      x={0}
                      y={0}
                      width={20}
                      height={20}
                      patternUnits="userSpaceOnUse"
                    >
                      <rect
                        x={0}
                        y={0}
                        width={4}
                        height={4}
                        fill={theme.colors.muted}
                      />
                    </pattern>
                  </defs>
                  <rect
                    width={784}
                    height={404}
                    fill={'url(#56409614-3d62-4985-9a10-7ca758a8f4f0)'}
                  />
                </svg>
                <svg
                  className="hidden lg:block absolute right-full top-1/2 transform translate-x-1/2 -translate-y-1/2"
                  width={404}
                  height={784}
                  fill="none"
                  viewBox="0 0 404 784"
                >
                  <defs>
                    <pattern
                      id="56409614-3d62-4985-9a10-7ca758a8f4f0"
                      x={0}
                      y={0}
                      width={20}
                      height={20}
                      patternUnits="userSpaceOnUse"
                    >
                      <rect
                        x={0}
                        y={0}
                        width={4}
                        height={4}
                        className="text-gray-200"
                        fill={theme.colors.muted}
                      />
                    </pattern>
                  </defs>
                  <rect
                    width={404}
                    height={784}
                    fill={'url(#56409614-3d62-4985-9a10-7ca758a8f4f0)'}
                  />
                </svg>
                <div className="relative lg:flex lg:items-center">
                  <div className="hidden lg:block lg:flex-shrink-0">
                    <img
                      className="h-64 w-64 rounded-full xl:h-80 xl:w-80"
                      src={testimony.avatarUrl}
                      alt=""
                    />
                  </div>
                  <div className="relative lg:ml-10">
                    <svg
                      className="absolute top-0 left-0 transform -translate-x-8 -translate-y-24 h-36 w-36 opacity-25"
                      stroke={theme.colors.primary}
                      fill="none"
                      viewBox="0 0 144 144"
                    >
                      <path
                        strokeWidth={2}
                        d="M41.485 15C17.753 31.753 1 59.208 1 89.455c0 24.664 14.891 39.09 32.109 39.09 16.287 0 28.386-13.03 28.386-28.387 0-15.356-10.703-26.524-24.663-26.524-2.792 0-6.515.465-7.446.93 2.327-15.821 17.218-34.435 32.11-43.742L41.485 15zm80.04 0c-23.268 16.753-40.02 44.208-40.02 74.455 0 24.664 14.891 39.09 32.109 39.09 15.822 0 28.386-13.03 28.386-28.387 0-15.356-11.168-26.524-25.129-26.524-2.792 0-6.049.465-6.98.93 2.327-15.821 16.753-34.435 31.644-43.742L121.525 15z"
                      />
                    </svg>
                    <blockquote>
                      <div
                        className="text-2xl leading-9 font-medium"
                        sx={{ color: 'text' }}
                      >
                        <p>{testimony.testimony}</p>
                      </div>
                      <footer className="mt-8">
                        <div className="flex">
                          <div className="flex-shrink-0 lg:hidden">
                            <img
                              className="h-12 w-12 rounded-full"
                              src={testimony.avatarUrl}
                              alt=""
                            />
                          </div>
                          <div className="ml-4 lg:ml-0">
                            <div
                              className="text-base leading-6 font-medium"
                              sx={{ color: 'text' }}
                            >
                              {testimony.name}
                            </div>
                            <div
                              className="text-base leading-6 font-medium"
                              sx={{ color: 'primary' }}
                            >
                              {testimony.role}, {testimony.company}
                            </div>
                          </div>
                        </div>
                      </footer>
                    </blockquote>
                  </div>
                </div>
              </div>
            </section>
          </div>
        </Main>
      </div>
    </div>
  )
}

const Contribute = () => {
  return (
    <Main>
      <div sx={{ bg: 'background' }}>
        <div className="max-w-screen-xl mx-auto text-center py-20 px-4 sm:px-6 lg:py-16 lg:px-8">
          <h2
            className="text-3xl leading-9 font-extrabold tracking-tight sm:text-4xl sm:leading-10"
            sx={{ color: 'text' }}
          >
            Ready to dive in?
            <br />
            You are just a command away.
          </h2>
          <div className="mt-8 flex justify-center">
            <div className="inline-flex rounded-md shadow">
              <Link
                to="https://docs.tuist.io"
                sx={{
                  color: 'background',
                  bg: 'primary',
                  '&:hover': { bg: lighten('primary', 0.05) },
                }}
                className="inline-flex items-center justify-center px-5 py-3 border border-transparent text-base leading-6 font-medium rounded-md text-white focus:outline-none focus:shadow-outline transition duration-150 ease-in-out"
              >
                Get started
              </Link>
            </div>
            <div className="ml-3 inline-flex">
              <Link
                to="https://docs.tuist.io/contributors/get-started"
                sx={{
                  color: 'background',
                  bg: lighten('secondary', 0.2),
                  '&:hover': { bg: lighten('secondary', 0.25) },
                }}
                className="inline-flex items-center justify-center px-5 py-3 border border-transparent text-base leading-6 font-medium rounded-md bg-indigo-100 hover:bg-indigo-50 focus:outline-none focus:shadow-outline focus:border-indigo-300 transition duration-150 ease-in-out"
              >
                Contribute
              </Link>
            </div>
          </div>
        </div>
      </div>
    </Main>
  )
}

const Principles = () => {
  const { theme } = useThemeUI()
  return (
    <Main>
      <div className="py-12" sx={{ bg: 'background' }}>
        <div className="max-w-screen-xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="lg:text-center">
            <p
              className="text-base leading-6 font-semibold tracking-wide uppercase"
              sx={{ color: 'primary' }}
            >
              Features
            </p>
            <h3
              className="mt-2 text-3xl leading-8 font-extrabold tracking-tight sm:text-4xl sm:leading-10"
              sx={{ color: 'text' }}
            >
              Developers love simple things
            </h3>
            <p
              className="mt-4 max-w-2xl text-xl leading-7 lg:mx-auto"
              sx={{ color: 'gray' }}
            >
              We take care of the complex things — you focus on building great
              apps
            </p>
          </div>
          <div className="mt-10">
            <ul className="md:grid md:grid-cols-2 md:gap-x-8 md:gap-y-10">
              <li>
                <div className="flex">
                  <div className="flex-shrink-0">
                    <div
                      className="flex items-center justify-center h-12 w-12 rounded-md text-white"
                      sx={{ bg: 'secondary' }}
                    >
                      <Heart sx={{ path: { fill: theme.colors.background } }} />
                    </div>
                  </div>
                  <div className="ml-4">
                    <h5
                      className="text-lg leading-6 font-medium"
                      sx={{ color: 'text' }}
                    >
                      Plain and easy language
                    </h5>
                    <p
                      className="mt-2 text-base leading-6"
                      sx={{ color: 'gray' }}
                    >
                      Describe your projects as you think about them. Build
                      settings, phases and other intricacies become
                      implementation details.
                    </p>
                  </div>
                </div>
              </li>
              <li className="mt-10 md:mt-0">
                <div className="flex">
                  <div className="flex-shrink-0">
                    <div
                      className="flex items-center justify-center h-12 w-12 rounded-md text-white"
                      sx={{ bg: 'secondary' }}
                    >
                      <Paper sx={{ path: { fill: theme.colors.background } }} />
                    </div>
                  </div>
                  <div className="ml-4">
                    <h5
                      className="text-lg leading-6 font-medium"
                      sx={{ color: 'text' }}
                    >
                      Reusability
                    </h5>
                    <p
                      className="mt-2 text-base leading-6"
                      sx={{ color: 'gray' }}
                    >
                      Instead of maintaining multiple Xcode projects, describe
                      your project once, and reuse it everywhere.
                    </p>
                  </div>
                </div>
              </li>
              <li className="mt-10 md:mt-0">
                <div className="flex">
                  <div className="flex-shrink-0">
                    <div
                      className="flex items-center justify-center h-12 w-12 rounded-md text-white"
                      sx={{ bg: 'secondary' }}
                    >
                      <Eye sx={{ path: { fill: theme.colors.background } }} />
                    </div>
                  </div>
                  <div className="ml-4">
                    <h5
                      className="text-lg leading-6 font-medium"
                      sx={{ color: 'text' }}
                    >
                      Focus
                    </h5>
                    <p
                      className="mt-2 text-base leading-6"
                      sx={{ color: 'gray' }}
                    >
                      Generated projects are optimized for your focus and
                      productivity. They contain just what you need for the task
                      at hand.
                    </p>
                  </div>
                </div>
              </li>
              <li className="mt-10 md:mt-0">
                <div className="flex">
                  <div className="flex-shrink-0">
                    <div
                      className="flex items-center justify-center h-12 w-12 rounded-md text-white"
                      sx={{ bg: 'secondary' }}
                    >
                      <Warning
                        sx={{ path: { fill: theme.colors.background } }}
                      />
                    </div>
                  </div>
                  <div className="ml-4">
                    <h5
                      className="text-lg leading-6 font-medium"
                      sx={{ color: 'text' }}
                    >
                      Early errors
                    </h5>
                    <p
                      className="mt-2 text-base leading-6"
                      sx={{ color: 'gray' }}
                    >
                      If we know your project won’t compile, we fail early. We
                      don't want you *to* waste time waiting for the build
                      system to bubble up errors.
                    </p>
                  </div>
                </div>
              </li>
              <li className="mt-10 md:mt-0">
                <div className="flex">
                  <div className="flex-shrink-0">
                    <div
                      className="flex items-center justify-center h-12 w-12 rounded-md text-white"
                      sx={{ bg: 'secondary' }}
                    >
                      <Message
                        sx={{ path: { fill: theme.colors.background } }}
                      />
                    </div>
                  </div>
                  <div className="ml-4">
                    <h5
                      className="text-lg leading-6 font-medium"
                      sx={{ color: 'text' }}
                    >
                      Conventions
                    </h5>
                    <p
                      className="mt-2 text-base leading-6"
                      sx={{ color: 'gray' }}
                    >
                      Be opinionated about the structure of the projects; define
                      project factories that teams can use to create new
                      projects.
                    </p>
                  </div>
                </div>
              </li>
              <li className="mt-10 md:mt-0">
                <div className="flex">
                  <div className="flex-shrink-0">
                    <div
                      className="flex items-center justify-center h-12 w-12 rounded-md text-white"
                      sx={{ bg: 'secondary' }}
                    >
                      <Arrow sx={{ path: { fill: theme.colors.background } }} />
                    </div>
                  </div>
                  <div className="ml-4">
                    <h5
                      className="text-lg leading-6 font-medium"
                      sx={{ color: 'text' }}
                    >
                      Scale
                    </h5>
                    <p
                      className="mt-2 text-base leading-6"
                      sx={{ color: 'gray' }}
                    >
                      Tuist is optimized to support projects at scale. Whether
                      your project is 1 target, or 1000, it should make no
                      diffference.
                    </p>
                  </div>
                </div>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </Main>
  )
}

const Videos = () => {
  const { theme } = useThemeUI()
  return (
    <Main>
      <div className="py-12" sx={{ bg: 'background' }}>
        <div className="max-w-screen-xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="lg:text-center">
            <p
              className="text-base leading-6 font-semibold tracking-wide uppercase"
              sx={{ color: 'primary' }}
            >
              Videos
            </p>
            <h3
              className="mt-2 text-3xl leading-8 font-extrabold tracking-tight sm:text-4xl sm:leading-10"
              sx={{ color: 'text' }}
            >
              A video is worth a thousand words
            </h3>
            <p
              className="mt-4 max-w-2xl text-xl leading-7 lg:mx-auto"
              sx={{ color: 'gray' }}
            >
              Watch our series of videos that explain different features of
              Tuist.
            </p>
          </div>
          <div className="mt-12 grid gap-5 max-w-lg mx-auto lg:grid-cols-2 lg:max-w-none">
            <div className="flex flex-col rounded-lg shadow-lg overflow-hidden">
              <div className="flex-shrink-0">
                <img
                  className="h-48 w-full object-cover"
                  src="https://i.ytimg.com/vi/wCVPWJvJGng/maxresdefault.jpg"
                  alt=""
                />
              </div>
              <div
                className="flex-1 p-6 flex flex-col justify-between"
                sx={{ bg: 'background' }}
              >
                <div className="flex-1">
                  <p
                    className="text-sm leading-5 font-medium"
                    sx={{ color: 'primary' }}
                  >
                    Video
                  </p>
                  <a
                    href="https://www.youtube.com/watch?v=wCVPWJvJGng"
                    target="__blank"
                    className="block"
                  >
                    <h3
                      className="mt-2 text-xl leading-7 font-semibold"
                      sx={{ color: 'text' }}
                    >
                      Introduction to Tuist
                    </h3>
                    <p
                      className="mt-3 text-base leading-6"
                      sx={{ color: 'gray' }}
                    >
                      In this video, I give a quick introduction to Tuist. I
                      talk about how to install the tool and bootstrap a new
                      modular app using the init command. Moreover, I show how
                      to use the focus command to generate and open and Xcode
                      project, as well as how to use "tuist edit" to edit the
                      manifest files using Xcode.
                    </p>
                  </a>
                </div>
                <div className="mt-6 flex items-center">
                  <div className="flex-shrink-0">
                    <img
                      className="h-10 w-10 rounded-full"
                      src="https://avatars3.githubusercontent.com/u/663605?s=460&v=4"
                      alt=""
                    />
                  </div>
                  <div className="ml-3">
                    <p
                      className="text-sm leading-5 font-medium"
                      sx={{ color: 'text' }}
                    >
                      Pedro Piñera
                    </p>
                    <div
                      className="flex text-sm leading-5"
                      sx={{ color: 'gray' }}
                    >
                      <time dateTime="2020-03-16">May 7, 2020</time>
                      <span className="mx-1">·</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <div className="flex flex-col rounded-lg shadow-lg overflow-hidden">
              <div className="flex-shrink-0">
                <img
                  className="h-48 w-full object-cover"
                  src="https://i.ytimg.com/vi/KHDNKdSKnkw/maxresdefault.jpg"
                  alt=""
                />
              </div>
              <div
                className="flex-1 p-6 flex flex-col justify-between"
                sx={{ bg: 'background' }}
              >
                <div className="flex-1">
                  <p
                    className="text-sm leading-5 font-medium"
                    sx={{ color: 'primary' }}
                  >
                    Video
                  </p>
                  <a
                    href="https://www.youtube.com/watch?v=KHDNKdSKnkw"
                    target="__blank"
                    className="block"
                  >
                    <h3
                      className="mt-2 text-xl leading-7 font-semibold"
                      sx={{ color: 'text' }}
                    >
                      Defining dependencies in Tuist
                    </h3>
                    <p
                      className="mt-3 text-base leading-6"
                      sx={{ color: 'gray' }}
                    >
                      In this video I talk about the DSL that Tuist exposes to
                      define dependencies easy and consistently.
                    </p>
                  </a>
                </div>
                <div className="mt-6 flex items-center">
                  <div className="flex-shrink-0">
                    <img
                      className="h-10 w-10 rounded-full"
                      src="https://avatars3.githubusercontent.com/u/663605?s=460&v=4"
                      alt=""
                    />
                  </div>
                  <div className="ml-3">
                    <p
                      className="text-sm leading-5 font-medium"
                      sx={{ color: 'text' }}
                    >
                      Pedro Piñera
                    </p>
                    <div
                      className="flex text-sm leading-5"
                      sx={{ color: 'gray' }}
                    >
                      <time dateTime="2020-03-16">May 13, 2020</time>
                      <span className="mx-1">·</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Main>
  )
}

const Sponsor = () => {
  return (
    <div className="py-12" sx={{ bg: 'muted' }}>
      <div className="max-w-screen-xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="lg:text-center flex items-center flex-col">
          <img
            src="https://github.githubassets.com/images/modules/site/sponsors/logo-mona-2.svg"
            sx={{ width: 200, my: 3 }}
          />
          <p
            className="text-base leading-6 font-semibold tracking-wide uppercase"
            sx={{ color: 'primary' }}
          >
            Sponsors
          </p>
          <h3
            className="mt-2 text-3xl leading-8 font-extrabold tracking-tight sm:text-4xl sm:leading-10"
            sx={{ color: 'text' }}
          >
            Become a backer
          </h3>

          <p
            className="mt-4 max-w-2xl text-xl leading-7 lg:mx-auto"
            sx={{ color: 'gray' }}
          >
            If you are using Tuist or packages like{' '}
            <a href="https://github.com/tuist/xcodeproj" target="__blank">
              XcodeProj
            </a>{' '}
            upon which the community is building incredible tools, consider
            financially supporting our work. We'll use the funds for paying
            costs and supporting the community.
          </p>
          <div>
            <div className="inline-flex rounded-md shadow my-5">
              <a
                target="__blank"
                href="https://github.com/sponsors/tuist"
                sx={{
                  color: 'background',
                  bg: 'primary',
                  '&:hover': { bg: lighten('primary', 0.05) },
                }}
                className="inline-flex items-center justify-center px-5 py-3 border border-transparent text-base leading-6 font-medium rounded-md text-white focus:outline-none focus:shadow-outline transition duration-150 ease-in-out"
              >
                Sponsor
              </a>
            </div>
          </div>
          <div sx={{ my: 3 }}></div>
          <div className="flex flex-col items-center">
            <h3
              className="mt-2 text-3xl leading-8 font-bold tracking-tight sm:text-3xl sm:leading-10"
              sx={{ color: 'text' }}
            >
              Silver Sponsors
            </h3>
            <p
              className="mt-4 max-w-2xl text-xl leading-7 lg:mx-auto"
              sx={{ color: 'gray' }}
            >
              We are honored to have the following organizations supporting the long-term financial sustainability of the project.
            </p>
            <div className="mt-8">
              <a target="_blank" href="https://getstream.io/chat/sdk/ios/?utm_source=Github&utm_medium=Github_Repo_Content_Ad&utm_content=Developer&utm_campaign=Github_Jan2022_SwiftSDK&utm_term=tuist">
                <img className="w-28" src={stream}/>
              </a>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

const IndexPage = () => {
  return (
    <Layout>
      <SEO title="Xcode on steroids" />
      <Steroids />
      <Workspaces />
      <Principles />
      <Videos />
      <Sponsor />
      <Testimonies />
      <Contribute />
    </Layout>
  )
}

export default IndexPage
