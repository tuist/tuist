# frozen_string_literal: true

Rails.application.routes.draw do
  # Devise
  devise_for :users

  # Web app
  root to: "application#app"
  match "*path", to: "application#app", via: :get
end
