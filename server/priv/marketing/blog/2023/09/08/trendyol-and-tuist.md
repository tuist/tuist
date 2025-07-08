---
title: "Trendyol and Tuist: Engineering Apps at Scale"
category: "community"
tags: ["Trendyol", "Apps at Scale", "VIPER", "Tuist", "Open Source", "GitLab", "Swift", "SwiftUI"]
type: interview
excerpt: "Dive into our exclusive chat with Trendyol, Turkey's e-commerce giant. Explore how they leverage Tuist for expansive iOS development, unravel their tools, team dynamics, and the secrets to managing tech at scale. A must-read for all developers"
interviewee_name: Trendyol
interviewee_role: E-commerce platform
interviewee_url: https://trendyol.com
interviewee_x_handle: Trendyol
interviewee_avatar: https://avatars.githubusercontent.com/u/13857072?s=200&v=4
---

In the bustling landscape of Turkey's e-commerce, [Trendyol](https://trendyol.com) stands as a beacon. As the nation's foremost e-commerce platform, Trendyol isn't simply about online shopping. It represents an entire digital ecosystem, a "super app," dedicated to providing users with an unparalleled, diverse range of services. But, beneath this massive digital edifice, there's an intricate dance of technology, teamwork, and tools. And one tool that has been instrumental for Trendyol is Tuist. We recently sat down with the developers at Trendyol to gain insights into how they use Tuist to meet the challenges of developing apps on such a monumental scale.

## Project Background and Introduction

### What is the size of your team and what is the structure of its organization?

Our mobile team is composed of a talented and dedicated group of **140 professionals who work collectively on both iOS and Android platforms**. As a dynamic and innovative organization, Trendyol operates as a super app, offering a diverse range of services through various omnichannels on the platform. To ensure efficient management and specialization, each omnichannel has its own dedicated domain teams. This organizational structure enables us to effectively cater to the unique needs and demands of each omnichannel, fostering a cohesive and agile work environment.

As the platform team, we provide services to five different channels and support ten distinct teams. Our primary focus is to enhance the developer experience, tooling, and performance for these teams. We consider each team as our valued client, working diligently to meet their specific needs and align with their interests in these areas.

![A diagram that shows Trendyol's team structure. The platform team supports peripheral organizations such as Turkey, International, DolapLite, Grocery, and Meal, which are focused on a specific products.](/marketing/images/blog/2023/09/08/organization.png)

## Project architecture

### Could you tell us about your project architecture?

We utilize the [VIPER](https://www.objc.io/issues/13-architecture/viper/) architecture in our app, which is composed of View, Interactor, Presenter, Entity, and Router components.

We chose VIPER for its strong alignment with [SOLID principles](https://en.wikipedia.org/wiki/SOLID) and its modular design. This ensures a clean, maintainable codebase and makes unit testing more straightforward. VIPER's scalability also makes it easier to onboard new developers who can focus on specific components.

On a practical level, VIPER promotes **parallel development**. Each developer can specialize in certain components, simplifying code reviews. While there's an initial learning curve and some boilerplate, we find these are outweighed by long-term benefits like maintainability and scalability. We even have **custom Xcode templates** to speed up development.

#### Exploring SwiftUI

We recently shifted our deployment target to [iOS 14](https://support.apple.com/en-us/HT211808). This move opened up the opportunity to integrate [SwiftUI](https://developer.apple.com/xcode/swiftui/) into our project. The motivation behind this was multi-fold:

- **User Experience:** SwiftUI allows for smoother animations and more native components, enhancing the overall user experience.
- **Developer Productivity:** The declarative nature of SwiftUI simplifies UI development, allowing our developers to accomplish more with less code.
- **Future-Proofing:** As Apple pushes SwiftUI as the future of iOS development, adopting it early places us at an advantage in terms of maintainability and access to new features.

As technologies continue to mature and new architectural patterns emerge, we're always open to evaluating them. Whether it's new patterns that mesh well with SwiftUI, or even entirely new paradigms, our team is excited by the potential to improve and optimize.

In summary, **while VIPER has served us well, our architecture is not static**. It's influenced by our commitment to best practices, the evolving tech landscape, and our continual desire to deliver the best possible product.

### What motivated you to migrate to Tuist?

Before using Tuist, we encountered the following problems:

- Committing Xcode project and workspace files to version control, which led to merge conflicts and a lack of flexibility in managing project files.
- Inconsistent manual configuration of Xcode projects, resulting in discrepancies across projects.
- Inconsistent dependency management.
- Unstable [Swift Package Manager (SPM)](https://www.swift.org/package-manager/) resolution processes.
- Complexity in managing Xcode projects and workspaces.
- A time-consuming setup process for new modules.
- Tedious manual steps required for project configuration and setup.

By adopting Tuist, we effectively tackled numerous challenges within our development process.

### How do you use Tuist today?

We have fully integrated Tuist into our development workflow, and the impact has been transformative. Tuist has enabled us to eliminate the need to commit Xcode project and workspace files to version control by utilizing its runtime generation capabilities. This has not only **mitigated the risk of merge conflicts** but also provided us with **greater flexibility in managing project files.**

Moreover, Tuist has played a crucial role in **ensuring consistency across projects** by eliminating the manual configuration of Xcode projects. Its streamlined and intuitive approach to configuration has enabled us to effortlessly **enforce best practices and maintain uniformity throughout our codebase.**

Additionally, Tuist has simplified the management of Xcode projects and workspaces, significantly **reducing complexity**. This has allowed us to focus more on development, sparing us the intricacies of project setup tasks.

One of the most valuable features of Tuist has been its **templates**, which have boosted our productivity. With Tuist's templates, we can swiftly establish new modules with standardized structures and configurations, saving considerable time and effort.

Furthermore, our overall developer experience has improved significantly as Tuist minimized the number of manual steps required for project configuration and setup. Its efficient and automated processes have **streamlined our workflow, empowering us to concentrate on coding and enhancing productivity.**

In summary, Tuist has been instrumental in addressing the challenges we previously faced in Xcode project management, dependency handling, consistency, productivity, and developer experience. Its seamless integration into our development process has revolutionized our project execution, leading to smoother and more efficient development.

### How do you use Tuist templates?

We have integrated the use of [templates](https://docs.old.tuist.io/commands/scaffold/) to **optimize our development process**. A particularly noteworthy template that we employ is engineered to **generate new modules.** This template facilitates the creation of a new Xcode project with customizable parameters, such as its name and path. The resulting project is automatically configured with essential targets, including Interface, Implementation, Test Support, and Tests. This efficient method not only accelerates the initiation of new modules but also guarantees consistency across our projects. It is an invaluable instrument that harmonizes with our development practices and aids us in upholding a superior standard of code quality.

## Build times

### How long do clean and incremental builds take?

The clean build process takes approximately 295 seconds, whereas the **incremental build takes around 40 seconds.** We are managing a substantial total of **230 .xcodeproj modules** within our project.

The clean build involves recompiling the entire project from scratch, which accounts for the longer duration, whereas the incremental build only compiles the modified or newly added files, resulting in a significantly faster build time.

Given the large number of modules, we have **managed to optimize our build times considerably by utilizing incremental builds**. This enhancement in build efficiency has had a positive impact on our development workflow, enabling us to devote more time to coding and reducing turnaround time during development iterations.

### How do you ensure incremental builds work reliably?

We [segregated](https://medium.com/trendyol-tech/revamping-trendyols-ios-app-a-modularization-success-story-a6c1d2c4188b) concrete modules from **interface modules**, enabling us to maximize the benefits of incremental building. In this setup, we employ our own dependency container. Concrete modules are not directly interconnected; rather, interface modules serve as intermediaries between them. Consequently, Xcode only compiles the modified sections, thereby minimizing our build time.

### What’s your release cadence and what does the process look like?

We follow a structured release cadence to guarantee the prompt delivery of packages. Our release cycle is bi-weekly, with predetermined release dates set for each cycle. In preparation for these releases, we initiate the process by creating a [Release Candidate (RC)](https://en.wikipedia.org/wiki/Software_release_life_cycle#Release_candidate) branch a few days before the scheduled release date.

The RC branch functions as a dedicated space for finalizing the upcoming release. Once the RC branch is established, our [Quality Assurance (QA)](https://en.wikipedia.org/wiki/Quality_assurance) team takes the helm and begins [regression testing](https://en.wikipedia.org/wiki/Regression_testing). This rigorous testing phase enables us to comprehensively evaluate the stability and functionality of the package before its live deployment.

Adhering to this approach allows us to confidently ensure the reliability of our releases and **minimize the risk of unexpected issues arising**. Our well-defined release cadence, complemented by the proactive creation of the RC branch and thorough QA regression tests, empowers us to consistently achieve our bi-weekly release targets while upholding a high standard of software quality.

### What’s your testing strategy?

Our [testing strategy](https://medium.com/trendyol-tech/managing-ios-tests-on-scale-a-symphony-a644275d0bbc) encompasses various types of tests, executed intentionally in different scenarios and, when necessary, capable of blocking pipelines. To discuss this quantitatively:

We have over **25k Unit, 1.5k Regression, 250 Smoke Tests, and 500 Snapshots**. Both smoke and unit tests are executed on every commit and act as blockers on merge requests.

[**Unit Tests**](https://en.wikipedia.org/wiki/Unit_testing) are indispensable. For many years, it has been mandatory to write and maintain tests for all developments. Recently, we have been using tools (explained in the tools section) that automatically generate these tests, speeding up the process. However, it is crucial to maintain a balance between automation and manual effort to prevent the tests from being neglected, much like unread documents. We continuously fine-tune this balance.

Our **UI Testing framework**, built on [XCUITest](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/09-ui_testing.html), is highly advanced. A significant portion of the code is auto-generated by our internal code generators. Our internal mock server allows us to easily mock the desired services. [This setup](https://medium.com/trendyol-tech/how-to-make-ios-ui-testing-fast-and-reliable-6f572a0955f2) simplifies the process of writing smoke tests for basic flows during development.

[**Smoke Tests**](https://en.wikipedia.org/wiki/Smoke_testing_(software)) were initially written to ensure that every page and element worked flawlessly before writing complex regression tests in the production environment. Another purpose was to confirm that the UI test infrastructure wasn't broken by the developments, by adding these tests as a merge check at an early stage. We quickly achieved close to 100% coverage, and it is now a must to add these tests when new pages are written.

[**Regression Tests**](https://en.wikipedia.org/wiki/Regression_testing) operate in the production environment using real test data and leverage the same architecture created for our smoke tests. These tests ensure existing functionality remains untouched with new updates. This approach not only assures quality but also accelerates our release cycle.

We use **Snapshot Tests** differently from many teams. Instead of using a unit test style, [we use our existing UI Test framework](https://medium.com/trendyol-tech/automated-visual-testing-with-snapshots-part-1-ee9c5cf58cca) to handle actions and flows while we use the [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) library to take and compare the screenshots. Architectural reasons and considerations around maintenance responsibilities led us to choose this path. We see it as a low-maintenance tool that effectively catches many bugs, and we share all test results via buttons on Slack.

Lastly, we also have a small number of [**Integration tests**](https://en.wikipedia.org/wiki/Integration_testing) written for our in-house SDK(s). End-to-end testing of certain systems, such as events, can be quite difficult and challenging. In this context, these tests grant us a significant amount of confidence in our systems.

### Have you developed any in-house tool?

In our pursuit to streamline our development processes and address the unique challenges we face at Trendyol, we've invested time and effort in developing several in-house tools. These tools are designed to cater to our specific needs, and have significantly contributed to our efficiency and productivity in developing iOS apps at scale. Here is a list of some of the in-house tools we have developed:

#### Mockolo

Mockolo is a powerful tool that generates all the necessary mocks for a protocol, conforming to it with just a single button press. It goes a step further by supporting the new async-await structure. Developed on top of [Uber's Mockolo library](https://github.com/uber/mockolo), it has been tailored to fit the team's needs and optimized for SwiftKit. The mock output has been fine-tuned to align seamlessly with the project requirements, making it an invaluable asset for the team's testing and development processes. With Mockolo, generating mocks and staying up-to-date with new Swift features has never been easier.

#### LatiFlex

LatiFlex is an efficient **in-app debugging tool** designed to streamline our debugging process. With its powerful features, we can easily track network requests, search in network responses, copy Curl commands and responses, monitor analytic events, search events, copy event parameters, execute deeplinks within our application, and seamlessly switch between different environments. LatiFlex simplifies debugging, making it faster and more effective.

#### MockServer

MockServer is a powerful **request mocking tool** that offers flexibility and ease of use. With its user-friendly features, you can effortlessly save and update requests for future use. The tool provides various filtering options such as location (all, path, query, scenario, method, status) to customize your mocking experience. Additionally, you can conveniently list all mocking requests and apply search filters to find specific requests efficiently. MockServer is your go-to solution for seamless and hassle-free request mocking.

#### [GitLab](https://gitlab.com) Menu Bar

GitLab Menu Bar is a handy and **feature-rich menubar application designed for an optimized GitLab experience**. The application lists merge requests with the user's approval count, build status, and conflict mark. It also displays merge requests that need to be reviewed, providing date and approval status for easy sorting. The "Create MR" button generates merge requests based on the user's recently pushed branches. In case of a failed pipeline, the app offers the option to trigger the pipeline again. Additionally, users can switch between branches and create new ones using the macOS Shortcuts app integration. Conflicted files can be opened with Visual Studio Code using the macOS Shortcuts app. The application streamlines the process of sending export IPA requests. For the mobile team, the QA Mode showcases automation tool export options and task status, requiring the board ID. GitLab Menu Bar aims to provide users with convenience and productivity, empowering them to enhance their GitLab workflow. When the user presses the merge button, a confirmation dialog appears, prompting the user to review his actions before proceeding. Creating a new merge request becomes effortless as GitLab automatically formats the merge request name and description for the user. Additionally, the branch name is automatically set as the merge request name, ensuring consistency in identification. For a comprehensive overview, all commit messages are aggregated and set as the merge request description.

#### Dependency Analyzer

A Tuist plugin that analyzes explicit dependencies between modules by using SwiftSyntax.

#### SwityTestGenerator

We developed a tool called [SwityTestGenerator](https://github.com/aytugsevgi/SwityTestGenerator) to **simplify the process of writing UI tests**, which previously required setting accessibility identifiers for each `IBOutlet` individually. This process was repetitive and manual. With SwiftyTestGenerator, we can easily create the necessary elements for UI testing and have made it available for use by all team members.

## Collaboration

### Can you discuss a bit about the collaboration between different roles (such as developers, designers, and product managers) in your team?

Collaboration is a cornerstone of our team’s success, and we have established a well-defined process to ensure **seamless communication and coordination among various roles**, including developers, designers, and product managers.

- **Regular Cross-Functional Meetings:** We hold regular cross-functional meetings, such as sprint planning sessions, stand-ups, and retrospectives. These meetings bring together developers, designers, and product managers to discuss project progress, upcoming features, design considerations, and any potential challenges. This facilitates a shared understanding of goals, timelines, and priorities.
- **Early Involvement in Design:** Designers are an integral part of our development process right from the start. They collaborate closely with product managers and developers to define user stories, user flows, and design mockups. This ensures that design considerations are incorporated early, minimizing potential design-related roadblocks down the line.
- **Collaborative Design Reviews:** Design reviews involve developers, designers, and product managers, where we collectively assess and provide feedback on design mockups and prototypes. This iterative process allows us to align on the visual and functional aspects of the product and make necessary adjustments before development begins.
- **Feature Specification Workshops:** Developers and product managers collaborate on detailed feature specification workshops. These sessions involve in-depth discussions about the technical requirements, user stories, acceptance criteria, and potential challenges. This collaborative effort ensures that the development team has a comprehensive understanding of the desired outcomes.
- **Continuous Communication:** We maintain open lines of communication through various channels, such as messaging platforms and project management tools. This enables quick exchanges of information, updates on progress, and the ability to address questions or concerns in real-time.
- **User Acceptance Testing (UAT):** Product managers and developers work closely during the UAT phase, where the product is tested by stakeholders and users. Feedback from UAT is carefully considered, and any necessary adjustments are made to ensure the final product meets the desired quality and functionality.
- **Retrospectives and Feedback Loops:** Regular retrospectives provide a space for all team members to reflect on the development process, share insights, and suggest improvements. This fosters a culture of continuous improvement and empowers everyone to contribute to the team’s success.

By nurturing a collaborative environment and involving different roles throughout the development lifecycle, we are able to leverage the unique perspectives and expertise of each team member. This holistic approach results in more well-rounded and user-centric solutions, as well as a stronger sense of ownership and shared accomplishment among our team members.

## Closing words

We hope this insight into Trendyol's engineering practices for developing iOS apps at scale has been enlightening. Their adept use of Tuist, among other powerful tools and collaborative practices, not only streamlines their development process but also ensures high code quality and consistency across projects. By fostering a collaborative environment, maintaining open lines of communication, and implementing comprehensive testing strategies, the **Trendyol team successfully navigates the challenges associated with managing a large number of modules and delivering reliable, user-centric solutions.**

We would like to express our gratitude to the engineers at Trendyol for sharing their valuable experiences and strategies. **Their commitment to continuous improvement and innovation is truly inspiring.** We believe that sharing knowledge and best practices like this contributes to the growth and success of the broader developer community.

Thank you for reading, and we hope you found this interview as informative and inspiring as we did. If you are interested in learning more about Tuist and how it can help streamline your development process, please visit [our website](https://tuist.io) or check out [our documentation](https://docs.old.tuist.io) for more details.

For more insights into engineering practices and technical articles, be sure to visit [Trendyol Tech's Medium blog](https://medium.com/trendyol-tech) and our [additional resources.](https://medium.com/trendyol-tech/revamping-trendyols-ios-app-a-modularization-success-story-a6c1d2c4188b)
