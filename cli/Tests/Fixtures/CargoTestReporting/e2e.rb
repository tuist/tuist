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
token = "cargo-e2e-loopback-only"
server = WEBrick::HTTPServer.new(BindAddress: "127.0.0.1", Port: 0,
                                Logger: WEBrick::Log.new(File::NULL, WEBrick::Log::FATAL), AccessLog: [])
port = server.listeners.first.addr[1]
server.mount_proc("/") do |request, response|
  begin
    response["Content-Type"] = "application/json"
    if request.request_method == "GET"
      check(request.path == "/api/cache/endpoint", "Unexpected GET #{request.path}")
      response.body = JSON.generate(endpoint: nil)
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
  run = lambda do |name, arguments, code, count, fail: false, reject: false, env: {}|
    rejection = reject
    current = environment.merge(env)
    current["TUIST_FIXTURE_FAIL"] = "1" if fail
    start = requests.length
    result = command(["cargo", *arguments], checkout, current, root, name)
    received = requests.drop(start)
    File.write(File.join(root, "#{name}.requests.json"), JSON.pretty_generate(received))
    check(result[0] == code, "#{name}: exit #{result[0]} != #{code}\n#{result[2]}")
    check(received.none? { |item| item.key?("error") }, "#{name}: #{received.inspect}")
    reports = received.select { |item| item["kind"] == "tests" }.map { |item| item.fetch("payload") }
    check(reports.length == (count.nil? ? 0 : 1), "#{name}: unexpected test uploads\n#{result[2]}")
    builds = received.select { |item| item["kind"] == "builds" }.map { |item| item.fetch("payload") }
    check(builds.length == 1 && builds[0]["status"] == (code.zero? ? "success" : "failure"), "#{name}: wrong build report")
    check(!builds[0].fetch("compilations").empty?, "Cold run did not observe rustc") if name == "success"
    unless count.nil?
      report = reports.first
      check(report["build_system"] == "cargo" && report["scheme"] == "cargo test", "Wrong test run identity")
      check(report["status"] == (code.zero? ? "success" : "failure"), "Wrong test run status")
      cases = report.fetch("test_modules").flat_map { |mod| mod.fetch("test_cases") }
      check(cases.length == count, "#{name}: #{cases.length} cases != #{count}")
      check(cases.count { |test| test["status"] == "failure" } == (fail ? 1 : 0), "Wrong failed count")
      check(cases.all? { |test| test["duration"].zero? }, "Invented per-test timing")
      check(cases.none? { |test| test["name"].end_with?(" - compile") }, "Unnormalized no_run doctest")
      if name == "selected-member"
        check(report.fetch("test_modules").all? { |mod| mod.fetch("name").start_with?("reporting-member") }, "Misattributed member tests")
        check(report.fetch("test_modules").any? { |mod| mod.fetch("name") == "reporting-member::api" }, "Missing member integration identity")
      end
      check(!report.key?("enumerated_tests") && !report.key?("shard_plan_id"), "Invented inventory/shard")
      if count == 10
        modules = report.fetch("test_modules").map { |mod| [mod.fetch("name"), mod] }.to_h
        check(modules.keys.sort == ["tuist-cargo-reporting-fixture", "tuist-cargo-reporting-fixture::api",
                                    "tuist-cargo-reporting-fixture::doc",
                                    "tuist-cargo-reporting-fixture::doctest/tuist_cargo_reporting_fixture"], "Wrong modules")
        docs = modules.fetch("tuist-cargo-reporting-fixture::doctest/tuist_cargo_reporting_fixture").fetch("test_cases")
        check(docs.length == 5 && docs.count { |test| test["status"] == "skipped" } == 1, "Wrong doctests")
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
  run.call("list", ["test", "--offline", "--", "--list"], 0, nil)
  run.call("quiet", ["test", "--offline", "--quiet"], 0, nil)
  run.call("verbose", ["test", "--offline", "--verbose"], 0, nil)
  run.call("very-verbose", ["test", "--offline", "-vv"], 0, nil)
  run.call("environment-verbose", ["test", "--offline"], 0, nil, env: { "CARGO_TERM_VERBOSE" => "true" })
  run.call("environment-quiet", ["test", "--offline"], 0, nil, env: { "CARGO_TERM_QUIET" => "true" })
  run.call("rejected-success", ["test", "--offline"], 0, 10, reject: true)
  run.call("rejected-failure", ["test", "--offline", "--no-fail-fast"], 101, 10, fail: true, reject: true)
  leak_pid = File.join(root, "leaked-child.pid")
  started = Time.now
  begin
    run.call("leaked-descendant", ["test", "--offline", "tests::passes"], 0, nil,
             env: { "TUIST_FIXTURE_LEAK_PID" => leak_pid })
    check(Time.now - started < 10, "Wrapper waited for the 30-second descendant")
  ensure
    Process.kill("TERM", Integer(File.read(leak_pid))) if File.file?(leak_pid)
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
  File.write(File.join(root, "summary.json"), JSON.pretty_generate(summaries))
  puts "PASS: all #{summaries.length} public-CLI scenarios using #{toolchain}"
  puts "Not exercised: Phoenix authorization, database persistence, or dashboard rendering."
ensure
  server.shutdown
  thread.join
end
