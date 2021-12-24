# frozen_string_literal: true

Rails.application.routes.draw do
  # GraphQL
  devise_for :users, controllers: {
    omniauth_callbacks: "users/omniauth_callbacks",
    sessions: "users/sessions",
    registrations: "users/registrations",
  }

  # GraphiQL
  if Rails.env.development?
    mount GraphiQL::Rails::Engine, at: "/graphiql", graphql_path: "/graphql"
  end
  post "/graphql", to: "graphql#execute"

  # React App
  root to: "application#app"

  get "/(*all)", to: "application#app"
end
