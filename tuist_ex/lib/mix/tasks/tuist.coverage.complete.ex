defmodule Mix.Tasks.Tuist.Coverage.Complete do
  @shortdoc "Tell Tuist a commit's coverage is complete"

  @moduledoc """
  Tells Tuist that every run of a commit that measures coverage has reported,
  which the runs alone cannot show. The commit's coverage is then complete and
  joins its branch's trend. Run it in a final pipeline job that depends on
  every job that runs `mix tuist.test --cover`.

      mix tuist.coverage.complete [--commit SHA] [--url URL] [--project HANDLE]

  The commit defaults to the one the run reports: `GIT_COMMIT`, or the
  checkout's `HEAD`.
  """

  use Mix.Task

  alias TuistEx.Analytics.Env
  alias TuistEx.Analytics.HTTP

  @switches [commit: :string, url: :string, project: :string]

  def run(args) do
    {options, rest, invalid} = OptionParser.parse(args, strict: @switches)

    if rest != [] or invalid != [] do
      Mix.raise(
        "Usage: mix tuist.coverage.complete [--commit SHA] [--url URL] [--project HANDLE]"
      )
    end

    sha = options[:commit] || Env.git_commit_sha()

    if sha in [nil, ""],
      do: Mix.raise("The commit is unknown: pass --commit or run inside a Git checkout.")

    case HTTP.project_request(:post, "/tests/coverage/commits/#{sha}/complete", %{}, options) do
      {:ok, %{"coverage" => coverage}} ->
        Mix.shell().info(
          "Coverage of commit #{String.slice(sha, 0, 7)} is complete: #{coverage}%."
        )

      {:ok, _pending} ->
        Mix.shell().info(
          "No run of commit #{String.slice(sha, 0, 7)} has reported coverage yet. " <>
            "Its coverage is marked complete once one does."
        )

      {:error, reason} ->
        Mix.raise(
          "Could not mark the coverage of commit #{String.slice(sha, 0, 7)} complete: #{inspect(reason)}"
        )
    end
  end
end
