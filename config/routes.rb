# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :users, controllers: {
    omniauth_callbacks: "users/omniauth_callbacks",
    sessions: "users/sessions",
    registrations: "users/registrations",
  }
  root to: "application#app"

  namespace :api do
    delete '/organizations/:organization_name/invitations', to: 'invitations#destroy'
    delete '/organizations/:organization_name/members/:username', to: 'members#destroy'
    get '/projects/:account_name/:project_name', to: 'projects#show'
    get "/cache", to: "cache#show"
    get "/cache/exists", to: "cache#exists"
    post "/analytics", to: "analytics#analytics"
    post "/cache", to: "cache#upload_cache_artifact"
    post "/cache/verify_upload", to: "cache#verify_upload"
    put '/organizations/:organization_name/members/:username', to: 'members#update'
    put "/projects/:account_name/:project_name/cache/clean", to: "cache#clean"
    resources :invitations, path: '/organizations/:organization_name/invitations', only: [:create]
    resources :organizations, :organizations, only: [:create, :index, :destroy, :show]
    resources :projects, :projects, only: [:create, :index, :destroy]
  end

  resources :organizations, param: :name, only: [:index] do
    get 'billing/plan', to: "organizations#billing_plan"
  end

  resources :projects, path: '/:account_name', param: :name, only: [] do
    get 'analytics', to: 'analytics#analytics'
    get 'analytics/targets', to: 'analytics#analytics_targets'
  end

  get "/ready", to: "application#ready"
  get "/auth/invitations/:token", to: "auth#accept_invitation"
  get "/auth/cli/success", to: "auth#cli_success"
  get "/auth", to: "auth#authenticate"
  post '/webhooks/stripe', to: 'webhooks#stripe'
  resources :projects, path: '/:account_name', param: :project_name, only: [:show]
  get "/get-started", to: "application#get_started"
  post "/create-customer-portal-session/:account_id", to: "organizations#billing_plan"

  get "/(*all)", to: "application#app"
end
