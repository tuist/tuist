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

  alias TuistEx.Analytics.Config
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
          "Coverage of commit #{String.slice(sha, 0, 7)} is complete: #{coverage}%.\n" <>
            "  See the commit's coverage at #{commits_url(options)}/#{sha}"
        )

      {:ok, _pending} ->
        # Usually the runs are still being processed, but a signal kept for a
        # commit the runs didn't report never applies, so name the commit and
        # how to signal another. The commit's own page is a 404 until one of
        # its runs is processed, so the commits list is linked instead.
        Mix.shell().info(
          "No run of commit #{String.slice(sha, 0, 7)}#{origin(options)} has reported coverage yet. " <>
            "That's expected while its runs are still being processed: the signal is kept, " <>
            "and the commit's coverage is marked complete once one is.\n" <>
            "  If your test runs reported another commit, signal that one with " <>
            "`mix tuist.coverage.complete --commit <sha>`\n" <>
            "  See the commits your runs reported coverage for at #{commits_url(options)}"
        )

      {:error, reason} ->
        Mix.raise(
          "Could not mark the coverage of commit #{String.slice(sha, 0, 7)} complete: #{inspect(reason)}"
        )
    end
  end

  defp origin(options) do
    cond do
      options[:commit] -> ""
      System.get_env("GIT_COMMIT") -> ", from GIT_COMMIT,"
      true -> ", the checkout's HEAD,"
    end
  end

  # The request that just succeeded resolved the same configuration.
  defp commits_url(options) do
    {:ok, %{url: url, project_handle: handle}} = Config.resolve(options)
    "#{url}/#{handle.account}/#{handle.project}/tests/coverage/commits"
  end
end
