#!/usr/bin/ruby
# Public CLI -> real Cargo and nextest with code coverage -> loopback receiver.
# Checks the request fields against OpenAPI and what they say about coverage, not Phoenix/database persistence.
require "fileutils"
require "json"
require "open3"
require "securerandom"
require "shellwords"
require "timeout"
require "tmpdir"
require "webrick"
require "yaml"
require "zlib"


def check(condition, message)
  raise message unless condition
end


def validate(value, schema, spec, path = "request")
  if schema["$ref"]
    schema = schema["$ref"].delete_prefix("#/").split("/").reduce(spec) do |node, key|
      node.fetch(key.gsub("~1", "/").gsub("~0", "~"))
    end
  end
  return if value.nil? && schema["nullable"]

  valid = case schema["type"]
          when "object" then value.is_a?(Hash)
          when "array" then value.is_a?(Array)
          when "string" then value.is_a?(String)
          when "integer" then value.is_a?(Integer)
          when "number" then value.is_a?(Numeric)
          when "boolean" then value == true || value == false
          when nil then true
          else raise "Unsupported schema type at #{path}"
          end
  check(valid, "Invalid #{schema['type']} at #{path}")
  check(schema["enum"].include?(value), "Invalid enum at #{path}") if schema["enum"]
  if value.is_a?(Hash)
    schema.fetch("required", []).each { |key| check(value.key?(key), "Missing #{path}.#{key}") }
    schema.fetch("properties", {}).each do |key, property|
      validate(value[key], property, spec, "#{path}.#{key}") if value.key?(key)
    end
  elsif value.is_a?(Array) && schema["items"]
    value.each_with_index { |item, index| validate(item, schema["items"], spec, "#{path}[#{index}]") }
  end
end


def command(arguments, directory, environment, root, label)
  stdout = File.join(root, "#{label}.stdout")
  stderr = File.join(root, "#{label}.stderr")
  pid = Process.spawn(environment, *arguments, chdir: directory, out: stdout, err: stderr,
                      unsetenv_others: true, pgroup: true)
  begin
    _, status = Timeout.timeout(300) { Process.wait2(pid) }
  rescue Timeout::Error
    Process.kill("KILL", -pid)
    Process.wait(pid)
    raise "Timed out: #{arguments.join(' ')}"
  end
  [status.exitstatus || 128 + status.termsig, File.binread(stdout), File.binread(stderr)]
end


def inflate(data)
  inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
  begin
    inflater.inflate(data) + inflater.finish
  ensure
    inflater.close
  end
end


# The lines a scope of `coverage_evidence` executed in a file, or nil when it executed none there.
def scope_lines(evidence, kind, mod, suite, name, path)
  index = evidence.fetch("paths").index(path)
  scope = evidence.fetch("scopes").find do |item|
    item["kind"] == kind && item["module"] == mod && item["suite"] == suite && item["name"] == name
  end
  return nil if index.nil? || scope.nil?

  position = scope.fetch("files").index(index)
  return nil if position.nil?

  scope.fetch("lines")[position].each_slice(2).flat_map { |first, last| (first..last).to_a }
end


fixture = File.dirname(File.realpath(__FILE__))
repository = File.expand_path("../../../..", fixture)
cli = File.realpath(ENV.fetch("TUIST_CLI_BINARY"))
spec = YAML.safe_load(File.read(File.join(repository, "cli/Sources/TuistServer/OpenAPI/server.yml")), aliases: true)
test_schema = nil
spec.fetch("paths").each_value do |methods|
  operation = methods.fetch("post", {})
  next unless operation["operationId"] == "createTest"

  test_schema = operation.fetch("requestBody").fetch("content").fetch("application/json").fetch("schema")
end
check(test_schema, "Missing the createTest request schema")
root = Dir.mktmpdir("tuist-cargo-coverage-e2e-")
puts "Artifacts: #{root}"
$stdout.sync = true
requests = []
uploads = {}
inline_threshold = 5_000_000
quarantine = { "muted" => [], "skipped" => [] }
plan_id = SecureRandom.uuid
assignments = []
token = "cargo-coverage-e2e-loopback-only"
prefix = "/api/projects/e2e/cargo"
server = WEBrick::HTTPServer.new(BindAddress: "127.0.0.1", Port: 0,
                                Logger: WEBrick::Log.new(File::NULL, WEBrick::Log::FATAL), AccessLog: [])
port = server.listeners.first.addr[1]
server.mount_proc("/") do |request, response|
  begin
    response["Content-Type"] = "application/json"
    if request.request_method == "PUT"
      check(request.path.start_with?("/coverage-blob/"), "Unexpected PUT #{request.path}")
      uploads[request.path.split("/").last] = request.body
      response.status = 200
      response.body = ""
    elsif request.request_method == "GET"
      case request.path
      when "/api/cache/endpoint"
        response.body = JSON.generate(endpoint: nil)
      when "/api/metadata/limits"
        response.status = 404
        response.body = JSON.generate(message: "Use legacy metadata limits")
      when "#{prefix}/tests/test-cases"
        state = request.query.fetch("state")
        page = Integer(request.query.fetch("page"))
        entries = quarantine.fetch(state)
        response.body = JSON.generate(test_cases: entries.slice((page - 1), 1) || [],
                                      pagination_metadata: { has_next_page: page < entries.length,
                                                             has_previous_page: page > 1, page_size: 1 })
      when "#{prefix}/tests/coverage/settings"
        response.body = JSON.generate(inline_threshold_bytes: inline_threshold)
      when "#{prefix}/tests/git-history/settings"
        response.body = JSON.generate(window_days: 30, window_commits: 100, deepen_budget_seconds: 5,
                                      upload_batch_size: 500, commit_file_limit: 100_000)
      else
        check(request.path.start_with?("#{prefix}/tests/shards/"), "Unexpected GET #{request.path}")
        index = Integer(request.path.split("/").last)
        response.body = JSON.generate(shard_plan_id: plan_id, modules: assignments.fetch(index), suites: {},
                                      download_urls: [])
      end
    else
      check(request.request_method == "POST", "Unexpected method")
      check(request["Authorization"] == "Bearer #{token}", "Wrong authorization header")
      data = request["Content-Encoding"] == "deflate" ? inflate(request.body) : request.body
      payload = data.to_s.empty? ? {} : JSON.parse(data)
      case request.path
      when "#{prefix}/tests/shards"
        modules = payload.fetch("modules")
        assignments = [modules.values_at(0, 2).compact, modules.values_at(1, 3).compact]
        response.body = JSON.generate(id: plan_id, reference: payload.fetch("reference"), shard_count: 2,
                                      shards: assignments.each_with_index.map { |mods, i| { index: i, test_targets: mods, estimated_duration_ms: 1 } })
      when "#{prefix}/tests/git-history/commits/missing", "#{prefix}/tests/git-history/listings/missing"
        requests << { "kind" => "#{request.path.split('/')[-2]}-missing", "payload" => payload }
        response.body = JSON.generate(missing: payload.fetch("shas"))
      when "#{prefix}/tests/git-history/commits", "#{prefix}/tests/git-history/listings"
        requests << { "kind" => request.path.split("/").last, "payload" => payload }
        response.status = 204
        response.body = ""
      when %r{\A#{prefix}/tests/coverage/commits/([0-9a-f]+)/complete\z}
        sha = Regexp.last_match(1)
        requests << { "kind" => "complete", "payload" => { "sha" => sha } }
        response.body = JSON.generate(git_commit_sha: sha, covered_lines: 9, executable_lines: 10, coverage: 90.0,
                                      measured_files_count: 3, unmeasured_files_count: 0, schemes: ["cargo test"],
                                      partial_schemes: [], partial: false, complete: true, completeness: "complete",
                                      test_run_ids: [], targets: [])
      when "#{prefix}/tests/coverage/uploads"
        key = SecureRandom.hex(8)
        requests << { "kind" => "coverage-upload", "payload" => payload }
        response.body = JSON.generate(storage_key: key, upload_url: "http://127.0.0.1:#{port}/coverage-blob/#{key}")
      when "#{prefix}/cargo/builds"
        response.status = 201
        response.body = JSON.generate(id: payload.fetch("id"))
      when "#{prefix}/tests"
        validate(payload, test_schema, spec)
        requests << { "kind" => "tests", "payload" => payload }
        cases = payload.fetch("test_modules").flat_map do |mod|
          mod.fetch("test_cases").map do |test|
            { id: SecureRandom.uuid, module_name: mod.fetch("name"),
              suite_name: test.fetch("test_suite_name", ""), name: test.fetch("name") }
          end
        end
        response.body = JSON.generate(type: "test", id: payload.fetch("id"), duration: payload.fetch("duration"),
                                      project_id: 1, url: "http://127.0.0.1:#{port}/tests/#{payload.fetch('id')}",
                                      test_case_runs: cases)
      else
        raise "Unexpected POST #{request.path}"
      end
    end
  rescue StandardError => error
    requests << { "error" => error.message, "path" => request.path }
    response.status = 400
    response.body = JSON.generate(message: error.message)
  end
end
thread = Thread.new { server.start }
begin
  environment = ENV.to_h.reject do |key, _|
    key.start_with?("TUIST_", "GITHUB_", "BUILDKITE_", "GITLAB_", "CARGO_", "RUST_TEST_", "NEXTEST_") ||
      ["CI", "RUSTC_WRAPPER", "RUSTC_WORKSPACE_WRAPPER", "RUSTFLAGS", "RUSTDOCFLAGS", "OUT_DIR", "LLVM_PROFILE_FILE"].include?(key)
  end
  cargo, cargo_status = Open3.capture2(environment, "rustup", "which", "cargo", unsetenv_others: true)
  check(cargo_status.success?, "Could not resolve Cargo")
  cargo = cargo.strip
  checkout = File.join(root, "checkout")
  FileUtils.mkdir_p(checkout)
  ["Cargo.toml", "src", "tests", ".gitignore"].each { |item| FileUtils.cp_r(File.join(fixture, item), checkout) }
  # Coverage is on through the project's configuration; TUIST_COVERAGE_UPLOAD=0 turns it off for one run.
  File.write(File.join(checkout, "tuist.toml"), "[test_insights.coverage]\nupload = true\n")
  git = lambda do |*arguments|
    output, status = Open3.capture2e(environment, "git", *arguments, chdir: checkout, unsetenv_others: true)
    check(status.success?, "git #{arguments.join(' ')}: #{output}")
    output.strip
  end
  remote = File.join(root, "remote.git")
  Open3.capture2e("git", "init", "--bare", "-q", remote)
  git.call("init", "-q", "-b", "main")
  git.call("-c", "user.name=E2E", "-c", "user.email=e2e@tuist.dev", "add", ".")
  git.call("-c", "user.name=E2E", "-c", "user.email=e2e@tuist.dev", "commit", "-q", "-m", "Fixture")
  git.call("remote", "add", "origin", remote)
  git.call("push", "-q", "-u", "origin", "main")
  head = git.call("rev-parse", "HEAD")
  environment.merge!("TUIST_PROJECT" => "e2e/cargo", "TUIST_URL" => "http://127.0.0.1:#{port}",
                     "TUIST_TOKEN" => token, "TUIST_DEBUG" => "1", "TUIST_CARGO_EXECUTABLE" => cargo,
                     "XDG_CACHE_HOME" => File.join(root, "cache"), "XDG_STATE_HOME" => File.join(root, "state"),
                     "XDG_CONFIG_HOME" => File.join(root, "config"))
  wrappers = File.join(root, "bin")
  FileUtils.mkdir_p(wrappers)
  File.write(File.join(wrappers, "cargo"), "#!/bin/sh\nexec #{Shellwords.escape(cli)} cargo \"$@\"\n")
  File.chmod(0700, File.join(wrappers, "cargo"))
  environment["PATH"] = wrappers + File::PATH_SEPARATOR + environment.fetch("PATH")
  summaries = []

  run = lambda do |name, arguments, code, env: {}, reports: 1, directory: checkout|
    start = requests.length
    result = command(["cargo", *arguments], directory, environment.merge(env), root, name)
    received = requests.drop(start)
    File.write(File.join(root, "#{name}.requests.json"), JSON.pretty_generate(received))
    check(result[0] == code, "#{name}: exit #{result[0]} != #{code}\n#{result[2]}")
    check(received.none? { |item| item.key?("error") }, "#{name}: #{received.select { |item| item.key?('error') }.inspect}")
    # Profiles of build scripts, listings and doctests stay out of the checkout, so its runs stay clean.
    left = Open3.capture2e(environment, "git", "status", "--porcelain", chdir: directory, unsetenv_others: true)[0].strip
    check(left.empty?, "#{name}: the run left files in the checkout: #{left}")
    tests = received.select { |item| item["kind"] == "tests" }.map { |item| item.fetch("payload") }
    check(tests.length == reports, "#{name}: #{tests.length} test reports != #{reports}\n#{result[2]}")
    summaries << { scenario: name, exit_code: code }
    puts "PASS: #{name}"
    [tests.first, received, result]
  end

  # The `coverage` block's files, sent inline or uploaded first.
  files_of = lambda do |report|
    coverage = report.fetch("coverage")
    check(coverage["tool"] == "llvm-cov" && coverage["tool_version"].start_with?("rustc ") && !coverage["platform"].empty?,
          "Wrong coverage tool: #{coverage.reject { |key, _| key == 'files' }}")
    files = if coverage.key?("storage_key")
              check(!coverage.key?("files"), "Uploaded coverage was also sent inline")
              inflate(uploads.fetch(coverage["storage_key"])).split("\n").map { |line| JSON.parse(line) }
            else
              coverage.fetch("files")
            end
    files.map { |file| [file.fetch("path"), file] }.to_h
  end
  covered = lambda do |file|
    file.fetch("line_numbers").zip(file.fetch("execution_counts")).select { |_, count| count.positive? }.map(&:first)
  end
  count_at = lambda do |file, line|
    index = file.fetch("line_numbers").index(line)
    index && file.fetch("execution_counts")[index]
  end
  targets_of = lambda do |report|
    report.fetch("coverage_evidence").fetch("scopes").select { |scope| scope["kind"] == "target" }.map { |scope| scope["module"] }.sort
  end
  case_names = lambda do |report|
    report.fetch("test_modules").reject { |mod| mod["name"].include?("::doctest/") }
          .flat_map { |mod| mod.fetch("test_cases").map { |test| test["name"] } }.sort
  end
  library = "cov-fixture"
  api = "cov-fixture::api"
  tool = "cov-fixture::bin/tool"

  # What every run that measured the whole suite says: the files, their counts and blobs, its functions.
  check_measured = lambda do |name, report|
    check(report["build_system"] == "cargo", "#{name}: wrong build system")
    check(report["coverage_enabled"] == true, "#{name}: coverage not enabled")
    check(report["coverage"]["partial"] == false, "#{name}: a full run was partial")
    check(!report.key?("only_test_identifiers") && !report.key?("skip_test_identifiers"), "#{name}: invented a selection")
    check(report["git_commit_sha"] == head && report["git_dirty"] == false, "#{name}: wrong commit or a dirty checkout")
    files = files_of.call(report)
    check((["src/lib.rs", "src/shapes.rs", "src/bin/tool.rs", "tests/api.rs", "tests/common/mod.rs"] - files.keys).empty?,
          "#{name}: missing files #{files.keys}")
    check(files.keys.none? { |path| path.start_with?("/") || path.include?("rustc") }, "#{name}: files outside the repository")
    files.each do |path, file|
      check(file["targets"] == [library], "#{name}: #{path} has targets #{file['targets']}")
      test_code = path.start_with?("tests/")
      check(file["is_test"] == test_code, "#{name}: #{path} is_test")
      check(file["line_numbers"].empty? == test_code, "#{name}: #{path} lines")
      check(file["git_blob_id"] == git.call("rev-parse", "HEAD:#{path}"), "#{name}: #{path} has the wrong blob")
    end
    lib = files.fetch("src/lib.rs")
    # `classify` ran for a negative number and zero, never a positive one; `add` ran in the unit test and the tool.
    check(count_at.call(lib, 13).to_i.positive? && count_at.call(lib, 15).to_i.positive? && count_at.call(lib, 17) == 0,
          "#{name}: wrong classify counts")
    functions = lib.fetch("functions").map { |function| function["name"] }
    check(functions.count("cov_fixture::apply") == 1 && functions.include?("cov_fixture::add"),
          "#{name}: wrong functions #{functions}")
    check(files.fetch("src/shapes.rs").fetch("functions").map { |function| function["name"] }.include?("<cov_fixture::shapes::Square>::grow"),
          "#{name}: missing a method")
    files
  end

  # Coverage off: the run says so, and sends neither coverage nor Git history.
  off, received, = run.call("coverage-off", ["test", "--offline"], 0, env: { "TUIST_COVERAGE_UPLOAD" => "0" })
  check(off["coverage_enabled"] == false, "coverage-off: coverage_enabled is not false")
  check(%w[coverage coverage_evidence only_test_identifiers skip_test_identifiers].none? { |key| off.key?(key) },
        "coverage-off: sent coverage")
  check(received.none? { |item| item["kind"] == "listings" }, "coverage-off: uploaded a listing")

  # A full `cargo test`: each binary's tests share its process, so each binary gets target evidence and its tests
  # are reported as overlapping.
  full, received, = run.call("cargo-test-full", ["test", "--offline"], 0)
  full_files = check_measured.call("cargo-test-full", full)
  evidence = full.fetch("coverage_evidence")
  check(evidence["status"] == "collected", "cargo-test-full: evidence #{evidence['status']}")
  check(evidence["scopes"].map { |scope| scope["kind"] }.uniq == ["target"], "cargo-test-full: test scopes from shared processes")
  check(targets_of.call(full) == [library, api, tool].sort, "cargo-test-full: targets #{targets_of.call(full)}")
  check(scope_lines(evidence, "target", api, "", "", "src/shapes.rs").include?(9), "cargo-test-full: the integration tests grow a square")
  check(!scope_lines(evidence, "target", library, "", "", "src/shapes.rs").include?(9), "cargo-test-full: the unit tests grew a square")
  check(scope_lines(evidence, "target", tool, "", "", "src/shapes.rs").nil?, "cargo-test-full: the tool touched shapes")
  check(evidence.fetch("overlapped_tests").map { |test| test["name"] }.sort == case_names.call(full),
        "cargo-test-full: overlapped tests")
  listings = received.select { |item| item["kind"] == "listings" }
  check(listings.length == 1 && listings[0]["payload"]["sha"] == head, "cargo-test-full: the commit's listing was not uploaded")
  check(received.any? { |item| item["kind"] == "commits" }, "cargo-test-full: no Git history was uploaded")
  full_covered = full_files.map { |path, file| [path, covered.call(file)] }.to_h

  # A report over the inline threshold is uploaded first, as raw DEFLATE of one file per line.
  inline_threshold = 1
  uploaded, received, = run.call("cargo-test-uploaded", ["test", "--offline"], 0)
  inline_threshold = 5_000_000
  check(uploaded["coverage"].key?("storage_key"), "cargo-test-uploaded: coverage was not uploaded")
  check(received.any? { |item| item["kind"] == "coverage-upload" && item["payload"]["test_run_id"] == uploaded["id"] },
        "cargo-test-uploaded: the upload names another run")
  check(files_of.call(uploaded).map { |path, file| [path, covered.call(file)] }.to_h == full_covered,
        "cargo-test-uploaded: the uploaded coverage differs from the inline one")

  # The caller's selection narrows the run: it names the tests it ran and is partial.
  narrowed, = run.call("cargo-test-narrowed", ["test", "--offline", "--test", "api"], 0)
  check(narrowed["coverage"]["partial"] == true, "cargo-test-narrowed: not partial")
  check(narrowed["only_test_identifiers"].sort == ["#{api}//applies", "#{api}//grows"], "cargo-test-narrowed: #{narrowed['only_test_identifiers']}")
  check(targets_of.call(narrowed) == [api], "cargo-test-narrowed: targets")
  skipped, = run.call("cargo-test-skip", ["test", "--offline", "--", "--skip", "grows"], 0)
  check(skipped["coverage"]["partial"] == true, "cargo-test-skip: not partial")
  check(!skipped["only_test_identifiers"].include?("#{api}//grows") && skipped["only_test_identifiers"].include?("#{api}//applies"),
        "cargo-test-skip: #{skipped['only_test_identifiers']}")

  # Fail-fast stops at the first failing binary: the run is partial, though its caller selected nothing.
  failed, = run.call("cargo-test-fail-fast", ["test", "--offline"], 101, env: { "TUIST_FIXTURE_FAIL" => "1" })
  check(failed["coverage"]["partial"] == true && !failed.key?("only_test_identifiers"), "cargo-test-fail-fast: partial")
  check(targets_of.call(failed) == [library], "cargo-test-fail-fast: targets #{targets_of.call(failed)}")
  unstopped, = run.call("cargo-test-no-fail-fast", ["test", "--offline", "--no-fail-fast"], 101, env: { "TUIST_FIXTURE_FAIL" => "1" })
  check(unstopped["coverage"]["partial"] == false && targets_of.call(unstopped) == [library, api, tool].sort,
        "cargo-test-no-fail-fast: every binary ran")

  # A quarantined test is left out on purpose: the run is not partial and names nothing.
  test_case = lambda do |mod, suite, name, state|
    { id: SecureRandom.uuid, name: name, module: { id: SecureRandom.uuid, name: mod },
      suite: { id: SecureRandom.uuid, name: suite }, avg_duration: 0, is_flaky: true,
      is_quarantined: true, state: state, url: "http://127.0.0.1:#{port}/case" }
  end
  quarantine["skipped"] = [test_case.call(api, "", "grows", "skipped")]
  quarantined, = run.call("cargo-test-quarantine", ["test", "--offline"], 0)
  quarantine["skipped"] = []
  check(quarantined["coverage"]["partial"] == false, "cargo-test-quarantine: partial")
  check(!quarantined.key?("only_test_identifiers") && !quarantined.key?("skip_test_identifiers"), "cargo-test-quarantine: named the skip")
  grows = quarantined.fetch("test_modules").find { |mod| mod["name"] == api }.fetch("test_cases").find { |test| test["name"] == "grows" }
  check(grows["status"] == "skipped" && grows["is_quarantined"], "cargo-test-quarantine: grows was not a quarantined skip")
  check(count_at.call(files_of.call(quarantined).fetch("src/shapes.rs"), 9) == 0, "cargo-test-quarantine: grows ran")
  check(!scope_lines(quarantined["coverage_evidence"], "target", api, "", "", "src/shapes.rs").to_a.include?(9),
        "cargo-test-quarantine: evidence holds the skipped test")

  # Shards: each runs its share without being partial, and together they measure what the full run did.
  run.call("cargo-test-shard-plan", ["test", "--offline", "--no-run", "--shard-total", "2"], 0, reports: 0,
           env: { "TUIST_SHARD_REFERENCE" => "coverage-e2e" })
  check(assignments.flatten.sort == [library, api, tool, "#{library}::doctest/cov_fixture"].sort, "Wrong plan #{assignments}")
  shard_covered = Hash.new { |hash, key| hash[key] = [] }
  assignments.each_with_index do |mods, index|
    shard, = run.call("cargo-test-shard-#{index}", ["test", "--offline"], 0,
                      env: { "TUIST_SHARD_PLAN_ID" => plan_id, "TUIST_SHARD_INDEX" => index.to_s })
    check(shard["shard_plan_id"] == plan_id && shard["shard_index"] == index, "shard #{index}: attribution")
    check(shard["coverage"]["partial"] == false && !shard.key?("only_test_identifiers"), "shard #{index}: partial or narrowed")
    check(targets_of.call(shard) == (mods - ["#{library}::doctest/cov_fixture"]).sort, "shard #{index}: targets #{targets_of.call(shard)}")
    files_of.call(shard).each { |path, file| shard_covered[path] |= covered.call(file) }
  end
  check(shard_covered.reject { |_, lines| lines.empty? }.transform_values(&:sort) == full_covered.reject { |_, lines| lines.empty? },
        "The shards together measured something else than the full run")

  # Once every test job of a commit has finished, CI marks its coverage complete: the checkout's commit by default.
  _, received, completed = run.call("coverage-complete", ["coverage-complete"], 0, reports: 0)
  check(received.map { |item| item["kind"] } == ["complete"] && received[0]["payload"]["sha"] == head,
        "coverage-complete: #{received.inspect}")
  check(completed[1].include?("Coverage of commit #{head[0, 7]} is complete: 90.0%."), "coverage-complete: #{completed[1]}")
  _, received, = run.call("coverage-complete-commit", ["coverage-complete", "--commit", "0123abc"], 0, reports: 0)
  check(received[0]["payload"]["sha"] == "0123abc", "coverage-complete-commit: #{received.inspect}")

  nextest, nextest_status = Open3.capture2e(environment, cargo, "nextest", "--version", unsetenv_others: true)
  if nextest_status.success?
    puts "Using #{nextest.lines.first.strip}"
    # Nextest runs each test in its own process, so each test gets evidence of its own.
    full_nextest, = run.call("nextest-full", ["nextest", "run", "--offline"], 0)
    check_measured.call("nextest-full", full_nextest)
    evidence = full_nextest.fetch("coverage_evidence")
    check(!evidence.key?("overlapped_tests"), "nextest-full: tests overlapped")
    check(targets_of.call(full_nextest) == [library, api, tool].sort, "nextest-full: targets")
    tests = evidence["scopes"].select { |scope| scope["kind"] == "test" }.map { |scope| [scope["module"], scope["suite"], scope["name"]] }
    check(tests.sort == full_nextest.fetch("test_modules").flat_map { |mod| mod["test_cases"].map { |test| [mod["name"], test.fetch("test_suite_name", ""), test["name"]] } }.sort,
          "nextest-full: tests with evidence #{tests}")
    check(scope_lines(evidence, "test", api, "", "grows", "src/shapes.rs").include?(9), "nextest-full: grows")
    check(scope_lines(evidence, "test", api, "", "applies", "src/shapes.rs").nil?, "nextest-full: applies touched shapes")
    check(scope_lines(evidence, "test", api, "", "applies", "src/lib.rs").include?(22), "nextest-full: applies")
    negative = scope_lines(evidence, "test", library, "tests", "classifies_negative", "src/lib.rs")
    check(negative.include?(13) && !negative.include?(15), "nextest-full: classifies_negative")
    nextest_covered = files_of.call(full_nextest).map { |path, file| [path, covered.call(file)] }.to_h

    filtered, = run.call("nextest-narrowed", ["nextest", "run", "--offline", "-E", "test(grows)"], 0)
    check(filtered["coverage"]["partial"] == true && filtered["only_test_identifiers"] == ["#{api}//grows"],
          "nextest-narrowed: #{filtered['only_test_identifiers']}")
    check(filtered["coverage_evidence"]["scopes"].select { |scope| scope["kind"] == "test" }.map { |scope| scope["name"] } == ["grows"],
          "nextest-narrowed: evidence of tests that did not run")

    # A shard runs from the archive its plan built, extracted where its binaries outlive the run.
    archive = File.join(root, "tests.tar.zst")
    run.call("nextest-shard-plan", ["test-build", "--offline", "--shard-total", "2"], 0, reports: 0,
             env: { "TUIST_SHARD_REFERENCE" => "coverage-e2e-nextest", "TUIST_TEST_SHARD_ARCHIVE_PATH" => archive })
    check(assignments.flatten.sort == [library, api, tool].sort, "Wrong nextest plan #{assignments}")
    shard_covered = Hash.new { |hash, key| hash[key] = [] }
    assignments.each_with_index do |mods, index|
      # Each shard runs in a clone of its own, as a CI worker does: the archive's binaries name the planning
      # checkout's sources, which coverage maps to the worker's.
      worker = File.join(root, "worker-#{index}")
      Open3.capture2e(environment, "git", "clone", "-q", remote, worker, unsetenv_others: true)
      Open3.capture2e(environment, "git", "remote", "set-url", "origin", git.call("remote", "get-url", "origin"),
                      chdir: worker, unsetenv_others: true)
      # An archive run builds nothing, and nextest rejects Cargo's network options beside `--archive-file`.
      shard, = run.call("nextest-shard-#{index}", ["nextest", "run"], 0, directory: worker,
                        env: { "TUIST_SHARD_PLAN_ID" => plan_id, "TUIST_SHARD_INDEX" => index.to_s,
                               "TUIST_TEST_SHARD_ARCHIVE_PATH" => archive })
      check(shard["shard_plan_id"] == plan_id && shard["coverage"]["partial"] == false, "nextest shard #{index}: partial")
      check(targets_of.call(shard) == mods.sort, "nextest shard #{index}: targets #{targets_of.call(shard)}")
      check(shard["coverage_evidence"]["scopes"].any? { |scope| scope["kind"] == "test" }, "nextest shard #{index}: no test evidence")
      files_of.call(shard).each { |path, file| shard_covered[path] |= covered.call(file) }
    end
    check(shard_covered.reject { |_, lines| lines.empty? }.transform_values(&:sort) == nextest_covered.reject { |_, lines| lines.empty? },
          "The nextest shards together measured something else than the full run")
  else
    puts "SKIP: nextest scenarios (cargo-nextest is not installed)"
  end
  File.write(File.join(root, "summary.json"), JSON.pretty_generate(summaries))
  puts "PASS: all #{summaries.length} public-CLI coverage scenarios"
  puts "Not exercised: Phoenix authorization, database persistence, or dashboard rendering."
ensure
  server.shutdown
  thread.join
end
