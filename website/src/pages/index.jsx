/** @jsx jsx */
import { jsx } from "theme-ui";

import Layout from "../components/layout";
import Meta from "../components/meta";
import HomeHeader from "../components/home-header";
import Footer from "../components/footer";
import { graphql } from "gatsby";

import BoxIcon from "../../assets/box.svg";
import Check from "../../assets/check.svg";
import Truck from "../../assets/truck.svg";
import Report from "../../assets/report.svg";
import Developer from "../../assets/developer.svg";
import Desk from "../../assets/desk.svg";
import Asteroid from "../../assets/asteroid.svg";
import Astrology from "../../assets/astrology.svg";
import Rocket from "../../assets/rocket.svg";
import Astronaut from "../../assets/astronaut.svg";
import GitHub from "../../assets/github.svg";
import Slack from "../../assets/slack.svg";
import Terminal from "react-animated-term";
import "react-animated-term/dist/react-animated-term.css";
import { Styled } from "theme-ui";

const WithMargin = ({ children, ...props }) => {
  return (
    <div
      sx={{
        flexDirection: "column",
        display: "flex",
        alignItems: "center",
        flex: 1,
        mx: [20, 60]
      }}
      {...props}
    >
      <div
        sx={{
          width: theme => ["90%", "90%", "80%", "80%", theme.breakpoints.md]
        }}
      >
        {children}
      </div>
    </div>
  );
};

const Feature = ({ children, title, description }) => {
  return (
    <div
      sx={{
        display: "flex",
        flexDirection: "column",
        width: 170,
        alignItems: "center",
        mx: [2, 3, 4]
      }}
    >
      <div sx={{ mb: 2 }}>{children}</div>
      <div
        sx={{
          fontWeight: "bold",
          color: "secondary",
          textAlign: "center",
          mb: 3
        }}
      >
        {title}
      </div>
      <p sx={{ textAlign: "center" }}>{description}</p>
    </div>
  );
};

const Why = () => {
  const featureSx = { width: 80, height: 80 };
  return (
    <div
      sx={{
        flexDirection: "column",
        alignItems: "center",
        mb: 2,
        mt: 5,
        textAlign: "center"
      }}
    >
      <div
        sx={{
          display: "flex",
          flexDirection: [
            "column-reverse",
            "column-reverse",
            "column-reverse",
            "row"
          ],
          alignItems: "center"
        }}
      >
        <div sx={{ flex: 1 }}>
          <Styled.h2>Why</Styled.h2>
          <p>
            With the unceasing growth of apps to support new platforms and
            products, <b>Xcode projects are growing in complexity</b>. Such
            complexity, although necessary at scale, makes the projects hard to
            maintain. Moreover, it’s often a source of issues and frustration
            for developers.
          </p>
          <p>
            We believe developers should be abstracted from complexities to let
            them focus on building apps. That’s the role Tuist takes. It
            provides a <b>simple and convenient abstraction</b>, and takes the
            opportunity to encourage what we believe are good practices and
            conventions.
          </p>
          <p>
            Tuist is a command line tool written in Swift, designed and
            developed in the open.
          </p>
        </div>
        <div sx={{ flex: 1 }}>
          <Desk
            sx={{ height: [200, 200, 300, 400], width: [200, 200, 300, 400] }}
          />
        </div>
      </div>
      <Styled.h2>Features</Styled.h2>
      <div
        sx={{
          display: "flex",
          my: [3, 3],
          flexDirection: ["column", "row"],
          flexWrap: "wrap",
          alignItems: [
            "center",
            "center",
            "center",
            "center",
            "center",
            "flex-start"
          ],
          justifyContent: [
            "center",
            "center",
            "center",
            "center",
            "space-between"
          ]
        }}
      >
        <Feature
          title="Xcode projects generation"
          description="You describe the projects in Swift, we configure them for you"
        >
          <Asteroid sx={featureSx} />
        </Feature>
        <Feature
          title="Easy static & dynamic linking"
          description="We translate dependencies into build settings and phases"
        >
          <Astrology sx={featureSx} />
        </Feature>
        <Feature
          title="Fewer Git conflicts"
          description="Spend less time solving git conflicts and more building great apps"
        >
          <Rocket sx={featureSx} />
        </Feature>
        <Feature
          title="Best practices"
          description="Easily enforce best practices & conventions in the project structure"
        >
          <Astronaut sx={featureSx} />
        </Feature>
      </div>
    </div>
  );
};

const OpenSource = ({ githubUrl, slackUrl }) => {
  const buttonIconSx = { width: "25px", height: "25px", mr: 3 };
  const buttonASx = {
    display: "flex",
    flexDirection: "row",
    alignItems: "center",
    p: 3,
    borderRadius: 2,
    boxShadow: theme =>
      `0px 0px 0px 1px ${theme.colors.primaryComplementary} inset`,
    color: "primaryComplementary",
    bg: "primary",
    whiteSpace: "nowrap",
    "&:hover": {
      boxShadow: theme => `0px 0px 0px 1px ${theme.colors.background} inset`,
      textDecoration: "none",
      borderColor: "background",
      bg: "background",
      color: "text"
    }
  };
  return (
    <div sx={{ display: "flex", bg: "primary" }}>
      <WithMargin sx={{ color: "white" }}>
        <div
          sx={{
            display: "flex",
            marginTop: 4,
            flexDirection: ["column", "column", "row"],
            alignItems: ["center", "center", "flex-end"]
          }}
        >
          <div sx={{ mb: [0, 0, -25] }}>
            <Developer
              sx={{ height: [130, 130, 240, 300], width: [270, 270, 330, 400] }}
            />
          </div>
          <div
            sx={{
              display: "flex",
              flex: 1,
              // ml: [0, 0, -30],
              flexDirection: "column",
              alignItems: ["center", "center", "flex-end"],
              justifyContent: "flex-end"
            }}
          >
            <Styled.h2
              sx={{
                textAlign: ["center", "center", "right"],
                color: "primaryComplementary"
              }}
            >
              An{" "}
              <span
                sx={{
                  borderBottom: theme => `5px solid ${theme.colors.accent}`
                }}
              >
                open source
              </span>{" "}
              project
            </Styled.h2>
            <p
              sx={{
                textAlign: ["center", "center", "right"],
                color: "primaryComplementary"
              }}
            >
              Tuist is entirely designed and developed in the open. Moreover, it
              embraces Unix philosophy: Make each program do one thing well. The
              project is made of smaller libraries that focus on doing one thing
              well, like <b>XcodeProj</b>.
            </p>
            <p
              sx={{
                color: "primaryComplementary",
                textAlign: ["center", "center", "right"]
              }}
            >
              Anyone has a place and voice in our healthy, collaborative, and
              ego-free community.
            </p>
            <div
              sx={{ display: "flex", flexDirection: ["column", "row"], pb: 5 }}
            >
              <a
                sx={{
                  ...buttonASx,
                  mx: 2,
                  my: [1, 0],
                  p: 12
                }}
                href={githubUrl}
                target="__blank"
              >
                <GitHub sx={buttonIconSx} /> <span>GitHub</span>
              </a>
              <a
                sx={{
                  ...buttonASx,
                  mx: 2,
                  my: [1, 0],
                  p: 12
                }}
                href={slackUrl}
                target="__blank"
              >
                <Slack sx={buttonIconSx} /> <span>Join our Slack</span>
              </a>
            </div>
          </div>
        </div>
      </WithMargin>
    </div>
  );
};

const Mission = ({ authors }) => {
  return (
    <WithMargin sx={{ marginTop: 4 }}>
      <Styled.h2 sx={{ textAlign: "center" }}>Our mission</Styled.h2>
      <p style={{ textAlign: "center" }}>
        We aim to provide a command line tool that makes the interaction with
        Xcode projects approachable, standard, and convenient at any scale,
        built on the principles of ease of use and reliability, and powered by
        Swift in the open.
      </p>
      <div
        sx={{
          display: "flex",
          justifyContent: "center",
          alignItems: "center",
          flexWrap: "wrap",
          mb: 4
        }}
      >
        {authors.map((author, index) => {
          return (
            <a
              alt={author.name}
              href={`https://twitter.com/${author.twitter}`}
              target="__blank"
              key={index}
            >
              <Avatar src={author.avatar} />
            </a>
          );
        })}
      </div>
    </WithMargin>
  );
};

const Avatar = ({ src }) => {
  return (
    <img
      sx={{
        height: [40, 60, 60],
        width: [40, 60, 60],
        borderRadius: [20, 30, 30],
        mx: 2
      }}
      src={src}
    />
  );
};

const TestItOut = ({ gettingStartedUrl }) => {
  const commands = [
    { text: "tuist init", cmd: true },
    { text: "✅ Success: Project generated at path MyProject", cmd: false },
    { text: "", cmd: false },
    { text: "tuist generate", cmd: true },
    {
      text: "✅ Success: Xcode project generated at MyProject.xcodeproj",
      cmd: false
    }
  ];
  return (
    <div sx={{ color: "background", bg: "primary", pb: 5 }}>
      <WithMargin sx={{ paddingTop: 4 }}>
        <div
          sx={{
            display: "flex",
            flex: "1",
            flexDirection: ["column", "column", "row"],
            alignItems: ["stretch", "stretch", "center"]
          }}
        >
          <div
            sx={{
              display: "flex",
              flex: 1,
              flexDirection: "column",
              alignItems: ["center", "center", "flex-start"],
              marginBottom: [4, 4, 0]
            }}
          >
            <Styled.h2
              sx={{
                color: "primaryComplementary",
                textAlign: ["center", "left"]
              }}
            >
              Test it out!
            </Styled.h2>
            <p
              sx={{
                color: "primaryComplementary",
                textAlign: ["center", "center", "left"]
              }}
            >
              Stop wasting your time figuring out complicated Xcode issues in
              your projects and let us help you with that.
            </p>
            <p
              sx={{
                color: "primaryComplementary",
                textAlign: ["center", "center", "left"]
              }}
            >
              You can adopt Tuist <b>incrementally</b> without having to change
              the structure of your projects.
            </p>
            <a
              href={gettingStartedUrl}
              target="__blank"
              sx={{
                p: 3,
                borderRadius: 2,
                boxShadow: theme =>
                  `0px 0px 0px 1px ${theme.colors.primaryComplementary} inset`,
                color: "primaryComplementary",
                bg: "primary",
                alt: "Start using the project",
                "&:hover": {
                  boxShadow: theme =>
                    `0px 0px 0px 1px ${theme.colors.background} inset`,
                  textDecoration: "none",
                  borderColor: "background",
                  bg: "background",
                  color: "text"
                }
              }}
            >
              Getting started
            </a>
          </div>
          <div sx={{ flex: "1", mx: 4 }}>
            <Terminal
              lines={commands}
              interval={80}
              style={{ border: "none" }}
              white
            />
          </div>
        </div>
      </WithMargin>
    </div>
  );
};

const OneMoreThing = ({ contributeUrl }) => {
  const iconProperties = { width: [60], height: [60] };
  return (
    <div
      sx={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        marginBottom: 4,
        marginTop: 4
      }}
    >
      <Styled.h2 style={{ textAlign: "center" }}>One more thing...</Styled.h2>
      <p sx={{ textAlign: "center" }}>
        There’s a lot more to come. Project generation opens the door to
        workflow improvements that will make your experience working with Xcode
        much more pleasant. Stay tuned to the exciting backlog we have ahead.
      </p>
      <div
        sx={{
          display: "flex",
          alignSelf: "stretch",
          my: [3, 3],
          flexDirection: ["column", "row"],
          flexWrap: "wrap",
          alignItems: ["center", "center", "center", "center", "flex-start"],
          justifyContent: [
            "center",
            "center",
            "center",
            "center",
            "space-between"
          ]
        }}
      >
        <Feature
          title="Swift Package Manager support"
          description="Easily integrate third party packages into your projects"
        >
          <BoxIcon sx={iconProperties} />
        </Feature>
        <Feature
          title="Selective test runs"
          description="Selectively run tests based on the changed files"
        >
          <Check sx={iconProperties} />
        </Feature>
        <Feature
          title="Build insights"
          description="Auto-generated reports about your projects and builds"
        >
          <Report sx={iconProperties} />
        </Feature>
        <Feature
          title="Distributed incremental builds"
          description="Leveraging alternative build systems such as Buck or Bazel"
        >
          <Truck sx={iconProperties} />
        </Feature>
      </div>

      <a
        href={contributeUrl}
        target="__blank"
        alt="Learn how to contribute to the project"
        sx={{
          p: 3,
          borderRadius: 2,
          boxShadow: theme =>
            `0px 0px 0px 1px ${theme.colors.primaryComplementary} inset`,
          color: "primaryComplementary",
          bg: "background",
          alt: "Start using the project",
          "&:hover": {
            boxShadow: theme =>
              `0px 0px 0px 1px ${theme.colors.primaryComplementary} inset`,
            textDecoration: "none",
            borderColor: "background",
            bg: "primary",
            color: "primaryComplementary"
          }
        }}
      >
        I want to contribute
      </a>
    </div>
  );
};
const IndexPage = ({
  data: {
    site: {
      siteMetadata: {
        contributeUrl,
        gettingStartedUrl,
        documentationUrl,
        githubUrl,
        slackUrl
      }
    },
    allAuthorsYaml,
    allProjectsYaml
  }
}) => {
  const authors = allAuthorsYaml.edges.map(edge => edge.node);

  return (
    <Layout>
      <Meta />
      <HomeHeader
        gettingStartedUrl={gettingStartedUrl}
        documentationUrl={documentationUrl}
      />
      <main>
        <WithMargin>
          <Why />
        </WithMargin>
        <OpenSource githubUrl={githubUrl} slackUrl={slackUrl} />
        <Mission authors={authors} />
        {/* <TrustedBy projects={projects} /> */}
        <TestItOut gettingStartedUrl={gettingStartedUrl} />
        <WithMargin>
          <OneMoreThing contributeUrl={contributeUrl} />
        </WithMargin>
      </main>
      <Footer />
    </Layout>
  );
};

export default IndexPage;

export const query = graphql`
  query {
    site {
      siteMetadata {
        contributeUrl
        gettingStartedUrl
        documentationUrl
        githubUrl
        slackUrl
      }
    }
    allAuthorsYaml {
      edges {
        node {
          name
          avatar
          twitter
        }
      }
    }
    allProjectsYaml {
      edges {
        node {
          name
          link
          linkName
        }
      }
    }
  }
`;
