# frozen_string_literal: true

# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative "config/application"

desc("Starts the Webpacker and Rails processes alongside")
task :start do
  system("bundle exec foreman start -f Procfile.dev") || abort
end

desc("Lints the style in Ruby files")
task :ruby_correct do
  system("bundle exec rubocop")
end

desc("Corrects the Ruby linting issues")
task :ruby_correct do
  system("bundle exec rubocop -a")
end

desc("Corrects the code style")
task :correct do
  Rake::Task["erb_correct"].invoke
  Rake::Task["ruby_correct"].invoke
end

Rails.application.load_tasks
