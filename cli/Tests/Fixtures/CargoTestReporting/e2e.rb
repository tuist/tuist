#!/usr/bin/ruby
# Public CLI -> stable Cargo/rustdoc -> loopback upload receiver.
# Checks the request fields against OpenAPI, not Phoenix/database persistence.
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
  reader, writer = label == "slow-consumer-failure" ? IO.pipe : [nil, nil]
  pid = Process.spawn(environment, *arguments, chdir: directory, out: writer || stdout, err: stderr,
                      unsetenv_others: true, pgroup: true)
  writer&.close
  drainer = if reader
              Thread.new do
                sleep 3
                File.binwrite(stdout, reader.read)
                reader.close
              end
            end
  begin
    _, status = Timeout.timeout(120) { Process.wait2(pid) }
  rescue Timeout::Error
    Process.kill("KILL", -pid)
    Process.wait(pid)
    raise "Timed out: #{arguments.join(' ')}"
  ensure
    drainer&.join
  end
  [status.exitstatus || 128 + status.termsig, File.binread(stdout), File.binread(stderr)]
end

fixture = File.dirname(File.realpath(__FILE__))
repository = File.expand_path("../../../..", fixture)
cli = File.realpath(ENV.fetch("TUIST_CLI_BINARY"))
spec = YAML.safe_load(File.read(File.join(repository, "cli/Sources/TuistServer/OpenAPI/server.yml")), aliases: true)
schemas = {}
spec.fetch("paths").each_value do |methods|
  operation = methods.fetch("post", {})
  kind = { "createTest" => "tests", "createCargoBuild" => "builds" }[operation["operationId"]]
  schemas[kind] = operation.fetch("requestBody").fetch("content").fetch("application/json").fetch("schema") if kind
end
check(schemas.keys.sort == ["builds", "tests"], "Missing request schemas")
root = Dir.mktmpdir("tuist-cargo-test-e2e-")
puts "Artifacts: #{root}"
$stdout.sync = true
requests = []
rejection = false
quarantine = { "muted" => [], "skipped" => [] }
quarantine_requests = []
quarantine_rejection = false
plan_id = SecureRandom.uuid
assignments = []
shard_override = nil
token = "cargo-e2e-loopback-only"
server = WEBrick::HTTPServer.new(BindAddress: "127.0.0.1", Port: 0,
                                Logger: WEBrick::Log.new(File::NULL, WEBrick::Log::FATAL), AccessLog: [])
port = server.listeners.first.addr[1]
server.mount_proc("/") do |request, response|
  begin
    response["Content-Type"] = "application/json"
    if request.request_method == "GET"
      if request.path == "/api/cache/endpoint"
        response.body = JSON.generate(endpoint: nil)
      elsif request.path == "/api/metadata/limits"
        response.status = 404
        response.body = JSON.generate(message: "Use legacy metadata limits")
      elsif request.path == "/api/projects/e2e/cargo/tests/test-cases"
        check(request["Authorization"] == "Bearer #{token}", "Wrong quarantine authorization")
        state = request.query.fetch("state")
        page = Integer(request.query.fetch("page"))
        quarantine_requests << [state, page]
        entries = quarantine.fetch(state)
        response.status = 400 if quarantine_rejection
        response.body = JSON.generate(test_cases: entries.slice((page - 1), 1) || [],
                                      pagination_metadata: { has_next_page: page < entries.length,
                                                             has_previous_page: page > 1, page_size: 1 })
      elsif request.path.start_with?("/api/projects/e2e/cargo/tests/shards/")
        check(request["Authorization"] == "Bearer #{token}", "Wrong shard authorization")
        index = Integer(request.path.split("/").last)
        if index >= assignments.length
          response.status = 404
          response.body = JSON.generate(message: "Missing shard")
        else
          response.body = JSON.generate(shard_override || { shard_plan_id: plan_id, modules: assignments[index],
                                                           suites: {}, download_urls: [] })
        end
      else
        raise "Unexpected GET #{request.path}"
      end
    else
      check(request.request_method == "POST", "Unexpected method")
      check(request["Authorization"] == "Bearer #{token}", "Wrong authorization header")
      data = request.body
      if request["Content-Encoding"] == "deflate"
        inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
        begin
          data = inflater.inflate(data) + inflater.finish
        ensure
          inflater.close
        end
      end
      payload = JSON.parse(data)
      if request.path == "/api/projects/e2e/cargo/tests/shards"
        validate(payload, spec.fetch("components").fetch("schemas").fetch("CreateShardPlanParams"), spec)
        check(payload.fetch("granularity") == "module", "Not a module plan")
        modules = payload.fetch("modules")
        assignments = [modules.values_at(0, 2).compact, modules.values_at(1, 3).compact]
        requests << { "kind" => "plan", "payload" => payload }
        response.body = JSON.generate(id: plan_id, reference: payload.fetch("reference"), shard_count: assignments.length,
                                      shards: assignments.each_with_index.map { |mods, i| { index: i, test_targets: mods, estimated_duration_ms: 1 } })
        next
      end
      kind = { "/api/projects/e2e/cargo/tests" => "tests",
               "/api/projects/e2e/cargo/cargo/builds" => "builds" }.fetch(request.path)
      validate(payload, schemas.fetch(kind), spec)
      requests << { "kind" => kind, "payload" => payload }
      if rejection
        response.status = 400
        response.body = JSON.generate(message: "Intentional E2E rejection")
      elsif kind == "builds"
        response.status = 201
        response.body = JSON.generate(id: payload.fetch("id"))
      else
        cases = payload.fetch("test_modules").flat_map do |mod|
          mod.fetch("test_cases").map do |test|
            { id: SecureRandom.uuid, module_name: mod.fetch("name"),
              suite_name: test.fetch("test_suite_name", ""), name: test.fetch("name") }
          end
        end
        response.body = JSON.generate(type: "test", id: payload.fetch("id"), duration: payload.fetch("duration"),
                                      project_id: 1, url: "http://127.0.0.1:#{port}/tests/#{payload.fetch('id')}",
                                      test_case_runs: cases)
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
    key.start_with?("TUIST_", "GITHUB_", "BUILDKITE_", "GITLAB_", "CARGO_", "RUST_TEST_") ||
      ["CI", "RUSTC_WRAPPER", "RUSTC_WORKSPACE_WRAPPER", "RUSTFLAGS", "OUT_DIR"].include?(key)
  end
  cargo, cargo_status = Open3.capture2(environment, "rustup", "which", "cargo", unsetenv_others: true)
  check(cargo_status.success?, "Could not resolve Cargo")
  cargo = cargo.strip
  toolchain, toolchain_status = Open3.capture2(environment, "rustup", "show", "active-toolchain", unsetenv_others: true)
  check(toolchain_status.success?, "Could not resolve the Rust toolchain")
  toolchain = toolchain.split(" (").first.strip
  check(!toolchain.include?("nightly"), "Use stable Rust")
  checkout = File.join(root, "checkout")
  FileUtils.mkdir_p(checkout)
  ["Cargo.toml", "src", "tests"].each { |item| FileUtils.cp_r(File.join(fixture, item), checkout) }
  environment.merge!("TUIST_PROJECT" => "e2e/cargo", "TUIST_URL" => "http://127.0.0.1:#{port}",
                     "TUIST_TOKEN" => token, "TUIST_DEBUG" => "1", "TUIST_CARGO_EXECUTABLE" => cargo,
                     "RUSTUP_TOOLCHAIN" => toolchain, "XDG_CACHE_HOME" => File.join(root, "cache"),
                     "XDG_STATE_HOME" => File.join(root, "state"), "XDG_CONFIG_HOME" => File.join(root, "config"))
  wrappers = File.join(root, "bin")
  FileUtils.mkdir_p(wrappers)
  File.write(File.join(wrappers, "cargo"), "#!/bin/sh\nexec #{Shellwords.escape(cli)} cargo \"$@\"\n")
  File.write(File.join(wrappers, "cargo-nextest"), "#!/bin/sh\necho 'nextest must not be used' >&2\nexit 97\n")
  Dir.glob(File.join(wrappers, "*")).each { |file| File.chmod(0700, file) }
  environment["PATH"] = wrappers + File::PATH_SEPARATOR + environment.fetch("PATH")
  baseline = command([cargo, "test", "--workspace", "--offline"], checkout, environment, root, "native")
  check(baseline[0].zero? && requests.empty?, "Native baseline failed or uploaded reports")
  FileUtils.rm_rf(File.join(checkout, "target"))
  summaries = []
  run = lambda do |name, arguments, code, count, fail: false, reject: false, env: {}, build: "success", shard: nil, failures: nil|
    rejection = reject
    current = environment.merge(env)
    current["TUIST_FIXTURE_FAIL"] = "1" if fail
    start = requests.length
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = command(["cargo", *arguments], checkout, current, root, name)
    elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
    received = requests.drop(start)
    File.write(File.join(root, "#{name}.requests.json"), JSON.pretty_generate(received))
    check(result[0] == code, "#{name}: exit #{result[0]} != #{code}\n#{result[2]}")
    check(received.none? { |item| item.key?("error") }, "#{name}: #{received.inspect}")
    reports = received.select { |item| item["kind"] == "tests" }.map { |item| item.fetch("payload") }
    check(reports.length == (count.nil? ? 0 : 1), "#{name}: unexpected test uploads\n#{result[2]}")
    builds = received.select { |item| item["kind"] == "builds" }.map { |item| item.fetch("payload") }
    if build.nil?
      check(builds.empty?, "#{name}: expected no unmeasured build report")
    else
      check(builds.length == 1 && builds[0]["status"] == build, "#{name}: wrong build report")
      check(builds[0].fetch("compilations").all? { |row| row.fetch("start_offset_ms") + row.fetch("duration_ms") <= builds[0].fetch("duration_ms") + 1 },
            "#{name}: compiler rows extend beyond build duration")
      if name == "nested-compile-failure-test"
        check(builds[0].fetch("compilations").none? { |row| row["name"] == "nested_failure" }, "Nested compiler leaked into outer build")
      end
    end
    if name == "slow-test-failure"
      check(builds[0].fetch("duration_ms") + 2000 < elapsed_ms, "Build duration includes test execution")
    end
    check(!builds[0].fetch("compilations").empty?, "Cold run did not observe rustc") if name == "success"
    unless count.nil?
      report = reports.first
      check(report["build_system"] == "cargo" && report["scheme"] == "cargo test", "Wrong test run identity")
      check(report["status"] == (code.zero? ? "success" : "failure"), "Wrong test run status")
      cases = report.fetch("test_modules").flat_map { |mod| mod.fetch("test_cases") }
      check(cases.length == count, "#{name}: #{cases.length} cases != #{count}")
      check(cases.count { |test| test["status"] == "failure" } == (failures || (fail ? 1 : 0)), "Wrong failed count")
      check(cases.all? { |test| test["duration"].zero? }, "Invented per-test timing")
      check(cases.none? { |test| test["name"].end_with?(" - compile") }, "Unnormalized no_run doctest")
      if name == "selected-member"
        check(report.fetch("test_modules").all? { |mod| mod.fetch("name").start_with?("reporting-member") }, "Misattributed member tests")
        check(report.fetch("test_modules").any? { |mod| mod.fetch("name") == "reporting-member::api" }, "Missing member integration identity")
      end
      check(!report.key?("enumerated_tests"), "Invented inventory")
      if shard.nil?
        check(!report.key?("shard_plan_id"), "Invented shard")
      else
        check(report["shard_plan_id"] == plan_id && report["shard_index"] == shard, "Wrong shard attribution")
      end
      if count == 10
        modules = report.fetch("test_modules").map { |mod| [mod.fetch("name"), mod] }.to_h
        check(modules.keys.sort == ["tuist-cargo-reporting-fixture", "tuist-cargo-reporting-fixture::api",
                                    "tuist-cargo-reporting-fixture::doc",
                                    "tuist-cargo-reporting-fixture::doctest/tuist_cargo_reporting_fixture"], "Wrong modules")
        docs = modules.fetch("tuist-cargo-reporting-fixture::doctest/tuist_cargo_reporting_fixture").fetch("test_cases")
        check(docs.length == 5 && docs.count { |test| test["status"] == "skipped" } == (name == "skip-quarantine" ? 2 : 1), "Wrong doctests")
      end
      if reject
        check(result[2].include?("Tuist rejected the Cargo test report"), "Rejection was not diagnosed")
      else
        check(!result[2].include?("Tuist Cargo reporting:"), "Unexpected reporting failure: #{result[2]}")
      end
    end
    summaries << { scenario: name, exit_code: code, reported_cases: count }
    puts "PASS: #{name}: exit=#{code}, reported cases=#{count.inspect}"
    result
  end
  observed = run.call("success", ["test", "--workspace", "--offline"], 0, 10)
  test_lines = ->(output) { output.lines.map(&:chomp).select { |line| line.start_with?("test ") && !line.start_with?("test result:") }.sort }
  check(test_lines.call(observed[1]) == test_lines.call(baseline[1]), "The wrapper changed Cargo test output")
  check(observed[1].include?("should panic") && observed[1].include?("compile fail"), "Missing doctest attributes")
  check(!observed[2].include?("failed to connect to jobserver"), "Compiler observation lost the jobserver")
  run.call("doctests", ["test", "--offline", "--doc"], 0, 5)
  run.call("filtered", ["test", "--offline", "tests::passes"], 0, 1)
  run.call("fail-fast", ["test", "--offline"], 101, 3, fail: true)
  run.call("no-fail-fast", ["test", "--offline", "--no-fail-fast"], 101, 10, fail: true)
  slow = run.call("slow-consumer-failure", ["test", "--offline"], 101, 3, fail: true,
                  env: { "TUIST_FIXTURE_NOISY" => "1" })
  check(slow[1].lines.count { |line| line.start_with?("captured line ") } == 1500, "Lost captured failure output")
  check(slow[1].include?("test result: FAILED."), "Lost the failure summary")
  run.call("no-run", ["test", "--offline", "--no-run"], 0, nil)
  run.call("list", ["test", "--offline", "--", "--list"], 0, nil, build: nil)
  run.call("quiet", ["test", "--offline", "--quiet"], 0, nil, build: nil)
  run.call("verbose", ["test", "--offline", "--verbose"], 0, nil, build: nil)
  run.call("very-verbose", ["test", "--offline", "-vv"], 0, nil, build: nil)
  run.call("message-format", ["test", "--offline", "--message-format=json"], 0, nil, build: nil)
  run.call("environment-verbose", ["test", "--offline"], 0, nil, env: { "CARGO_TERM_VERBOSE" => "true" }, build: nil)
  run.call("environment-quiet", ["test", "--offline"], 0, nil, env: { "CARGO_TERM_QUIET" => "true" }, build: nil)
  run.call("colored", ["test", "--offline", "--color=always"], 0, 10)
  run.call("plain-build", ["build", "--offline"], 0, nil)
  no_tests = File.join(root, "no-tests")
  FileUtils.mkdir_p(File.join(no_tests, "src"))
  File.write(File.join(no_tests, "Cargo.toml"), "[package]\nname = \"no-tests\"\nversion = \"0.1.0\"\nedition = \"2024\"\n[lib]\ntest = false\ndoctest = false\n")
  File.write(File.join(no_tests, "src", "lib.rs"), "pub fn value() {}\n")
  run.call("no-runnable-tests", ["test", "--offline", "--manifest-path", "../no-tests/Cargo.toml"], 0, nil)
  source = File.join(checkout, "src", "lib.rs")
  original_source = File.read(source)
  begin
    File.write(source, original_source + "\n#[test]\nfn slow_phase_probe() { std::thread::sleep(std::time::Duration::from_secs(3)); }\n")
    run.call("slow-test-failure", ["test", "--offline", "--lib"], 101, 4, fail: true)
    File.write(source, original_source + "\ncompile_error!(\"fixture compilation failure\");\n")
    run.call("compile-failure", ["test", "--offline"], 101, nil, build: "failure")
  ensure
    File.write(source, original_source)
  end
  build_script = File.join(checkout, "build.rs")
  build_nested = File.join(root, "build-script-nested")
  FileUtils.mkdir_p(File.join(build_nested, "src"))
  File.write(File.join(build_nested, "Cargo.toml"), "[package]\nname = \"build-script-nested\"\nversion = \"0.1.0\"\nedition = \"2024\"\n")
  File.write(File.join(build_nested, "src", "lib.rs"), "#[test]\nfn passes() {}\n")
  begin
    ["build", "test"].each do |command|
      File.write(build_script, <<~RUST)
        fn main() {
            let status = std::process::Command::new(std::env::var("CARGO").unwrap())
                .args(["#{command}", "--offline", "--manifest-path", "../build-script-nested/Cargo.toml"])
                .status().unwrap();
            assert!(status.success());
            panic!("outer build script failed after nested Cargo succeeded");
        }
      RUST
      dumped = run.call("build-script-nested-#{command}-failure", ["test", "--offline"], 101, nil, build: nil)
      check(dumped[2].include?("Finished") && dumped[2].include?("--- stderr"), "Nested Cargo completion was not dumped")
    end
  ensure
    FileUtils.rm_f(build_script)
  end
  nested = File.join(root, "nested")
  FileUtils.mkdir_p(File.join(nested, "src"))
  File.write(File.join(nested, "Cargo.toml"), "[package]\nname = \"nested-failure\"\nversion = \"0.1.0\"\nedition = \"2024\"\n")
  File.write(File.join(nested, "src", "lib.rs"), "compile_error!(\"nested compilation failure\");\n")
  begin
    File.write(source, original_source + <<~RUST)
      #[test]
      fn nested_compile_failure_test() {
          let status = std::process::Command::new("cargo")
              .args(["check", "--offline", "--manifest-path", "../nested/Cargo.toml"])
              .status().unwrap();
          assert!(!status.success());
      }
    RUST
    run.call("nested-compile-failure-test", ["test", "--offline", "--lib", "nested_compile_failure_test"], 0, 1)
  ensure
    File.write(source, original_source)
  end
  cargo_config = File.join(checkout, ".cargo", "config.toml")
  FileUtils.mkdir_p(File.dirname(cargo_config))
  begin
    File.write(cargo_config, "[term]\nquiet = true\n")
    quiet = run.call("configured-quiet-success", ["test", "--offline"], 0, nil, build: nil)
    check(quiet[2].include?("build phase was not measured"), "Unmeasured build omission was not diagnosed")
    run.call("configured-quiet-failure", ["test", "--offline"], 101, nil, fail: true, build: nil)
    File.write(source, original_source + <<~RUST)
      #[test]
      fn nested_build_failure() {
          let status = std::process::Command::new("cargo")
              .args(["check", "--offline", "--manifest-path", "../nested/Cargo.toml"])
              .status().unwrap();
          assert!(status.success());
      }
    RUST
    nested_failure = run.call("configured-quiet-nested-failure", ["test", "--offline", "--lib", "nested_build_failure"], 101, nil, build: nil)
    check((nested_failure[1] + nested_failure[2]).include?("nested compilation failure"), "Nested compiler was not exercised")
  ensure
    File.write(source, original_source)
    FileUtils.rm_f(cargo_config)
  end
  run.call("rejected-success", ["test", "--offline"], 0, 10, reject: true)
  run.call("rejected-failure", ["test", "--offline", "--no-fail-fast"], 101, 10, fail: true, reject: true)
  test_case = lambda do |mod, suite, name, state|
    { id: SecureRandom.uuid, name: name, module: { id: SecureRandom.uuid, name: mod },
      suite: { id: SecureRandom.uuid, name: suite }, avg_duration: 0, is_flaky: true,
      is_quarantined: true, state: state, url: "http://127.0.0.1:#{port}/case" }
  end
  package = "tuist-cargo-reporting-fixture"
  docs_module = "#{package}::doctest/tuist_cargo_reporting_fixture"
  quarantine["muted"] = [test_case.call("other-package", "tests", "optionally_fails", "muted"),
                           test_case.call(package, "tests", "optionally_fails", "muted")]
  quarantine_requests.clear
  run.call("muted-failure", ["test", "--offline"], 0, 10, fail: true)
  check(quarantine_requests == [["muted", 1], ["muted", 2], ["skipped", 1]], "Quarantine pagination lost a page/state")
  muted_report = requests.reverse.find { |item| item["kind"] == "tests" }.fetch("payload")
  failed = muted_report.fetch("test_modules").flat_map { |mod| mod.fetch("test_cases") }.select { |test| test["status"] == "failure" }
  check(failed.length == 1 && failed[0]["is_quarantined"], "Muted failure was lost instead of attributed")
  run.call("muted-rejected-upload", ["test", "--offline"], 0, 10, fail: true, reject: true)
  run.call("muted-existing-no-fail-fast", ["test", "--offline", "--no-fail-fast"], 0, 10, fail: true)
  begin
    doctest_line = original_source.lines.length + 2
    quarantine["muted"] = [test_case.call(docs_module, "doctests", "src/lib.rs - termination_probe (line #{doctest_line})", "muted")]
    { "signal" => 'unsafe extern "C" { fn raise(signal: i32) -> i32; } unsafe { raise(15); }',
      "panic" => 'panic!("ordinary muted doctest failure");' }.each do |kind, body|
      File.write(source, original_source + "\n/// ```standalone_crate\n/// #{body}\n/// ```\npub fn termination_probe() {}\n")
      result = run.call("muted-doctest-#{kind}", ["test", "--offline", "--doc"], kind == "signal" ? 101 : 0, 6, failures: 1)
      check(result[1].match?(/Test executable failed \((?:terminated by signal|signal:)/), "Doctest signal was not exercised") if kind == "signal"
    end
  ensure
    File.write(source, original_source)
    quarantine["muted"] = [test_case.call(package, "tests", "optionally_fails", "muted")]
  end
  signal_runner = File.join(root, "signal-runner")
  File.write(signal_runner, <<~SH)
    #!/bin/sh
    for argument do
      if [ "$argument" = "--list" ]; then exec "$@"; fi
    done
    "$@"
    kill -TERM $$
  SH
  File.chmod(0700, signal_runner)
  host, host_status = Open3.capture2(environment, "rustc", "-vV", unsetenv_others: true)
  check(host_status.success?, "Could not resolve the Rust host")
  runner_key = "CARGO_TARGET_#{host.lines.find { |line| line.start_with?('host: ') }.split.last.upcase.tr('-', '_')}_RUNNER"
  signalled = run.call("muted-signalled-runner", ["test", "--offline", "--lib"], 101, 3, fail: true,
                       env: { runner_key => signal_runner })
  check(signalled[2].include?("signal: 15"), "Runner signal was not exercised")
  run.call("quarantine-disabled", ["test", "--offline"], 101, 3, fail: true, env: { "TUIST_TEST_SKIP_QUARANTINE" => "1" })
  quarantine_rejection = true
  unavailable = run.call("quarantine-unavailable", ["test", "--offline"], 101, 3, fail: true)
  check((unavailable[1] + unavailable[2]).include?("Failed to fetch Cargo quarantine"), "Quarantine fallback lacked a warning")
  quarantine_rejection = false
  unsupported = run.call("quarantine-quiet", ["test", "--offline", "--quiet"], 1, nil, build: nil)
  check(test_lines.call(unsupported[1]).empty?, "Unsupported quarantine mode executed tests")
  begin
    File.write(cargo_config, "[term]\nquiet = true\n")
    run.call("quarantine-configured-quiet", ["test", "--offline"], 1, nil, build: nil)
  ensure
    FileUtils.rm_f(cargo_config)
  end
  begin
    File.write(source, original_source + "\n#[test]\nfn unmuted_failure() { panic!(\"not muted\"); }\n")
    run.call("mixed-failures", ["test", "--offline", "--lib"], 101, 4, fail: true, failures: 2)
    File.write(source, original_source + "\ncompile_error!(\"cannot mute compilation errors\");\n")
    run.call("quarantine-compile-failure", ["test", "--offline"], 101, nil, build: nil)
  ensure
    File.write(source, original_source)
  end
  quarantine["muted"] = []
  quarantine["skipped"] = [test_case.call(package, "tests", "optionally_fails", "skipped"),
                             test_case.call(docs_module, "doctests", "src/lib.rs - answer (line 12)", "skipped")]
  skipped = run.call("skip-quarantine", ["test", "--offline"], 0, 10, env: { "TUIST_FIXTURE_FAIL" => "1" })
  check(!skipped[1].include?("test tests::optionally_fails ..."), "Skipped unit test ran")
  check(!skipped[1].include?("test src/lib.rs - answer (line 12)"), "Skipped doctest ran")
  skipped_report = requests.reverse.find { |item| item["kind"] == "tests" }.fetch("payload")
  check(skipped_report.fetch("test_modules").flat_map { |mod| mod.fetch("test_cases") }.count { |test| test["is_quarantined"] && test["status"] == "skipped" } == 2,
        "Skipped quarantine cases missing")
  exact_docs = run.call("exact-doctest-skip", ["test", "--offline", "--doc", "--", "--exact"], 1, nil, build: nil)
  check(exact_docs[2].include?("cannot safely skip individual doctests with --exact"), "Exact doctest exclusion was not rejected")
  check(test_lines.call(exact_docs[1]).empty?, "Exact doctest exclusion executed a skipped example")
  run.call("skip-filter-intersection", ["test", "--offline", "--lib", "optionally_fails"], 0, 1,
           env: { "TUIST_FIXTURE_FAIL" => "1" })
  begin
    File.write(source, original_source + "\n#[test]\nfn optionally_fails_sibling() {}\n")
    prefix = run.call("skip-prefix-collision", ["test", "--offline", "--lib", "optionally_fails"], 0, 2)
    check(prefix[1].include?("test optionally_fails_sibling ... ok"), "Skip excluded a different matching test")
  ensure
    File.write(source, original_source)
  end
  quarantine["skipped"] = [test_case.call(docs_module, "doctests", "src/lib.rs - answer (line 2)", "skipped")]
  ambiguous_skip = run.call("ambiguous-doctest-skip", ["test", "--offline", "--doc"], 1, nil, build: nil)
  check((ambiguous_skip[1] + ambiguous_skip[2]).include?("cannot safely skip"), "Unsafe doctest exclusion was not diagnosed")
  check(test_lines.call(ambiguous_skip[1]).empty?, "Ambiguous doctest filtering ran tests")
  manifest = File.join(checkout, "Cargo.toml")
  manifest_before_bench = File.read(manifest)
  FileUtils.mkdir_p(File.join(checkout, "benches"))
  File.write(File.join(checkout, "benches", "custom.rs"), 'fn main() { panic!("custom harness must not run"); }')
  begin
    File.write(manifest, manifest_before_bench + "\n[[bench]]\nname = \"custom\"\nharness = false\n")
    quarantine["skipped"] = [test_case.call(package, "tests", "optionally_fails", "skipped")]
    run.call("unselected-custom-bench", ["test", "--offline", "--lib"], 0, 3, env: { "TUIST_FIXTURE_FAIL" => "1" })
    custom = run.call("selected-custom-bench", ["test", "--offline", "--all-targets"], 1, nil, build: nil)
    check(test_lines.call(custom[1]).empty?, "Selected custom harness executed before rejection")
    check(custom[2].include?("standard libtest harnesses"), "Selected custom harness was not diagnosed")
    run.call("unselected-custom-bench-plan", ["test", "--offline", "--lib", "--no-run", "--shard-total", "1"], 0, nil,
             env: { "TUIST_SHARD_REFERENCE" => "lib-only" }, build: nil)
    marker = File.join(root, "custom-harness-ran")
    custom_source = 'fn main() { std::fs::write(std::env::var("TUIST_HARNESS_MARKER").unwrap(), "ran").unwrap(); }'
    File.write(File.join(checkout, "tests", "custom.rs"), custom_source)
    File.write(manifest, File.read(manifest) + "\n[[test]]\nname = \"custom\"\nharness = false\n")
    patterns = run.call("custom-target-pattern-plan", ["test", "--offline", "--test", "cust*", "--no-run", "--shard-total", "1"], 1, nil,
                        env: { "TUIST_SHARD_REFERENCE" => "custom-pattern", "TUIST_HARNESS_MARKER" => marker }, build: nil)
    check(patterns[2].include?("target patterns are unsupported") && !File.exist?(marker), "Target pattern executed a custom harness")
    File.write(source, custom_source)
    File.write(manifest, File.read(manifest) + "\n[lib]\nharness = false\n")
    native = command([cargo, "test", "--offline", "--benches", "--no-run"], checkout,
                     environment.merge("TUIST_HARNESS_MARKER" => marker), root, "native-custom-bench-no-run")
    check(native[0].zero? && !File.exist?(marker), "Native no-run executed a custom harness")
    benches = run.call("custom-library-benches-plan", ["test", "--offline", "--benches", "--no-run", "--shard-total", "1"], 1, nil,
                       env: { "TUIST_SHARD_REFERENCE" => "custom-library", "TUIST_HARNESS_MARKER" => marker }, build: nil)
    check(benches[2].include?("standard libtest harnesses") && !File.exist?(marker), "--benches executed a custom library harness")
  ensure
    File.write(manifest, manifest_before_bench)
    File.write(source, original_source)
    FileUtils.rm_rf(File.join(checkout, "benches"))
    FileUtils.rm_f(File.join(checkout, "tests", "custom.rs"))
  end
  quarantine["skipped"] = []
  planned = run.call("plain-shard-plan", ["test", "--offline", "--no-run", "--shard-total", "2"], 0, nil,
                     env: { "TUIST_SHARD_REFERENCE" => "cargo-e2e", "TUIST_FIXTURE_FAIL" => "1" }, build: nil)
  check(JSON.parse(planned[1]).fetch("shard_plan_id") == plan_id, "Missing plan output")
  check(assignments.flatten.sort == [package, "#{package}::api", "#{package}::doc", docs_module].sort, "Wrong planned modules")
  outputs = []
  assignments.each_with_index do |mods, index|
    count = mods.sum { |mod| mod == package ? 3 : mod == docs_module ? 5 : 1 }
    result = run.call("plain-shard-#{index}", ["test", "--offline"], 0, count,
                      env: { "TUIST_SHARD_PLAN_ID" => plan_id, "TUIST_SHARD_INDEX" => index.to_s }, shard: index)
    outputs += test_lines.call(result[1])
  end
  check(outputs.sort == test_lines.call(baseline[1]), "Shards did not execute all tests exactly once")
  quarantine["muted"] = [test_case.call(package, "tests", "optionally_fails", "muted")]
  run.call("sharded-quarantine", ["test", "--offline"], 0, 4, fail: true,
           env: { "TUIST_SHARD_PLAN_ID" => plan_id, "TUIST_SHARD_INDEX" => "0" }, shard: 0)
  quarantine["muted"] = []
  shard_override = { shard_plan_id: plan_id, modules: [], suites: {}, download_urls: [] }
  empty = run.call("empty-shard", ["test", "--offline"], 0, 0,
                   env: { "TUIST_SHARD_PLAN_ID" => plan_id, "TUIST_SHARD_INDEX" => "0" }, shard: 0)
  check(test_lines.call(empty[1]).empty?, "Empty shard executed tests")
  [{ modules: ["unknown-module"], suites: {} }, { modules: [], suites: { package => ["tests"] } }, nil].each_with_index do |override, index|
    shard_override = override&.merge(shard_plan_id: plan_id, download_urls: [])
    result = run.call("invalid-shard-#{index}", ["test", "--offline"], 1, nil, build: nil,
                     env: { "TUIST_SHARD_PLAN_ID" => plan_id, "TUIST_SHARD_INDEX" => (override.nil? ? "99" : "0") })
    check(test_lines.call(result[1]).empty?, "Invalid shard executed unfiltered tests")
  end
  [["test", "--shard-total", "2"], ["test", "--no-run", "--shard-total", "0"],
   ["test", "--no-run", "--shard-total", "2", "--shard-max", "4"]].each_with_index do |arguments, index|
    result = run.call("invalid-plan-options-#{index}", arguments, 1, nil, build: nil)
    check(test_lines.call(result[1]).empty?, "Invalid plan options executed tests")
  end
  leak_pid = File.join(root, "leaked-child.pid")
  ["leaked-descendant", "periodic-descendant"].each do |scenario|
    started = Time.now
    begin
      tick = scenario == "periodic-descendant" ? "1" : nil
      run.call(scenario, ["test", "--offline", "tests::passes"], 0, nil,
               env: { "TUIST_FIXTURE_LEAK_PID" => leak_pid, "TUIST_FIXTURE_TICK" => tick })
      check(Time.now - started < 10, "Wrapper waited for the background descendant")
    ensure
      begin
        Process.kill("TERM", Integer(File.read(leak_pid))) if File.file?(leak_pid)
      rescue Errno::ESRCH
        # Closing the pipe may have already terminated the writer through SIGPIPE.
      end
    end
  end
  member = File.join(checkout, "crates", "member")
  FileUtils.mkdir_p([File.join(member, "src"), File.join(member, "tests")])
  File.write(File.join(member, "Cargo.toml"), "[package]\nname = \"reporting-member\"\nversion = \"0.1.0\"\nedition = \"2024\"\n")
  File.write(File.join(member, "src", "lib.rs"), "#[test]\nfn member_unit() {}\n")
  File.write(File.join(member, "tests", "api.rs"), "#[test]\nfn member_integration() {}\n")
  manifest = File.join(checkout, "Cargo.toml")
  File.write(manifest, File.read(manifest).sub("[workspace]", "[workspace]\nmembers = [\"crates/member\"]\ndefault-members = [\".\"]"))
  run.call("selected-member", ["test", "--offline", "-p", "reporting-member"], 0, 2)
  run.call("ambiguous-workspace", ["test", "--offline", "--workspace"], 0, nil)
  workspace_manifest = File.read(manifest)
  member_manifest = File.join(member, "Cargo.toml")
  member_source = File.join(member, "src", "lib.rs")
  begin
    File.write(manifest, workspace_manifest + "\n[features]\ndefault = [\"extra\"]\nextra = []\n")
    File.write(source, original_source + "\npub fn feature_enabled() -> bool { cfg!(feature = \"extra\") }\n")
    File.write(member_manifest, File.read(member_manifest) + "\n[dependencies]\ntuist-cargo-reporting-fixture = { path = \"../..\", default-features = false }\n")
    File.write(member_source, "#[test]\nfn feature_regression() { assert!(!tuist_cargo_reporting_fixture::feature_enabled()); }\n")
    native = command([cargo, "test", "--workspace", "--offline", "--lib"], checkout, environment, root, "native-workspace-features")
    check(native[0] == 101, "Native workspace feature regression was not exercised")
    quarantine["muted"] = [test_case.call("unrelated-package", "tests", "unrelated", "muted")]
    [[], ["--features", "extra"], ["--all-features"]].each_with_index do |features, index|
      run.call("workspace-feature-unification-#{index}", ["test", "--offline", "--workspace", "--lib", *features], 101, 4, failures: 1)
    end
    run.call("single-package-feature-control", ["test", "--offline", "-p", "reporting-member", "--lib"], 0, 1)
    quarantine["muted"] = []
    quarantine["skipped"] = [test_case.call(package, "tests", "optionally_fails", "skipped")]
    rejected = run.call("workspace-skip-feature-safety", ["test", "--offline", "--workspace", "--lib"], 1, nil, build: nil)
    check(rejected[2].include?("preserve feature unification") && test_lines.call(rejected[1]).empty?, "Unsafe workspace skip selection was not rejected")
    run.call("default-member-skip", ["test", "--offline", "--lib"], 0, 3, env: { "TUIST_FIXTURE_FAIL" => "1" })
    run.call("workspace-shard-feature-safety", ["test", "--offline", "--workspace", "--lib", "--no-run", "--shard-total", "2"], 1, nil,
             env: { "TUIST_SHARD_REFERENCE" => "workspace-unsafe" }, build: nil)
    File.write(member_manifest, File.read(member_manifest) + "\n[lib]\nharness = false\n")
    File.write(member_source, 'fn main() { panic!("unselected package must not run"); }')
    run.call("unselected-package-custom-harness", ["test", "--offline", "-p", package, "--lib"], 0, 3)
  ensure
    File.write(manifest, workspace_manifest)
    File.write(source, original_source)
    quarantine["muted"] = []
    quarantine["skipped"] = []
  end
  dependency = File.join(root, "helper")
  FileUtils.mkdir_p([File.join(dependency, "src"), File.join(dependency, "tests")])
  File.write(File.join(dependency, "Cargo.toml"), <<~TOML)
    [package]
    name = "helper"
    version = "0.1.0"
    edition = "2024"
    [lib]
    name = "tuist_cargo_reporting_fixture"
  TOML
  File.write(File.join(dependency, "src", "lib.rs"), <<~RUST)
    /// ```
    /// assert!(true);
    /// ```
    pub fn dependency() {}
    #[test]
    fn dependency_only() {}
  RUST
  File.write(File.join(dependency, "tests", "api.rs"), "#[test]\nfn dependency_integration() {}\n")
  manifest_source = File.read(manifest).sub('members = ["crates/member"]', 'exclude = ["crates/member"]')
  File.write(manifest, manifest_source + "\n[dependencies]\nhelper = { path = \"../helper\" }\n")
  run.call("non-member-library", ["test", "--offline", "-p", "helper", "--lib"], 0, nil)
  run.call("non-member-integration", ["test", "--offline", "-p", "helper", "--test", "api"], 0, nil)
  run.call("non-member-doctests", ["test", "--offline", "-p", "helper", "--doc"], 0, nil)
  run.call("version-qualified-package", ["test", "--offline", "-p", "tuist-cargo-reporting-fixture@0.1.0", "--lib"], 0, nil)
  run.call("glob-package", ["test", "--offline", "-p", "tuist-*", "--lib"], 0, nil)
  File.write(File.join(root, "summary.json"), JSON.pretty_generate(summaries))
  puts "PASS: all #{summaries.length} public-CLI scenarios using #{toolchain}"
  puts "Not exercised: Phoenix authorization, database persistence, or dashboard rendering."
ensure
  server.shutdown
  thread.join
end
