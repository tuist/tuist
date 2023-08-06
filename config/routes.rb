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
    resources :projects, :projects, only: [:create, :index, :destroy]
    resources :organizations, :organizations, only: [:create, :index, :destroy, :show]
    get '/projects/:account_name/:project_name', to: 'projects#show'
    resources :invitations, path: '/organizations/:organization_name/invitations', only: [:create]
    delete '/organizations/:organization_name/invitations', to: 'invitations#destroy'
    delete '/organizations/:organization_name/members/:username', to: 'members#destroy'
    put '/organizations/:organization_name/members/:username', to: 'members#update'
  end

  get "/(*all)", to: "application#app"
end
