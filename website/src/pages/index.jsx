/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'

import Layout from '../components/layout'
import Footer from '../components/footer'
import Main from '../components/main'
import { graphql, Link } from 'gatsby'
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

const PressableButton = posed.div({
  hoverable: true,
  pressable: true,
  init: { scale: 1 },
  hover: { scale: 1.1 },
  press: { scale: 1.05 },
})

const GradientButton = ({ title, link }) => {
  return (
    <Link to={link}>
      <PressableButton
        sx={{
          fontSize: 1,
          mt: 4,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: theme =>
            `linear-gradient(90deg, ${theme.colors.purple} 0%, ${theme.colors.primary} 100%)`,
          color: 'white',
          p: 2,
          px: 3,
          height: '40px',
          borderRadius: '40px',
          '&:focus': {
            textDecoration: 'underline',
            textDecorationColor: 'white',
          },
          '&:hover': {
            cursor: 'pointer',
          },
        }}
      >
        {title}
      </PressableButton>
    </Link>
  )
}

const Steroids = () => {
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
              <span sx={{ borderBottom: '5px solid' }}>Easy</span> and{' '}
              <span sx={{ borderBottom: '5px solid' }}>fast</span>
            </div>
            <div
              sx={{
                color: 'gray2',
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
            {/* <div sx={{ color: 'gray4', mt: 4 }}>
              Trusted by the following companies and projects:
            </div>
            <div sx={{ mt: 3 }}>
              <Soundcloud sx={{ height: 30 }} />
              <Mytaxi sx={{ ml: 3, height: 30 }} />
            </div> */}
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
      <div sx={{ color: 'gray3', mt: 2, textAlign: 'center' }}>
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
          bg: 'gray5',
          height: 20,
          borderTopLeftRadius: radius,
          borderTopRightRadius: radius,
          display: 'flex',
          flexDirection: 'row',
          alignItems: 'center',
          flex: 1,
          py: 1,
          px: 2,
        }}
      >
        <div sx={{ ...buttonStyle, bg: 'red' }} />
        <div sx={{ ...buttonStyle, ml: 1, bg: 'yellow' }} />
        <div sx={{ ...buttonStyle, ml: 1, bg: 'green' }} />
        <div sx={{ fontSize: 1, color: 'gray3', ml: 3 }}>Project.swift</div>
      </div>
      <div
        sx={{
          bg: 'black',
          borderBottomLeftRadius: radius,
          borderBottomRightRadius: radius,
        }}
      >
        <Code className="language-swift" my="0" showCopy={false} bg="black">
          {exampleCode}
        </Code>
      </div>
    </div>
  )
}

const PBXProj = () => {
  const part1 = `PBXBuildFile section */ B90F3BFE238DB50A00102CB7 /* Manifest.swift in Sources */ = {isa = PBXBuildFile; fileRef = B90F3BFD238DB50A00102CB7 /* Manifest.swift */; }; OBJ_1007 /* Signals.swift in Sources */ = {isa = PBXBuildFile; fileRef = OBJ_544 /* Signals.swift */; }; OBJ_1014 /* Package.swift in Sources */ = {isa = PBXBuildFile; fileRef = OBJ_545 /* Package.swift */; }; OBJ_1020 /* Package.swift in Sources */ = {isa = PBXBuildFile; fileRef = OBJ_636 /* Package.swift */; }; OBJ_1026 /* CocoaPodsNode.swift in Sources */ = {isa = PBXBuildFile; fileRef = OBJ_43 /* CocoaPodsNode.swift */; }; OBJ_1027 /* FrameworkNode.swift in Sources */ OBJ_16 /* Headers.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Headers.swift; sourceTree = "<group>"; }; OBJ_1631 /* Frameworks */ = { isa = PBXFrameworksBuildPhase; buildActionMask = 0; files = ( OBJ_1632 /* TuistSupportTesting.framework in Frameworks */, OBJ_1633 /* TuistKit.framework in Frameworks */, OBJ_1634 /* Signals.framework in Frameworks */, OBJ_1635 /* ProjectDescription.framework in Frameworks */, OBJ_1636 /* TuistGenerator.framework in Frameworks */, OBJ_1637 /* TuistCore.framework in Frameworks */, OBJ_1638 /* XcodeProj.framework in Frameworks */`
  const part2 = ` = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FileElement.swift; sourceTree = "<group>"; }; OBJ_140 /* GraphToDotGraphMapper.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GraphToDotGraphMapper.swift; sourceTree = "<group>"; }; OBJ_142 /* AbsolutePath+Extras.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "AbsolutePath+Extras.swift"; sourceTree = "<group>"; }; OBJ_143 /* Array+Extras.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "Array+Extras.swift"; sourceTree = "<group>"; }; OBJ_144 /* Xcodeproj+Extras.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "Xcodeproj+Extras.swift"; sourceTree = "<group>"; }; OBJ_146 /* BuildPhaseGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BuildPhaseGenerator.swift; sourceTree = "<group>"; } ; OBJ_147 /* ConfigGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ConfigGenerator.swift; sourceTree = "<group>"; }; OBJ_148 /* DerivedFileGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DerivedFileGenerator.swift; sourceTree = "<group>"; }; OBJ_149 /* FileGenerator.swift *`
  const part3 = ` {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FileGenerator.swift; sourceTree = "<group>"; }; OBJ_15 /* FileList.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FileList.swift; sourceTree = "<group>"; }; OBJ_150 /* GeneratedProject.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift;`
  const part4 = `path = InfoPlistContentProvider.swift; sourceTree = "<group>"; }; OBJ_153 /* LinkGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LinkGenerator.swift; sourceTree = "<group>"; }; OBJ_154 /* ProjectFileElements.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ProjectFileElements.swift; sourceTree = "<group>"; }; OBJ_155 /* ProjectGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ProjectGenerator.swift; sourceTree = "<group>"; }; OBJ_156 /* ProjectGroups.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ProjectGroups.swift; sourceTree = "<group>"; }; OBJ_157 /* SchemesGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SchemesGenerator.swift; sourceTree = "<group>"; }; OBJ_158 /* TargetGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TargetGenerator.swift; sourceTree = "<group>"; }; OBJ_159 /* WorkspaceGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WorkspaceGenerator.swift; sourceTree = "<group>"; }; , OBJ_1639 /* AEXML.framework in Frameworks */, OBJ_1640 /* PathKit.framework in Frameworks */, OBJ_1641 /* TuistSupport.framework in Frameworks */, OBJ_1642 /* SPMUtility.framework in Frameworks */, OBJ_1643 /* Basic.framework in Frameworks */, OBJ_1644 /* SPMLibc.framework in Frameworks */, OBJ_1645 /* clibc.framework in Frameworks */, ); runOnlyForDeploymentPostprocessing = 0; };/* Begin PBXBuildFile section */ B90F3BFE238DB50A00102CB7 /* Manifest.swift in Sources */ = {isa = PBXBuildFile; fileRef = B90F3BFD238DB50A00102CB7 /* Manifest.swift */; }; OBJ_1007 /* Signals.swift in Sources */ = {isa = PBXBuildFile; fileRef = OBJ_544 /* Signals.swift */; }; OBJ_1014 /* Package.swift in Sources */ = {isa = PBXBuildFile; fileRef = OBJ_545 /* Package.swift */; }; OBJ_1020 /* Package.swift in Sources */ = {isa = PBXBuildFile; fileRef = OBJ_636 /* Package.swift */; }; OBJ_1026 /* CocoaPodsNode.swift in Sources */ = {isa = PBXBuildFile; fileRef = OBJ_43 /* CocoaPodsNode.swift */; }; OBJ_1027 /* FrameworkNode.swift in Sources */ = {isa = PBXBuildFile; fileRef = OBJ_44 /* FrameworkNode.swift */; }; B90F3B5C238DB48E00102CB7 /* PBXContainerItemProxy */ = { isa = PBXContainerItemProxy; containerPortal = OBJ_1 /* Project object */; proxyType = 1; remoteGlobalIDString = "SwiftPM::Basic"; remoteInfo = Basic; }; B90F3B5D238DB48E00102CB7 /* PBXContainerItemProxy */ = { isa = PBXContainerItemProxy; containerPortal = OBJ_1 /* Project object */; proxyType = 1; remoteGlobalIDString = "SwiftPM::SPMLibc"; remoteInfo = SPMLibc; }; B90F3B5E238DB48E00102CB7 /* PBXContainerItemProxy */ = { isa = PBXContainerItemProxy; containerPortal = OBJ_1 /* Project object */; proxyType = 1; remoteGlobalIDString = "SwiftPM::clibc"; remoteInfo = clibc; }; OBJ_138 /* DotGraphNodeAttribute.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DotGraphNodeAttribute.swift; sourceTree = "<group>"; }; OBJ_139 /* DotGraphType.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DotGraphType.swift; sourceTree = "<group>"; }; OBJ_14 /* FileElement.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FileElement.swift; sourceTree = "<group>"; }; OBJ_140 /* GraphToDotGraphMapper.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GraphToDotGraphMapper.swift; sourceTree = "<group>"; }; OBJ_142 /* AbsolutePath+Extras.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "AbsolutePath+Extras.swift"; sourceTree = "<group>"; }; OBJ_143 /* Array+Extras.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "Array+Extras.swift"; sourceTree = "<group>"; }; OBJ_144 /* Xcodeproj+Extras.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "Xcodeproj+Extras.swift"; sourceTree = "<group>"; }; OBJ_146 /* BuildPhaseGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BuildPhaseGenerator.swift; sourceTree = "<group>"; }; OBJ_147 /* ConfigGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ConfigGenerator.swift; sourceTree = "<group>"; }; OBJ_148 /* DerivedFileGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DerivedFileGenerator.swift; sourceTree = "<group>"; }; OBJ_149 /* FileGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FileGenerator.swift; sourceTree = "<group>"; }; OBJ_15 /* FileList.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path =`
  return (
    <div sx={{ opacity: '0.5', fontSize: 0, color: 'gray5' }}>
      <span>{part4}</span>
      <span sx={{ fontWeight: '500' }}>{`<<<<<<< HEAD:project.pbxproj`}</span>
      <span sx={{ fontWeight: '500' }}>{part2}</span>
      <span sx={{ fontWeight: '500' }}>{`===========`}</span>
      <span sx={{ fontWeight: '500' }}>{part3}</span>
      <span
        sx={{ fontWeight: '500' }}
      >{`>>>>>>> 77976da35a11db4580b80ae27e8d65caf5208086:project.pbxproj`}</span>
      <span>{part1}</span>
      <span>{part4}</span>
    </div>
  )
}

const Workspaces = () => {
  return (
    <div sx={{ position: 'relative', overflow: 'hidden' }}>
      <div sx={{ color: 'gray6', position: 'absolute', zIndex: '-1' }}>
        <PBXProj />
      </div>
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

const Feature = ({ color, icon, name, description, children }) => {
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
      <div sx={{ textAlign: 'center', color: 'gray3' }}>{description}</div>
    </PosedFeature>
  )
}

const Principles = () => {
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
            color="purple"
            name="Plain and easy language"
            description="Describe your projects as you think about them.  Build settings, phases and other intricacies become implementation details."
          >
            <Heart />
          </Feature>
          <Feature
            color="green"
            name="Reusability"
            description="Instead of maintaining multiple Xcode projects, describe your project once, and reuse it everywhere."
          >
            <Paper />
          </Feature>
          <Feature
            color="blue"
            name="Focus"
            description="Generated projects are optimized for your focus and productivity. They contain just what you need for the task at hand."
          >
            <Eye />
          </Feature>
          <Feature
            color="blue"
            name="Early errors"
            description="If we know your project won’t compile, we fail early. We don't want you *to* waste time waiting for the build system to bubble up errors."
          >
            <Warning />
          </Feature>
          <Feature
            color="green"
            name="Conventions"
            description="Be opinionated about the structure of the projects; define project factories that teams can use to create new projects."
          >
            <Message />
          </Feature>
          <Feature
            color="purple"
            name="Scale"
            description="Tuist is optimized to support projects at scale. Whether your project is 1 target, or 1000, it should make no diffference."
          >
            <Arrow />
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
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        mb: [4, 0],
        bg: 'white',
        width: ['95%', '30%'],
        boxShadow: theme => `-1px -1px 12px -4px ${theme.colors.gray5}`,
      }}
    >
      <div sx={{ mt: 4, mb: 3, display: 'inherit' }}>
        <img
          src={avatarUrl}
          alt={`${name} avatar`}
          sx={{ bg: 'gray6', width: 60, height: 60, borderRadius: 30, ml: 3 }}
        />
        <div
          sx={{
            position: 'relative',
            top: 40,
            right: 15,
            bg: 'green',
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
      <div sx={{ fontSize: 0, color: 'green' }}>{name}</div>
      <div
        sx={{
          fontSize: 1,
          textAlign: 'center',
          color: 'gray3',
          p: 3,
        }}
      >
        <Quote>"{testimony}"</Quote>
      </div>
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
            bg: 'green',
            flex: '0 0 3px',
            width: '30%',
            alignSelf: 'center',
          }}
        />
        <div sx={{ height: 1, bg: 'gray6', flex: '0 0 1px' }} />
        <div
          sx={{
            fontSize: 0,
            color: 'gray3',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            textAlign: 'center',
            py: 3,
          }}
        >{`${role} AT ${company}`}</div>
      </div>
    </div>
  )
}

const Ball = ({ size, color, top, left }) => {
  return (
    <div
      sx={{
        position: 'absolute',
        width: size,
        height: size,
        borderRadius: size / 2,
        bg: color,
        top: top,
        left: left,
      }}
    />
  )
}

const FloatingBalls = ({ bg }) => {
  const colors = ['red', 'green', 'purple', 'yellow', 'blue']
  return (
    <div
      sx={{
        display: 'block',
        zIndex: 0,
        position: 'absolute',
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        bg: bg,
      }}
    >
      {[...Array(5).keys()].map(index => {
        const color = colors[Math.round(Math.random() * 5)]
        const top = `${20 + Math.round(Math.random() * 60)}%`
        const left = `${20 + Math.round(Math.random() * 60)}%`
        return (
          <Ball
            size={Math.random() * 50}
            color={color}
            key="index"
            top={top}
            left={left}
          />
        )
      })}
    </div>
  )
}

const Reflections = () => {
  return (
    <div
      sx={{
        position: 'relative',
        flexDirection: 'column',
        alignItems: 'stretch',
        bg: 'white',
      }}
    >
      <div sx={{ mb: [0, 0, 50], pb: [5, 5, 0] }}>
        <div sx={{ bg: 'gray5', alignSelf: 'stretch', height: '1px' }} />
        <Main py="0">
          <div
            sx={{
              display: 'flex',
              flexDirection: 'column',
              pt: 4,
            }}
          >
            <FloatingBalls bg="gray6" />

            <SectionTitle
              title="Reflections"
              subtitle="USERS"
              description="Tuist is a project trusted and supported by developers that are already having fun working with Xcode"
            />
            <div
              sx={{
                position: 'relative',
                mt: 5,
                display: 'flex',
                flexDirection: ['column', 'row'],
                mb: [0, 0, -48],
                alignItems: ['stretch', 'center'],
                justifyContent: ['flex-start', 'space-between'],
              }}
            >
              <Reflection
                name="OLIVER ATKINSON"
                testimony="It has really helped out the team and project by creating an environment where defining new modules is easy, modularity allows us to focus and become experts in our individual domains."
                role="SENIOR IOS ENGINEER"
                company="SKY"
                avatarUrl="https://en.gravatar.com/userimage/41347978/456ffd8f0ef3f52c6e38f9003f4c51fa.jpg?size=460"
              />
              <Reflection
                name="TYLER NEVELDINE"
                testimony="Tuist centralizes our entire workspace’s configuration and describes it in a language that we all understand. This increases the readability and approachability of our project tenfold."
                role="IOS LEAD"
                company="DYNAMIC SIGNAL"
                avatarUrl="https://pbs.twimg.com/profile_images/999765687777148928/wSJxk3Ni_400x400.jpg"
              />
              <Reflection
                name="ROMAIN BOULAY"
                testimony="Tuist has delivered more than the SoundCloud iOS Collective expected! We aimed to make modularization more accessible and maintainable. We got this... and better build times!."
                role="IOS LEAD"
                company="SOUNDCLOUD"
                avatarUrl="https://avatars2.githubusercontent.com/u/169323?s=460&v=4"
              />
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
          px: [0, 6],
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
      <SEO />
      <Steroids />
      <Workspaces />
      <Principles />
      <Reflections />
      <Contribute />
      <Footer />
    </Layout>
  )
}

export default IndexPage
