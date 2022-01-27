# frozen_string_literal: true

require 'yard'
require 'rubocop'
require 'rubocop-minitest'
require 'rubocop/cops_documentation_generator'

YARD::Rake::YardocTask.new(:yard_for_generate_documentation) do |task|
  task.files = ['lib/rubocop/cop/**/*.rb']
  task.options = ['--no-output']
end

desc 'Generate docs of all cops departments'
task generate_cops_documentation: :yard_for_generate_documentation do
  deps = ['Minitest']
  CopsDocumentationGenerator.new(departments: deps).call
end

desc 'Verify that documentation is up to date'
task verify_cops_documentation: :generate_cops_documentation do
  # Do not print diff and yield whether exit code was zero
  sh('git diff --quiet docs') do |outcome, _|
    exit if outcome

    # Output diff before raising error
    sh('GIT_PAGER=cat git diff docs')

    warn 'The docs directory is out of sync. ' \
      'Run `rake generate_cops_documentation` and commit the results.'
    exit!
  end
end

desc 'Syntax check for the documentation comments'
task documentation_syntax_check: :yard_for_generate_documentation do
  require 'parser/ruby25'

  ok = true
  YARD::Registry.load!
  cops = RuboCop::Cop::Registry.global
  cops.each do |cop|
    examples = YARD::Registry.all(:class).find do |code_object|
      next unless RuboCop::Cop::Badge.for(code_object.to_s) == cop.badge

      break code_object.tags('example')
    end

    examples.to_a.each do |example|
      buffer = Parser::Source::Buffer.new('<code>', 1)
      buffer.source = example.text
      parser = Parser::Ruby25.new(RuboCop::AST::Builder.new)
      parser.diagnostics.all_errors_are_fatal = true
      parser.parse(buffer)
    rescue Parser::SyntaxError => e
      path = example.object.file
      puts "#{path}: Syntax Error in an example. #{e}"
      ok = false
    end
  end
  abort unless ok
end
