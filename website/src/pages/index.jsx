/** @jsx jsx */
import { jsx, Styled, useThemeUI } from 'theme-ui'
import { useState } from "react";
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
import { faChevronRight, faChevronLeft } from '@fortawesome/free-solid-svg-icons'

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
          background: theme =>
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
  const { theme } = useThemeUI();
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
              <span >Easy</span> and{' '}
              <span >fast</span>
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
            <div sx={{ mt: 3, display: 'flex', flexDirection: 'row', justifyContent: 'center' }}>
              <a href="https://soundcloud.com" target="__blank">
                <Soundcloud sx={{ height: 30, path: { fill: theme.colors.secondary } }} />
              </a>
              <Devengo sx={{ ml: 3, height: 30, width: 150, path: { fill: theme.colors.secondary } }} />
              <a href="https://www.ackee.cz/en" target="__blank" sx={{ ml: 3 }}>
                <Ackee sx={{ height: 20, width: 80, path: { fill: theme.colors.secondary } }} />
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
      <div sx={{ color: 'text', mt: 2, textAlign: 'center', textAlign: 'center' }}>
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
          <SectionTitle
            title="Describe & generate"
            subtitle="WORKSPACES"
            description="Describe your apps and the frameworks they depend on. If they have unit or ui test targets you can define them too; even Swift package dependencies."
          />
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

const Principles = () => {
  const { theme } = useThemeUI()
  return (
    <Main>
      <div
        sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}
      >
        <SectionTitle
          title="Principles"
          subtitle="DESIGN"
          description="Tuist is not a project generator, it’s a tool to empower you to build apps
        of any scale."
        />
        <div
          sx={{
            flex: 1,
            mt: 4,
            display: 'flex',
            justifyContent: 'space-between',
            flexDirection: ['column', 'row'],
            flexWrap: 'wrap',
          }}
        >
          <Feature
            color="secondary"
            name="Plain and easy language"
            description="Describe your projects as you think about them.  Build settings, phases and other intricacies become implementation details."
          >
            <Heart sx={{ path: { fill: theme.colors.background } }} />
          </Feature>
          <Feature
            color="secondary"
            name="Reusability"
            description="Instead of maintaining multiple Xcode projects, describe your project once, and reuse it everywhere."
          >
            <Paper sx={{ path: { fill: theme.colors.background } }} />
          </Feature>
          <Feature
            color="secondary"
            name="Focus"
            description="Generated projects are optimized for your focus and productivity. They contain just what you need for the task at hand."
          >
            <Eye sx={{ path: { fill: theme.colors.background } }} />
          </Feature>
          <Feature
            color="secondary"
            name="Early errors"
            description="If we know your project won’t compile, we fail early. We don't want you *to* waste time waiting for the build system to bubble up errors."
          >
            <Warning sx={{ path: { fill: theme.colors.background } }} />
          </Feature>
          <Feature
            color="secondary"
            name="Conventions"
            description="Be opinionated about the structure of the projects; define project factories that teams can use to create new projects."
          >
            <Message sx={{ path: { fill: theme.colors.background } }} />
          </Feature>
          <Feature
            color="secondary"
            name="Scale"
            description="Tuist is optimized to support projects at scale. Whether your project is 1 target, or 1000, it should make no diffference."
          >
            <Arrow sx={{ path: { fill: theme.colors.background } }} />
          </Feature>
        </div>
      </div>
    </Main>
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
        flex: "0 0 29%"
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
      <div sx={{ fontSize: 0, color: 'primary', textTransform: 'uppercase' }}>{name}</div>
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
  const { theme } = useThemeUI();
  const reflections = [
    {
      name: "Kassem Wridan",
      testimony: "By leveraging Tuist libraries, we’ve built tooling to help us manage and scale our Xcode projects in a safe and consistent manner. Our team has also contributed back to the community to help other developers tame their large projects.",
      role: "iOS developer",
      company: "Bloomberg",
      avatarUrl: "https://avatars1.githubusercontent.com/u/11914919?s=460"
    },
    {
      name: "Romain Boulay",
      testimony: "Tuist has delivered more than the SoundCloud iOS Collective expected! We aimed to make modularization more accessible and maintainable. We got this... and better build times!.",
      role: "iOS lead",
      company: "SoundCloud",
      avatarUrl: "https://avatars2.githubusercontent.com/u/169323?s=460"
    },
    {
      name: "Oliver Atkinson",
      testimony: "It has really helped out the team and project by creating an environment where defining new modules is easy, modularity allows us to focus and become experts in our individual domains.",
      role: "Senior iOS developer",
      company: "Sky",
      avatarUrl: "https://en.gravatar.com/userimage/41347978/456ffd8f0ef3f52c6e38f9003f4c51fa.jpg?size=460"
    },
    {
      name: "Tyler Neveldine",
      testimony: "Tuist centralizes our entire workspace’s configuration and describes it in a language that we all understand. This increases the readability and approachability of our project tenfold.",
      role: "iOS lead",
      company: "Dynamic Signal",
      avatarUrl: 'https://pbs.twimg.com/profile_images/999765687777148928/wSJxk3Ni_400x400.jpg'
    }
  ]
  const [offset, setOffset] = useState(0);
  const next = () => {
    if ((offset + 1 + 3) <= reflections.length) {
      setOffset(offset + 1);
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
            <SectionTitle
              title="Reflections"
              subtitle="USERS"
              description="Tuist is a project trusted and supported by developers that are already having fun working with Xcode"
            />
            <div
              sx={{
                mt: 5,
                display: 'flex',
                flexDirection: ['column', 'row'],
                alignItems: ['stretch', 'stretch'],
                justifyContent: 'space-between'
              }}
            >
              <div sx={{ alignSelf: 'center', px: 2, cursor: 'pointer', display: ['none', 'inherit'] }} onClick={previous}>
                <FontAwesomeIcon
                  sx={{ mt: -1, path: { fill: theme.colors.text }, "&:hover": { path: { fill: theme.colors.primary } } }}
                  icon={faChevronLeft}
                  size="lg"
                />
              </div>
              {selectedTestimonies.map((reflection, index) => {
                return <Reflection
                  key={index}
                  name={reflection.name}
                  testimony={reflection.testimony}
                  role={reflection.role}
                  company={reflection.company}
                  avatarUrl={reflection.avatarUrl}
                />
              })}
              <div sx={{ alignSelf: 'center', ml: 2, px: 2, cursor: 'pointer', display: ['none', 'inherit'] }} onClick={next}>
                <FontAwesomeIcon
                  sx={{ mt: -1, path: { fill: theme.colors.text }, "&:hover": { path: { fill: theme.colors.primary } } }}
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
      <div
        sx={{
          display: 'flex',
          flexDirection: ['column', 'row'],
          alignItems: 'center',
          justifyContent: 'center',
          py: [0, 5],
          px: [0, 1],
        }}
      >
        <div
          sx={{
            alignSelf: 'stretch',
            flex: 0.5,
            display: 'flex',
            flexDirection: ['row', 'column'],
            alignItems: 'center',
            justifyContent: 'space-between',
          }}
        >
          <a
            href="https://github.com/ollieatkinson"
            target="__blank"
            alt="Open Ollie's profile on GitHub"
            sx={{ alignSelf: 'flex-start', mt: [100, 0] }}
          >
            <img
              sx={{
                width: 50,
                height: 50,
                borderRadius: 25,
              }}
              alt="Ollie's avatar"
              src="https://avatars2.githubusercontent.com/u/1382565?s=460&v=4"
            />
          </a>
          <a
            href="https://github.com/kwridan"
            target="__blank"
            alt="Open Kas' profile on GitHub"
          >
            <img
              sx={{ width: 50, height: 50, borderRadius: 25 }}
              alt="Kas' avatar"
              src="https://avatars2.githubusercontent.com/u/11914919?s=460&v=4"
            />
          </a>

          <a
            href="https://github.com/fortmarek"
            target="__blank"
            alt="Open Marek's profile on GitHub"
            sx={{ alignSelf: 'flex-start', mt: [100, 0] }}
          >
            <img
              sx={{
                width: 50,
                height: 50,
                borderRadius: 25,
              }}
              alt="Marek's profile"
              src="https://avatars1.githubusercontent.com/u/9371695?s=460&v=4"
            />
          </a>
        </div>
        <div
          sx={{
            px: 3,
            flex: [1, 1.6],
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
          }}
        >
          <SectionTitle
            title="You can bring more fun to Xcode projects too"
            subtitle="CONTRIBUTE"
            description="Tuist is a welcoming and open source project that is writen in Swift  by and for the community"
          />

          <GradientButton
            title="START CONTRIBUTING"
            link="/docs/contribution/getting-started/"
          />
        </div>
        <div
          sx={{
            alignSelf: 'stretch',
            flex: 0.5,
            display: 'flex',
            flexDirection: ['row', 'column'],
            alignItems: 'center',
            justifyContent: 'space-between',
          }}
        >
          <a
            href="https://github.com/lakpa"
            target="__blank"
            alt="Open Lakpa profile on GitHub"
            sx={{ alignSelf: 'flex-end', mb: [100, 0] }}
          >
            <img
              sx={{
                width: 50,
                height: 50,
                borderRadius: 25,
              }}
              alt="Lakpa's avatar"
              src="https://avatars1.githubusercontent.com/u/389328?s=400&v=4"
            />
          </a>

          <a
            href="https://github.com/pepibumur"
            target="__blank"
            alt="Open Pedro's profile on GitHub"
          >
            <img
              sx={{ width: 50, height: 50, borderRadius: 25 }}
              src="https://avatars3.githubusercontent.com/u/663605?s=460&v=4"
            />
          </a>
          <a
            href="https://github.com/marciniwanicki"
            target="__blank"
            alt="Open Marcin's profile on GitHub"
            sx={{ mb: [100, 0], alignSelf: 'flex-end' }}
          >
            <img
              sx={{
                width: 50,
                height: 50,
                borderRadius: 25,
              }}
              alt="Marcin's avatar"
              src="https://avatars1.githubusercontent.com/u/946649?s=460&v=4"
            />
          </a>
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
