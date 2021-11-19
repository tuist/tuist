# frozen_string_literal: true

Rails.application.routes.draw do
  resources :command_events

  # Web app
  root to: "application#home"
end
