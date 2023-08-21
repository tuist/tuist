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

  get "/get-started", to: "root#get_started"


  get "/auth/invitations/:token", to: "auth#accept_invitation"
  get "/auth/cli/success", to: "auth#cli_success"
  get "/auth", to: "auth#authenticate"

  post "/api/analytics", to: "analytics#analytics"

  namespace :api do
    get "/cache", to: "cache#cache"
    get "/cache/exists", to: "cache#exists"
    post "/cache", to: "cache#upload_cache_artifact"
    post "/cache/verify_upload", to: "cache#verify_upload"
    put "/projects/:account_name/:project_name/cache/clean", to: "cache#clean"

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
