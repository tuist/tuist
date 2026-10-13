require 'digest'
require 'json'

phase = ARGV.fetch(0)
state_path = File.join(ENV.fetch('RUNNER_TEMP'), 'volume-manifest-state.json')
environment_path = '.build/.volume-experiment-environment.json'
automatic_exclusions = %w[GITHUB_ACTION GITHUB_ARTIFACTS GITHUB_ARTIFACTS_LIST GITHUB_ENV GITHUB_OUTPUT GITHUB_PATH GITHUB_RUN_ATTEMPT GITHUB_RUN_ID GITHUB_RUN_NUMBER GITHUB_STEP_SUMMARY]
config = File.read('Tuist.swift')
project_exclusions = config[/packageManifestEnvironment: \.automatic\(excluding: \[(.*?)\]\)/m, 1].to_s.scan(/"([A-Z_]+)"/).flatten
environment = ENV.reject { |key, _| (automatic_exclusions + project_exclusions).include?(key) || key == '_' }
fingerprints = environment.transform_values { |value| Digest::SHA256.hexdigest(value) }

if phase == 'before'
  if File.exist?(environment_path)
    previous = JSON.parse(File.read(environment_path))
    changed = (previous.keys | fingerprints.keys).select { |key| previous[key] != fingerprints[key] }.sort
    puts "Manifest-visible environment keys changed since previous job: #{changed.join(', ')}"
  else
    puts 'No per-variable environment baseline retained yet.'
  end
end

files = Dir.glob('.build/swifterpm/**/*').select { |path| File.file?(path) }
state = files.to_h do |path|
  [path, {'mtime' => File.mtime(path).to_f, 'digest' => Digest::SHA256.file(path).hexdigest}]
end
if File.exist?(state_path)
  previous = JSON.parse(File.read(state_path))
  rewritten = state.keys.select { |path| previous[path] && previous[path]['mtime'] != state[path]['mtime'] }
  changed_fingerprints = rewritten.select { |path| path.end_with?('.envhash') && previous[path]['digest'] != state[path]['digest'] }
  puts "#{phase}: #{rewritten.length} cached manifest files rewritten; #{changed_fingerprints.length} environment fingerprints changed"
  puts "#{phase}: rewritten manifest-cache paths: #{rewritten.sort.join(', ')}"
  puts "#{phase}: root package-info rewritten: #{rewritten.include?('.build/swifterpm/package-info/root.json')}"
else
  puts "#{phase}: #{state.length} retained manifest-cache files"
end
File.write(state_path, JSON.generate(state))
File.write(environment_path, JSON.generate(fingerprints)) if phase == 'after-first'
if phase == 'after-first'
  system('du', '-sh', '.build/native-manifest-cache/swiftpm')
end
