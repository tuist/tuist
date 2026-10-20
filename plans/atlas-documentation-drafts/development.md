## Before you start

Atlas is an Elixir application built with Phoenix and PostgreSQL. It currently lives in the [Tuist repository](https://github.com/tuist/tuist/tree/main/atlas), alongside the Noora design system that it uses.

Use the versions pinned in the repository's [mise configuration](https://github.com/tuist/tuist/blob/main/.mise.toml). Keep the monorepo checkout available when building, since Atlas depends on sibling packages.

## Prepare the application

From the Atlas directory, install the dependencies:

```sh
mise exec -- mix deps.get
```

Build Noora's assets from the `noora` directory before building Atlas's assets. Follow the repository's development configuration for the database and application keys. Production requires a database connection and independent session, authentication, and encryption secrets.

## Create the database

With your database connection configured, run:

```sh
mise exec -- mix ecto.create
mise exec -- mix ecto.migrate
```

Run the existing migration chain against an empty database. Avoid demo seeds when preparing a real installation. Migrations create the schema and required role definitions; signing in alone does not assign a role.

## Configure sign-in

Atlas currently uses Google sign-in. Configure credentials for your own Google application and its callback address, then set `ATLAS_ALLOWED_EMAIL_DOMAIN` to your organization's domain. This setting updates the sign-in restriction and Google's account-picker hint together.

For example, `ATLAS_ALLOWED_EMAIL_DOMAIN=example.org` admits that domain. An unset value preserves the existing Tuist default. A blank or malformed value is rejected. Admission does not grant administrative access.

## Start Atlas

For local development, start the Phoenix server:

```sh
mise exec -- mix phx.server
```

Sign in once with the person who will administer the installation, then follow the [first administrator guide](/docs/first-administrator).

## Current limitations

> [!WARNING]
> Self-hosting is still being generalized. Optional integrations and background jobs are not yet uniformly gated, and some defaults still refer to Tuist. Review configuration before enabling workers or delivery providers. Do not assume that omitting credentials disables every integration.
>
> A supported standalone deployment and a complete installation configuration reference are planned work. This guide is a source-checkout starting point.
