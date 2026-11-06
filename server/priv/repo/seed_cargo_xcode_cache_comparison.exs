# Replays recorded Xcode fixtures into the isolated Cargo/Xcode comparison demo.
# Build the production parser with server/native/xcactivitylog_nif/build.sh first.
# TUIST_CACHE_COMPARISON_PARSER overrides its path; TUIST_CACHE_COMPARISON_RECORDS
# optionally reuses already parsed summaries and step JSONL.
# Existing synthetic history and genuine Cargo reports are preserved.
import Ecto.Query

alias Tuist.Accounts
alias Tuist.Builds
alias Tuist.Builds.Build
alias Tuist.Builds.BuildFile
alias Tuist.Builds.BuildIssue
alias Tuist.Builds.BuildTarget
alias Tuist.Builds.CacheableTask
alias Tuist.Builds.CASOutput
alias Tuist.ClickHouseRepo
alias Tuist.Projects.Project
alias Tuist.Repo

if Mix.env() != :dev or Repo.config()[:database] != "tuist_cargo_resonant_fluxon_demo" or
     ClickHouseRepo.config()[:database] != "tuist_cargo_resonant_fluxon_demo" do
  raise "Cache comparison replays require the isolated development demo databases"
end

records =
  System.get_env("TUIST_CACHE_COMPARISON_RECORDS") ||
    Path.join(System.tmp_dir!(), "tuist-xcode-comparison-#{System.unique_integer([:positive])}")

File.mkdir_p!(records)
parser = System.get_env("TUIST_CACHE_COMPARISON_PARSER") || Path.expand("priv/native/xcactivitylog-parser")
{:ok, user} = Accounts.get_user_by_email("tuistrocks@tuist.dev")
account = Repo.preload(user, :account).account
project = Repo.get_by!(Project, account_id: account.id, name: "xcode-demo")

# Parsed fixture keys come from the production parser's fixed schema.
atomize = fn map -> Map.new(map, fn {key, value} -> {String.to_existing_atom(key), value} end) end

# Load schemas before resolving their field atoms.
for schema <- [Build, BuildFile, BuildIssue, BuildTarget, CacheableTask, CASOutput, Tuist.Builds.Step],
    do: schema.__schema__(:fields)

fixtures = [
  {"remote", "build-with-remote-hits/build-with-remote-hits.xcactivitylog", "bd738db6-3ec5-4f42-8fc2-a800e1b70001"},
  {"uploads", "build-with-uploads/build-with-uploads.xcactivitylog", "bd738db6-3ec5-4f42-8fc2-a800e1b70002"},
  {"local", "build-with-local-hits.xcactivitylog", "bd738db6-3ec5-4f42-8fc2-a800e1b70003"},
  {"mixed", "failed-build-with-cache-misses.xcactivitylog", "bd738db6-3ec5-4f42-8fc2-a800e1b70004"},
  {"warning", "build-with-warning.xcactivitylog", "bd738db6-3ec5-4f42-8fc2-a800e1b70005"},
  {"clang", "xcode_27_clang_cache_hits.xcactivitylog", "bd738db6-3ec5-4f42-8fc2-a800e1b70006"}
]

for {name, source, id} <- fixtures do
  if !File.exists?(Path.join(records, name <> ".json")) do
    log =
      if name == "clang",
        do: Path.expand("native/xcactivitylog_nif/Tests/XCActivityLogParserTests/Fixtures/#{source}"),
        else: Path.expand("../cli/Tests/Fixtures/#{source}")

    arguments = [
      log,
      Path.join(records, "missing-cas.db"),
      Path.join(Path.dirname(log), "state"),
      Path.join(records, name <> ".json"),
      Path.join(records, name <> ".steps.jsonl")
    ]

    case System.cmd(parser, arguments, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, status} -> raise "Recorded Xcode fixture parse failed (#{status}): #{output}"
    end
  end

  parsed = records |> Path.join(name <> ".json") |> File.read!() |> JSON.decode!()

  if !ClickHouseRepo.exists?(from(b in Build, where: b.id == ^id and b.project_id == ^project.id)) do
    cas_outputs =
      Enum.map(parsed["cas_outputs"], fn output ->
        output |> atomize.() |> Map.update!(:duration, &trunc/1)
      end)

    steps =
      records |> Path.join(name <> ".steps.jsonl") |> File.stream!() |> Stream.map(&(&1 |> JSON.decode!() |> atomize.()))

    {:ok, _} =
      Builds.create_build(%{
        id: id,
        project_id: project.id,
        account_id: account.id,
        duration: parsed["duration"],
        status: parsed["status"],
        category: parsed["category"],
        is_ci: false,
        custom_tags: ["recorded-fixture", name],
        custom_values: %{
          "Source" => source,
          "Recording ID" => parsed["unique_identifier"],
          "Data provenance" => "Recorded activity log and accompanying CAS metadata; replayed for UI comparison"
        },
        cacheable_tasks: Enum.map(parsed["cacheable_tasks"], atomize),
        cas_outputs: cas_outputs,
        issues: Enum.map(parsed["issues"], atomize),
        targets: Enum.map(parsed["targets"], atomize),
        files: Enum.map(parsed["files"], atomize),
        build_steps: steps
      })
  end

  IO.puts("Xcode #{name}: http://localhost:9071/#{account.name}/#{project.name}/builds/build-runs/#{id}?tab=xcode-cache")
end

for schema <- [Build, BuildFile, BuildIssue, BuildTarget, CacheableTask, CASOutput],
    do: Module.concat(schema, Buffer).flush()

IO.puts("Recorded Xcode cache, compiler, diagnostics and Timeline comparison data ready; no synthetic cache measurements")
