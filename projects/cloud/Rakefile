# frozen_string_literal: true

# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative "config/application"
require "graphql/rake_task"

GraphQL::RakeTask.new(schema_name: "TuistCloudSchema")

Rails.application.load_tasks
