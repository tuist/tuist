require 'rubygems'
require 'cucumber'
require 'cucumber/rake/task'
require 'mkmf'

Cucumber::Rake::Task.new(:features) do |t|
  t.cucumber_opts = "--format pretty"
end

desc "Lints the Swift code style"
task :style_swift do
  abort_unless_swiftlint_installed
  system("swiftlint") || abort
end

desc "Corrects the issues with the Swift style"
task :style_swift_correct do
  abort_unless_swiftlint_installed
  system("swiftlint", "autocorrect")
end


def abort_unless_swiftlint_installed
  abort("swiftlint not installed. Run 'brew install swiftlint'") unless find_executable('swiftlint')
end