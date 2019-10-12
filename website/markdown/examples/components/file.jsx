/** @jsx jsx */
import { jsx } from "theme-ui";

import Prism from "prismjs/components/prism-core";
import Highlight, { defaultProps } from "prism-react-renderer";
import theme from "prism-react-renderer/themes/nightOwl";
import { useState } from "react";

const files = {
  "ios-carthage-project": `
  import ProjectDescription

  let appTarget = Target(name: "Angle",
                         platform: .iOS,
                         product: .app,
                         bundleId: "io.tuist.Angle",
                         infoPlist: "Info.plist",
                         sources: ["Sources/**"],
                         dependencies: [
                          .framework(path: "Carthage/Build/iOS/RxSwift.framework")
                         ])
  let project = Project(name: "Angle", targets: [appTarget]
  `,
  "ios-carthage-setup": `
  import ProjectDescription

  let setup = Setup([.carthage(platforms: [.iOS])])
  `,
  "macos-cocoapods-project": `
  import ProjectDescription

  let appTarget = Target(name: "Angle",
                        platform: .iOS,
                        product: .app,
                        bundleId: "io.tuist.Angle",
                        infoPlist: "Info.plist",
                        sources: ["Sources/**"],
                        dependencies: [
                          .cocoapods(path: ".")
                        ])
  let project = Project(name: "Angle", targets: [appTarget])                     
  `,
  "macos-cocoapods-podfile": `
  project 'Angle'
  platform :osx, '10.13'

  target 'Angle' do
    use_frameworks!

    pod "Sparkle"
  end
  `,
  "ios-frameworks-project": `
  let app = Target(name: "Angle",
                   platform: .iOS,
                   product: .app,
                   bundleId: "io.tuist.Angle",
                   infoPlist: "App/Info.plist",
                   sources: ["App/Sources/**"],
                   dependencies: [.target("Login")])

  let login = Target(name: "Login",
                     platform: .iOS,
                     product: .framework,
                     bundleId: "io.tuist.Login",
                     infoPlist: "Login/Info.plist",
                     sources: ["Login/Sources/**"],
                     dependencies: [.target("Core")])

  let core = Target(name: "Core",
                    platform: .iOS,
                    product: .framework,
                    bundleId: "io.tuist.Core",
                    infoPlist: "Core/Info.plist",
                    sources: ["Core/Sources/**"])

  let project = Project(name: "Angle", targets: [app, login, core])  
  `,
  "ios-modular-frameworks-libraries-project": `
  let app = Target(name: "Angle",
                   platform: .iOS,
                   product: .app,
                   bundleId: "io.tuist.Angle",
                   infoPlist: "App/Info.plist",
                   sources: ["App/Sources/**"],
                   dependencies: [.target("Login")])

  let login = Target(name: "Login",
                     platform: .iOS,
                     product: .framework,
                     bundleId: "io.tuist.Login",
                     infoPlist: "Login/Info.plist",
                     sources: ["Login/Sources/**"],
                     dependencies: [.target("Core")])

  let core = Target(name: "Core",
                    platform: .iOS,
                    product: .staticLibrary,
                    bundleId: "io.tuist.Core",
                    infoPlist: "Core/Info.plist",
                    sources: ["Core/Sources/**"])
                    
  let project = Project(name: "Angle", targets: [app, login, core])  
  `
};

const File = ({ fileName, code, language }) => {
  const [opened, setOpened] = useState(false);
  return (
    <div sx={{ display: "flex", flexDirection: "column" }}>
      <div
        sx={{
          fontSize: 2,
          cursor: "pointer",
          bg: "primary",
          color: "primaryComplementary",
          p: 2,
          mb: opened ? 0 : 3
        }}
        onClick={() => setOpened(!opened)}
      >
        {opened ? `▲ ${fileName}` : `▼ ${fileName}`}
      </div>
      {opened && (
        <Highlight
          {...defaultProps}
          theme={theme}
          code={files[code]}
          language={language}
          Prism={Prism}
        >
          {({ className, style, tokens, getLineProps, getTokenProps }) => (
            <pre className={className} style={style}>
              {tokens.map((line, i) => (
                <div {...getLineProps({ line, key: i })}>
                  {line.map((token, key) => (
                    <span {...getTokenProps({ token, key })} />
                  ))}
                </div>
              ))}
            </pre>
          )}
        </Highlight>
      )}
    </div>
  );
};

export default File;
