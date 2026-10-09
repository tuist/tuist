defmodule Mix.Tasks.Tuist.Test.Build do
  @shortdoc "Build for testing once and plan the test shards"

  @moduledoc """
  Compiles the project for testing, splits its tests into shards, and uploads
  the build so every shard can test without compiling again.

      mix tuist.test.build --shard-max 4 [ARGS...]

  Run it once per pipeline, on one machine. Then run `mix tuist.test` (or
  `mix test`, if you aliased it) on each shard with `TUIST_SHARD_INDEX` set:
  it downloads the build, runs only that shard's tests, and reports them as
  part of one test run.

  Tuist balances the shards with how long each test module took in earlier
  runs. Modules it has not seen yet get an estimate. `async: true` modules
  run alongside each other, up to ExUnit's `:max_cases` from the `:ex_unit`
  application environment (twice the schedulers by default), and the others
  one at a time, and the shards are balanced by that.

  ## Options

    * `--shard-max N` - the most shards to split into (default 2)
    * `--shard-min N` - the fewest shards to split into
    * `--shard-total N` - an exact number of shards, instead of a range
    * `--shard-max-duration MS` - the longest a shard should take, in
      milliseconds; Tuist picks the number of shards to fit
    * `--shard-reference REF` - the name the shards find the plan by. Derived
      from the pipeline run on GitHub Actions, GitLab, CircleCI and Buildkite;
      set it, or `TUIST_SHARD_REFERENCE`, anywhere else
    * `--no-upload` - plan the shards without uploading the build; each shard
      then compiles for itself
    * `--url`, `--project` - as in `mix tuist.test`

  Every other argument is forwarded to `mix compile`.

  ## What the shards need

  The same checkout, the same Elixir and Erlang versions, and `mix deps.get`.
  The uploaded build is the `_build/test` directory; dependency sources stay
  in `deps/`.

  ## Output

  On GitHub Actions the shard indexes are written to `GITHUB_OUTPUT` as
  `matrix={"shard":[0,1,...]}`, ready for a job matrix. Elsewhere the plan is
  written to `.tuist-shard-matrix.json`.
  """

  use Mix.Task

  alias TuistEx.Analytics.Args
  alias TuistEx.Analytics.Shards

  @preferred_cli_env :test

  @switches [
    url: :string,
    project: :string,
    shard_max: :integer,
    shard_min: :integer,
    shard_total: :integer,
    shard_max_duration: :integer,
    shard_reference: :string
  ]

  def run(args) do
    case Args.ensure_env(:test, "tuist.test.build", args) do
      :ok -> run_in_test_env(args)
      {:reexecuted, 0} -> :ok
      {:reexecuted, status} -> exit({:shutdown, status})
    end
  end

  defp run_in_test_env(args) do
    if Mix.Project.umbrella?(),
      do:
        Mix.raise(
          "Tuist does not shard from an umbrella's root yet. Run this inside one of its applications."
        )

    {options, compile_args} = Args.split(args, @switches)
    {upload?, compile_args} = pop_flag(compile_args, "--no-upload")
    options = Keyword.put_new(options, :shard_max, 2)
    Application.put_env(:tuist_ex, :analytics_options, Keyword.take(options, [:url, :project]))

    reference = unwrap(Shards.reference(options))

    # Before compiling: a test file that cannot be parsed stops the plan here.
    units = Shards.test_units()
    if units == %{}, do: Mix.raise("No test files found, so there is nothing to shard.")

    Mix.Task.run("compile", compile_args)

    plan = unwrap(Shards.create_plan(reference, Map.keys(units), options))
    shards = plan["shards"] || []

    Mix.shell().info(
      "Tuist: planned #{Shards.count(length(shards), "shard")} for #{Shards.count(map_size(units), "test file")} (#{reference})"
    )

    for shard <- shards do
      Mix.shell().info(
        "  Shard #{shard["index"]}: #{Shards.count(length(shard["test_targets"]), "test file")}, about #{seconds(shard["estimated_duration_ms"])}"
      )
    end

    if upload? do
      size = unwrap(Shards.upload_build(reference, Mix.Project.build_path(), options))
      Mix.shell().info("Tuist: uploaded the build (#{Float.round(size / 1_048_576, 1)} MB)")
    end

    write_matrix(reference, shards)
    :ok
  end

  defp pop_flag(args, flag), do: {flag not in args, List.delete(args, flag)}

  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, reason}) when is_binary(reason), do: Mix.raise(reason)
  defp unwrap({:error, reason}), do: Mix.raise("Tuist sharding failed: #{inspect(reason)}")

  defp seconds(nil), do: "an unknown time"
  defp seconds(ms), do: "#{Float.round(ms / 1000, 1)}s"

  @doc false
  def write_matrix(reference, shards, environment \\ &System.get_env/1) do
    indexes = Enum.map(shards, & &1["index"])

    case environment.("GITHUB_OUTPUT") do
      path when is_binary(path) and path != "" ->
        File.write!(path, "matrix=#{JSON.encode!(%{shard: indexes})}\n", [:append])
        Mix.shell().info("Tuist: wrote the shard matrix to GITHUB_OUTPUT")

      _ ->
        path = ".tuist-shard-matrix.json"

        File.write!(
          path,
          JSON.encode!(%{reference: reference, shard_count: length(shards), shards: shards})
        )

        Mix.shell().info("Tuist: wrote the shard plan to #{path}")
    end
  end
end
