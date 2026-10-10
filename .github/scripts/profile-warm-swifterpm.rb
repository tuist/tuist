require 'digest'
require 'json'
require 'open3'

# Print process categories and cache counts only, never arguments or environment values.
def cache_state
  patterns = [
    '.build/swifterpm/**/*.envhash',
    File.expand_path('~/.cache/swifterpm/sources/**/.build/swifterpm/manifests/*.envhash')
  ]
  patterns.flat_map { |pattern| Dir.glob(pattern) }.sort.to_h do |path|
    [path, [Digest::SHA256.file(path).hexdigest, File.mtime(path).to_f]]
  end
end

def category(command)
  return 'swift package dump-package' if command.include?('dump-package')
  return 'swift package resolve' if command.match?(/(?:swift-package|swift package).*\bresolve\b/)
  return 'swift-frontend' if command.include?('swift-frontend')
  return 'clang' if command.match?(/\bclang(?:\s|$)/)
  return 'git' if command.match?(/(?:^|\/)git\s/)
  return 'tuist' if command.match?(/(?:^|\/)tuist\s/)
  'other child process'
end

def profile(label, arguments)
  before = cache_state
  lockfile = Digest::SHA256.file('Package.resolved').hexdigest
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  pid = Process.spawn('tuist', 'install', '--cache-path', File.expand_path('~/.cache/swifterpm'), *arguments)
  processes = {}
  status = nil
  loop do
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    output, ps_status = Open3.capture2('/bin/ps', '-axo', 'pid=,ppid=,command=')
    raise 'Process sampling failed' unless ps_status.success?
    rows = output.lines.map do |line|
      match = line.match(/^\s*(\d+)\s+(\d+)\s+(.*)$/)
      match && [match[1].to_i, match[2].to_i, match[3]]
    end.compact
    descendants = [pid]
    loop do
      added = rows.select { |child, parent, _| descendants.include?(parent) && !descendants.include?(child) }.map(&:first)
      break if added.empty?
      descendants.concat(added)
    end
    rows.each do |child, _, command|
      next unless descendants.include?(child)
      entry = (processes[child] ||= { category: category(command), first: now, last: now })
      entry[:last] = now
    end
    waited = Process.waitpid2(pid, Process::WNOHANG)
    if waited
      status = waited.last
      break
    end
    sleep 0.1
  end
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  after = cache_state
  result = {
    label: label, seconds: elapsed.round(3), success: status.success?,
    lockfile_unchanged: lockfile == Digest::SHA256.file('Package.resolved').hexdigest,
    environment_sidecars_before: before.length, environment_sidecars_after: after.length,
    changed_environment_sidecars: before.keys.count { |path| after[path] && before[path][0] != after[path][0] },
    rewritten_environment_sidecars: before.keys.count { |path| after[path] && before[path][1] != after[path][1] },
    sampled_processes: processes.values.group_by { |entry| entry[:category] }.transform_values do |entries|
      {
        count: entries.length,
        first_seen_s: entries.map { |entry| entry[:first] }.min.round(3),
        last_seen_s: entries.map { |entry| entry[:last] }.max.round(3),
        longest_observed_s: entries.map { |entry| entry[:last] - entry[:first] }.max.round(3)
      }
    end
  }
  puts "SWIFTERPM_PROFILE #{JSON.generate(result)}"
  File.open(ENV.fetch('GITHUB_STEP_SUMMARY'), 'a') { |file| file.puts("\n### #{label}\n\n```json\n#{JSON.pretty_generate(result)}\n```\n") }
  raise 'Install failed or changed Package.resolved' unless status.success? && result[:lockfile_unchanged]
end

%w[PHASE CACHE_HIT SWIFTERPM_CACHE_HIT WRITER_ID].each { |key| ENV.delete(key) }
profile('retained snapshot, forced versions', ['--force-resolved-versions'])
profile('same VM repeat, forced versions', ['--force-resolved-versions'])
profile('same VM, no forced validation', [])
profile('same VM repeat, no forced validation', [])
