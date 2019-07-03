---
name: Galaxy
menu: Contributors
---

# Galaxy

Galaxy is a [Rails](https://rubyonrails.org/) application that exposes a [GraphQL API](https://graphql.org/learn/) that is consumed by a [React](https://reactjs.org/) frontend that is bundled and served by Rails using [Webpacker](https://github.com/rails/webpacker).

## Set up for development

- Git clone the repository: `git clone git@github.com:tuist/tuist.git`.
- Install [Postgress](https://www.postgresql.org/download/macosx/).
- Choose the galaxy directory: `cd galaxy`.
- Install Bundler dependencies: `bundle install`.
- Install NPM dependencies: `yarn install`.
- Run: `rails start`.

## Storybook

The project has [Storybook](https://storybook.js.org/) configured, a Javascript tool to create a catalogue for the project components. The catalogue entries are called stories, and they are defined in the directory `stories/`.

To run the catalogue, just run the command `yarn storybook` in your terminal. That'll transpile the catalogue and open the browser with it.

## Useful commands

- `rails db:drop`: Deletes the database.
- `rails db:create`: Creates the database.
- `rails db:migrate`: Migrates the database structure.

## Useful resources

- [Rails](https://rubyonrails.org/)
- [Styled components](https://www.styled-components.com/)
- [Relay](https://relay.dev/)
- [GraphQL](https://graphql.org/learn/)
- [React](https://reactjs.org/)
- [Webpacker](https://github.com/rails/webpacker)
