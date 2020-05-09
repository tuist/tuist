/** @jsx jsx */
import { jsx, Styled, useThemeUI } from 'theme-ui'
import { useState } from 'react'
import Layout from '../components/layout'
import Main from '../components/main'
import { Link } from 'gatsby'
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
import Quote from '../../assets/quote.svg'
import SEO from '../components/SEO'
import Soundcloud from '../../assets/soundcloud.svg'
import Devengo from '../../assets/devengo.svg'
import Ackee from '../../assets/ackee.svg'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { darken, lighten } from '@theme-ui/color'
import {
  faChevronRight,
  faChevronLeft,
} from '@fortawesome/free-solid-svg-icons'

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
            <div
              sx={{
                textAlign: 'center',
                color: 'primary',
                fontSize: [5, 6],
                mb: 0,
                fontWeight: '500',
                lineHeight: 1.3,
              }}
            >
              Xcode on steroids
            </div>
            <div
              sx={{
                textAlign: 'center',
                color: 'primary',
                fontSize: [5, 6],
                mt: 0,
                fontWeight: 'heading',
                lineHeight: 1.3,
              }}
            >
              <span>Easy</span> and <span>fast</span>
            </div>
            <div
              sx={{
                color: 'primary',
                fontSize: [2, 3],
                fontWeight: 'body',
                mt: [4, 5],
                textAlign: 'center',
              }}
            >
              Bootstrap, maintain, and interact with
              <br /> Xcode projects at any scale
            </div>
            <GradientButton
              title="GET STARTED"
              link="/docs/usage/getting-started/"
            />

            <div sx={{ color: 'secondary', mt: 4, textAlign: 'center' }}>
              Trusted by the following companies and projects:
            </div>
            <div
              sx={{
                mt: 3,
                display: 'flex',
                flexDirection: 'row',
                justifyContent: 'center',
              }}
            >
              <a href="https://soundcloud.com" target="__blank">
                <Soundcloud
                  sx={{ height: 30, path: { fill: theme.colors.secondary } }}
                />
              </a>
              <Devengo
                sx={{
                  ml: 3,
                  height: 30,
                  width: 150,
                  path: { fill: theme.colors.secondary },
                }}
              />
              <a href="https://www.ackee.cz/en" target="__blank" sx={{ ml: 3 }}>
                <Ackee
                  sx={{
                    height: 20,
                    width: 80,
                    path: { fill: theme.colors.secondary },
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
  const buttonStyle = { width: 12, height: 12, borderRadius: 6 }
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
    <div sx={{ position: 'relative', overflow: 'hidden' }}>
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
              Describe your apps and the frameworks they depend on. If they have
              unit or ui test targets you can define them too; even Swift
              package dependencies.
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

const Reflection = ({ name, avatarUrl, testimony, role, company }) => {
  return (
    <div
      sx={{
        bg: 'muted',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        ml: 3,
        mb: [4, 0],
        flex: '0 0 29%',
      }}
    >
      <div sx={{ mt: 4, mb: 3, display: 'inherit' }}>
        <img
          src={avatarUrl}
          alt={`${name} avatar`}
          sx={{ bg: 'muted', width: 60, height: 60, borderRadius: 30, ml: 3 }}
        />
        <div
          sx={{
            position: 'relative',
            top: 40,
            right: 15,
            bg: 'primary',
            width: 20,
            height: 20,
            borderRadius: 20,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <Quote />
        </div>
      </div>
      <div sx={{ fontSize: 0, color: 'primary', textTransform: 'uppercase' }}>
        {name}
      </div>
      <div
        sx={{
          fontSize: 1,
          textAlign: 'center',
          color: 'text',
          p: 3,
        }}
      >
        {testimony}
      </div>
      <div sx={{ flex: 1 }} />
      <div
        sx={{
          height: 50,
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'flex-start',
          alignItems: 'stretch',
          alignSelf: 'stretch',
          mt: 2,
        }}
      >
        <div
          sx={{
            height: 2,
            bg: 'primary',
            flex: '0 0 3px',
            width: '30%',
            alignSelf: 'center',
          }}
        />
        <div sx={{ height: 1, bg: 'muted', flex: '0 0 1px' }} />
        <div
          sx={{
            fontSize: 0,
            color: 'primary',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            textAlign: 'center',
            textTransform: 'uppercase',
            py: 3,
          }}
        >{`${role} at ${company}`}</div>
      </div>
    </div>
  )
}

const Reflections = () => {
  const { theme } = useThemeUI()
  const reflections = [
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
      name: 'Tyler Neveldine',
      testimony:
        'Tuist centralizes our entire workspace’s configuration and describes it in a language that we all understand. This increases the readability and approachability of our project tenfold.',
      role: 'iOS lead',
      company: 'Dynamic Signal',
      avatarUrl:
        'https://pbs.twimg.com/profile_images/999765687777148928/wSJxk3Ni_400x400.jpg',
    },
  ]
  const [offset, setOffset] = useState(0)
  const next = () => {
    if (offset + 1 + 3 <= reflections.length) {
      setOffset(offset + 1)
    }
  }
  const previous = () => {
    if (offset > 0) {
      setOffset(offset - 1)
    }
  }
  const selectedTestimonies = reflections.slice(offset, offset + 3)

  return (
    <div
      sx={{
        position: 'relative',
        flexDirection: 'column',
        alignItems: 'stretch',
      }}
    >
      <div sx={{ mb: [0, 0, 50], pb: [5, 5, 0] }}>
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
                What users say
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
                heavy-lifting and complext work
              </p>
            </div>
            <div
              sx={{
                mt: 5,
                display: 'flex',
                flexDirection: ['column', 'row'],
                alignItems: ['stretch', 'stretch'],
                justifyContent: 'space-between',
              }}
            >
              <div
                sx={{
                  alignSelf: 'center',
                  px: 2,
                  cursor: 'pointer',
                  display: ['none', 'inherit'],
                }}
                onClick={previous}
              >
                <FontAwesomeIcon
                  sx={{
                    mt: -1,
                    path: { fill: theme.colors.text },
                    '&:hover': { path: { fill: theme.colors.primary } },
                  }}
                  icon={faChevronLeft}
                  size="lg"
                />
              </div>
              {selectedTestimonies.map((reflection, index) => {
                return (
                  <Reflection
                    key={index}
                    name={reflection.name}
                    testimony={reflection.testimony}
                    role={reflection.role}
                    company={reflection.company}
                    avatarUrl={reflection.avatarUrl}
                  />
                )
              })}
              <div
                sx={{
                  alignSelf: 'center',
                  ml: 2,
                  px: 2,
                  cursor: 'pointer',
                  display: ['none', 'inherit'],
                }}
                onClick={next}
              >
                <FontAwesomeIcon
                  sx={{
                    mt: -1,
                    path: { fill: theme.colors.text },
                    '&:hover': { path: { fill: theme.colors.primary } },
                  }}
                  icon={faChevronRight}
                  size="lg"
                />
              </div>
            </div>
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
        <div className="max-w-screen-xl mx-auto text-center py-12 px-4 sm:px-6 lg:py-16 lg:px-8">
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
                to="/docs/usage/getting-started/"
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
                to="/docs/contribution/getting-started/"
                sx={{
                  color: 'secondary',
                  bg: lighten('secondary', 0.32),
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
            <ul className="md:grid md:grid-cols-2 md:col-gap-8 md:row-gap-10">
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

const IndexPage = () => {
  return (
    <Layout>
      <SEO title="Xcode on steroids" />
      <Steroids />
      <Workspaces />
      <Principles />
      <Reflections />
      <Contribute />
    </Layout>
  )
}

export default IndexPage
