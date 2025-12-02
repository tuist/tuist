# Test script for manually triggering job execution
#
# Usage (run from server directory):
#   cd /Users/marekfort/Developer/tuist/server
#   GITHUB_TOKEN="your-pat" mix run runner/test_job.exs
#
# Required:
#   GITHUB_TOKEN            - GitHub PAT with admin:org or repo scope
#
# Optional environment variables:
#   GITHUB_ORG              - GitHub organization (default: "tuist")
#   GITHUB_REPO             - GitHub repository (default: nil for org-level runner)
#   RUNNER_LABELS           - Comma-separated labels (default: "self-hosted,macos,arm64")
#   RUNNER_WORK_DIR         - Working directory (default: /tmp/tuist-runner-test)
#   JOB_TIMEOUT_MS          - Job timeout in ms (default: 300000 = 5 minutes)
#
# The PAT needs these scopes:
#   - For org-level runner: admin:org
#   - For repo-level runner: repo (full control)

require Logger
Logger.configure(level: :info)

# Parse environment variables
github_token = System.get_env("GITHUB_TOKEN")

unless github_token do
  IO.puts(:stderr, """
  Error: GITHUB_TOKEN environment variable is required.

  You need a GitHub Personal Access Token (PAT) with:
    - For org-level runner: admin:org scope
    - For repo-level runner: repo scope

  Create one at: https://github.com/settings/tokens

  Then run:
    GITHUB_TOKEN="your-pat" mix run runner/test_job.exs
  """)
  System.halt(1)
end

github_org = System.get_env("GITHUB_ORG", "tuist")
github_repo = System.get_env("GITHUB_REPO")
labels = System.get_env("RUNNER_LABELS", "self-hosted,macos,arm64") |> String.split(",")
work_dir = System.get_env("RUNNER_WORK_DIR", "/tmp/tuist-runner-test")
timeout_ms = System.get_env("JOB_TIMEOUT_MS", "300000") |> String.to_integer()

job_config = %{
  job_id: "manual-test-#{:rand.uniform(100_000)}",
  github_org: github_org,
  github_repo: github_repo,
  labels: labels,
  registration_token: github_token,
  timeout_ms: timeout_ms
}

IO.puts("""
===========================================
  Tuist Runner - Manual Job Test
===========================================

Configuration:
  Job ID:          #{job_config.job_id}
  GitHub Org:      #{github_org}
  GitHub Repo:     #{github_repo || "(org-level runner)"}
  Labels:          #{Enum.join(labels, ", ")}
  Work Directory:  #{work_dir}
  Timeout:         #{div(timeout_ms, 1000)} seconds

Starting job execution...
This will:
  1. Register runner with GitHub (get JIT config)
  2. Download official runner binary (if not cached)
  3. Run official runner with --jitconfig
  4. Clean up

Press Ctrl+C to cancel.
===========================================
""")

case Runner.Runner.JobExecutor.execute(job_config, base_work_dir: work_dir) do
  {:ok, result} ->
    IO.puts("""

    ===========================================
      Job Completed!
    ===========================================
    Result:       #{result.result}
    Exit Code:    #{result.exit_code}
    Duration:     #{div(result.duration_ms, 1000)} seconds
    #{if result[:error], do: "Error:        #{inspect(result.error)}", else: ""}
    ===========================================
    """)

  {:error, reason} ->
    IO.puts(:stderr, """

    ===========================================
      Job Failed!
    ===========================================
    Error: #{inspect(reason)}
    ===========================================
    """)
    System.halt(1)
end
