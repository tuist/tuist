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

  root to: "root#app"

  get "/invitations/:token/", to: "application#app", as: :invitation

  get "/auth", to: "auth#authenticate"

  get "/api/cache", to: "cache#cache"
  get "/api/cache/exists", to: "cache#exists"
  post "/api/cache", to: "cache#upload_cache_artifact"
  post "/api/cache/verify_upload", to: "cache#verify_upload"

  post "/api/analytics", to: "analytics#analytics"

  namespace :api do
    resources :projects, :projects, only: [:index, :create, :destroy]
  end


  get "/(*all)", to: "application#app"
end
