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

  root to: "application#app"

  get "/get-started", to: "application#get_started"
  post "/create-customer-portal-session/:account_id", to: "organizations#billing_plan"

  resources :organizations, param: :name, only: [:index] do
    get 'billing/plan', to: "organizations#billing_plan"
  end

  resources :projects, path: '/:account_name', param: :project_name, only: [:show] do
  end

  resources :projects, path: '/:account_name', param: :name, only: [] do
    get 'analytics', to: 'analytics#analytics'
    get 'analytics/targets', to: 'analytics#analytics_targets'
  end

  get "/auth/invitations/:token", to: "auth#accept_invitation"
  get "/auth/cli/success", to: "auth#cli_success"
  get "/auth", to: "auth#authenticate"

  namespace :api do
    get "/cache", to: "cache#show"
    get "/cache/exists", to: "cache#exists"
    post "/cache", to: "cache#upload_cache_artifact"
    post "/cache/verify_upload", to: "cache#verify_upload"
    put "/projects/:account_name/:project_name/cache/clean", to: "cache#clean"

    post "/analytics", to: "analytics#analytics"

    resources :projects, :projects, only: [:create, :index, :destroy]
    resources :organizations, :organizations, only: [:create, :index, :destroy, :show]
    get '/projects/:account_name/:project_name', to: 'projects#show'
    resources :invitations, path: '/organizations/:organization_name/invitations', only: [:create]
    delete '/organizations/:organization_name/invitations', to: 'invitations#destroy'
    delete '/organizations/:organization_name/members/:username', to: 'members#destroy'
    put '/organizations/:organization_name/members/:username', to: 'members#update'
  end

  post '/webhooks/stripe', to: 'webhooks#stripe'

  get "/(*all)", to: "application#app"
end
