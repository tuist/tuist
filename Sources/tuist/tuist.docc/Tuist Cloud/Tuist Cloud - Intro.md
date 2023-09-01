# What is Tuist Cloud

Addressing large-scale challenges necessitates persisting state and service integration, for which Tuist Cloud is key. This paid solution is vital for Tuist project integration and its open-source project's longevity.

## Overview

Utilizing a graph of dependencies for representing projects and converting them into Xcode projects showed that this approach could be **foundational for optimizing workflows**, thereby preventing unnecessary time wastage for organization's developers. Key features that leverage this foundational approach include **local binary caching**, which enables the generation of projects with some targets replaced by their pre-compiled binary counterparts, and selective testing, which allows running tests only for the targets impacted by changes.

As we advanced towards enhancing productivity, it became evident that **certain solutions necessitated an HTTP server for state storage and building integrations with other HTTP services** like [GitHub](https://github.com), [Slack](https://slack.com), or [Apple Store Connect](https://appstoreconnect.apple.com/). For instance, caching could leverage a server to share binaries across local and CI environments, thereby accelerating build and test times. This realization led to the creation of Tuist Cloud.

Tuist Cloud, a closed-source paid service, enhances Tuist by adding server-requisite functionalities. Integration of Tuist projects with Tuist Cloud not only augments existing functionalities but also introduces new ones. This service encapsulates years of experience in developing tools for mobile developers at [Shopify](https://shopify.com) (e.g., [Mobile Tophat](https://shopify.engineering/mobile-tophatting-at-shopify-1), [Mobile Release Engineering at Scale](https://shopify.engineering/mobile-release-engineering-scale-shipit-mobile), [Scaling iOS CI with Anka](https://shopify.engineering/scaling-ios-ci-with-anka)) and is envisioned as **the copilot for your platform teams**. Our objective is to help organizations cultivate a productive development environment.

> Note: Similar to many other open-source projects, Tuist also necessitated full-time dedicated personnel to adequately meet the demand for support and feature requests. Tuist Cloud plays a crucial role in fulfilling this requirement by enabling the financing of full-time personnel for the project.

## Features

Tuist Cloud 

## Plans

One of the initial decisions you or your organization must make is **determining the plan that best suits your needs**. Below is a breakdown of the available plans along with some recommendations to help you assess whether a particular plan aligns with your requirements:

#### Indie

If you are an **individual developer** working on a project, this is the advised option. It provides access to the complete feature set, however, it does not permit granting access to the project to others. It's important to note that the support available under this plan is community-based, hence it does not have as high a priority as the support provided in the plans listed below.

> Tip: If you wish to test your project against Tuist Cloud, we recommend using a personal account for the tests.

#### Team

If there are **multiple people working on the project**, this is the recommended option. You will be able to create organizations that serve as the umbrella for multiple projects and invite people to join the organization. This plan provides access to the complete feature set and also includes community-based support, similar to the Indie plan.

> Important: Unlike Tuist, which is supported by an [Open Collective fiscal host](https://opencollective.com/tuistapp), Tuist Cloud is supported by a legally incorporated German entity, **Tuist GmbH**. This entity is legally responsible for any issues that may arise.

#### Enterprise

For organizations that prefer to host the software on their own infrastructure, require SAML Single-Sign-On, and seek additional, prioritized support and advice from the creators of Tuist and Tuist Cloud, we offer an enterprise plan. If this option interests you, please reach out to [sales@tuist.io](mailto:sales@tuist.io).
If you are already an enterprise customer of Tuist Cloud, you can follow our <doc:Tuist-Cloud---Self-host> tutorial to deploy and update Tuist Cloud on your infrastructure.
