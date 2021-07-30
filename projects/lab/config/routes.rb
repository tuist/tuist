# typed: ignore
# frozen_string_literal: true
require "sidekiq/web"

Rails.application.routes.draw do
  if Rails.env.development?
    mount GraphiQL::Rails::Engine, at: "/graphiql", graphql_path: "/graphql"
  end
  post "/graphql", to: "graphql#execute"
  mount RailsAdmin::Engine => "/admin", as: "rails_admin"

  # Devise
  devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks" }

  authenticate :user, lambda { |u| u.has_role?(:admin) } do
    mount Sidekiq::Web => "/sidekiq"
  end

  # API
  defaults format: :json do
    scope :api do
      post "/upload", to: "api#upload"
    end
  end

  # Landing
  root to: "app#index"
  get "/", to: "app#index", as: :app
  get "*path", to: "app#index"
end
