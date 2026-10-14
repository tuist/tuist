require 'digest'
require 'find'
require 'json'

def snapshot
  sources = {}
  cache = {}
  links = {}
  roots = {
    'workspace' => File.realpath('.build'),
    'sources' => File.join(ENV.fetch('HOME'), '.cache/swifterpm/sources')
  }
  roots.each do |kind, root|
    Find.find(root) do |path|
      relative = path.delete_prefix(root + '/')
      name = "#{kind}/#{relative}"
      if File.symlink?(path)
        links[name] = File.readlink(path)
      elsif File.file?(path)
        if relative.include?('swifterpm/') && (path.end_with?('.json') || path.end_with?('.envhash'))
          cache[name] = [Digest::SHA256.file(path).hexdigest, File.mtime(path).to_f]
        elsif kind == 'sources' && !relative.include?('/.build/') && !relative.include?('/.git/')
          sources[name] = Digest::SHA256.file(path).hexdigest
        end
      end
    end
  end
  excluded = File.read('Tuist.swift').scan(/"([A-Z][A-Z0-9_]+)"/).flatten + %w[
    GITHUB_ACTION GITHUB_ARTIFACTS GITHUB_ARTIFACTS_LIST GITHUB_ENV GITHUB_OUTPUT
    GITHUB_PATH GITHUB_RUN_ATTEMPT GITHUB_RUN_ID GITHUB_RUN_NUMBER GITHUB_STEP_SUMMARY
  ]
  environment = ENV.to_h.reject { |key, _| excluded.include?(key) }.transform_values { |value| Digest::SHA256.hexdigest(value) }
  manifests = Dir.glob(['Package*.swift', 'server/native/{xcactivitylog_nif,xcresult_nif}/Package*.swift'])
  {
    'sources' => sources, 'cache' => cache, 'links' => links,
    'environment' => environment,
    'manifests' => manifests.to_h { |manifest| [manifest, Digest::SHA256.file(manifest).hexdigest] },
    'manifest_mtimes' => manifests.to_h { |manifest| [manifest, File.mtime(manifest).to_f] },
    'lockfile' => Digest::SHA256.file('Package.resolved').hexdigest,
    'binary' => Digest::SHA256.file(File.join(ENV.fetch('HOME'), '.cache/swifterpm-content-validation/products/tuist')).hexdigest
  }
end

mode, path = ARGV
current = snapshot
if mode == 'snapshot'
  File.write(path, JSON.generate(current))
  puts "Recorded #{current['sources'].length} source files, #{current['cache'].length} cache files, #{current['links'].length} links"
else
  previous = JSON.parse(File.read(path))
  %w[sources lockfile binary manifests environment].each do |field|
    if field == 'environment' && previous[field] != current[field]
      changed = (previous[field].keys | current[field].keys).select { |key| previous[field][key] != current[field][key] }
      warn "Changed manifest environment keys: #{changed.join(', ')}"
    end
    abort "Integrity mismatch: #{field}" unless previous[field] == current[field]
  end
  if mode == 'verify'
    File.write('.validation-evidence/restored.json', JSON.generate(current))
    %w[cache links].each do |field|
      if previous[field] != current[field]
        changed = (previous[field].keys | current[field].keys).select { |name| previous[field][name] != current[field][name] }
        warn JSON.pretty_generate(field: field, changed: changed.first(10).to_h { |name| [name, {before: previous[field][name], after: current[field][name]}] })
      end
      abort "Retained snapshot mismatch: #{field}" unless previous[field] == current[field]
    end
    puts 'Verified all retained source, cache, symlink, binary and lockfile records on this fresh runner'
    changed = previous['manifest_mtimes'].keys.select { |key| previous['manifest_mtimes'][key] != current['manifest_mtimes'][key] }
    puts "Fresh checkout manifest mtimes changed: #{changed.join(', ')}"
  else
    changed = (previous['cache'].keys | current['cache'].keys).select { |name| previous['cache'][name] != current['cache'][name] }
    puts JSON.pretty_generate(changed_cache_files: changed, source_and_lockfile_integrity: 'unchanged')
  end
end
