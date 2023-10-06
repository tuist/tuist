# Tuist Cloud

Tuist Cloud is a server-side add-on for [Tuist](https://tuist.io), designed to provide features that require storing and sharing state and integrating with other services via web-based APIs. The project is powered by [Ruby](https://www.ruby-lang.org/en/) and [Ruby on Rails](https://rubyonrails.org/).

Unlike Tuist, Tuist Cloud is a closed-source project with a monetization component that aims to bring the necessary resources to **support the development of Tuist.**

## Enterprise

If you are an enterprise user of Tuist Cloud, you can check out the documentation [here](https://docs.next.tuist.io/tutorials/tuist-cloud).

## Development

### Environments

| Environment | Description | URL | Database |
| --- | ---- | ---- | --- |
| **Production** | Default environment | [https://cloud.tuist.io](https://cloud.tuist.io) | Production (Neon Database) |
| **Canary** | Used for testing new features before they are released to production | [https://cloud-canary.tuist.io](https://cloud-canary.tuist.io) | Canary (Fly-managed) |
| **Staging** | Used for testing new features during development. It can be disposed along with its databse when needed | [https://staging.cloud.tuist.io](https://staging.cloud.tuist.io) | Staging (Fly-managed) |

