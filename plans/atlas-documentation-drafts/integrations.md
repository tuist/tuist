## Choose your providers

Atlas connects to external services for sign-in, object storage, communication, payments, document processing, and assisted workflows. Configuration is currently spread across application settings and deployment configuration.

Self-hosting work will make capabilities explicit and remove implicit Tuist defaults. Until then, inspect the relevant settings and jobs before enabling a provider.

## Sign-in and storage

Google is the current sign-in provider. Set your own credentials and allowed email domain. File workflows use a shared storage boundary; production uses compatible object storage, while local storage is intended for development and tests.

## Communication and finance

Slack, email, postal delivery, and payment providers have independent credentials and destinations. Check sending identities, channel identifiers, and payment settings against your organization's accounts.

## Assisted workflows

Model-backed workflows require configured inference providers. Upstream tool connections have their own authorization in addition to Atlas permissions. Reauthorize the specific upstream connection when its credentials or permissions change.

## Tuist connections

Atlas currently includes Tuist-specific customer signals and upstream tools. These are being separated into an explicit connection. Do not configure Tuist's internal destinations or credentials for an independent installation.
