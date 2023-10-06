# frozen_string_literal: true

# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative "config/application"
require "graphql/rake_task"

GraphQL::RakeTask.new(schema_name: "TuistCloudSchema")

Rails.application.load_tasks

task "Deploys the app to the staging environment"
task "deploy:staging" do
  system("flyctl deploy -c fly.staging.toml --build-arg RAILS_ENV=staging --vm-memory=2048 --wait-timeout 600") || abort
end

desc "Deploys the app to the canary environment"
task "deploy:canary" do
  system("flyctl deploy -c fly.canary.toml --build-arg RAILS_ENV=canary --vm-memory=2048 --wait-timeout 600") || abort
end
