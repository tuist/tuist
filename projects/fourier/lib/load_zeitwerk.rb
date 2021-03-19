require 'zeitwerk'

def load_zeitwerk(additional_directories: [])
  loader = Zeitwerk::Loader.new
  loader.push_dir(__dir__)
  additional_directories.each do |dir|
    loader.push_dir(dir)
  end
  loader.inflector.inflect("github_client" => "GitHubClient")
  loader.inflector.inflect("github" => "GitHub")
  loader.setup
end
