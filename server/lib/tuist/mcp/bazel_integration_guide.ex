defmodule Tuist.MCP.BazelIntegrationGuide do
  @moduledoc false

  @server_origin_regex ~r/\Ahttps?:\/\/(?:\[[0-9A-Fa-f:]+\]|[A-Za-z0-9._-]+)(?::\d{1,5})?\/?\z/

  def build(args \\ %{}) do
    account_handle = Map.get(args, "account_handle")
    project_handle = Map.get(args, "project_handle")

    project =
      if account_handle && project_handle,
        do: "`#{account_handle}/#{project_handle}`",
        else: "the Tuist project selected during setup"

    with {:ok, server_url} <- server_origin(args) do
      {:ok, render(project, server_url)}
    end
  end

  defp render(project, server_url) do
    """
    # Integrate an existing Bazel project with Tuist

    Connect #{project} to the Tuist server at `#{server_url}`. The goal is a normal `bazel build` that uses the Tuist remote cache and publishes build insights without wrapping or decorating the Bazel command.

    ## 1. Discover or create the Tuist project

    1. Call `list_accounts` and `list_projects` to identify an account and reuse a matching Bazel project when one exists.
    2. If needed, call `create_project` with `build_system=bazel`. Create an organization only when the user explicitly asks for one.
    3. Keep the full handle returned by the tool. It has the form `ACCOUNT_HANDLE/PROJECT_HANDLE`.

    ## 2. Complete both authentication layers

    [Model Context Protocol](https://modelcontextprotocol.io/) authentication authorizes this agent to call Tuist tools. It is not a credential for Bazel's remote cache or build-event service.

    If the Model Context Protocol connection is unauthenticated, follow the deployment-local `auth.md` document advertised by its `401 Unauthorized` response. Do not invent an email address, password, or token. Before starting a claim, ask the user to confirm the email address for their Tuist account.

    Verify command-line authentication against the same server URL:

    ```sh
    tuist auth whoami --url "#{server_url}"
    ```

    If that command is not authenticated, stop and ask the user to run:

    ```sh
    tuist auth login --url "#{server_url}"
    ```

    Do not reuse a Model Context Protocol token as a Bazel credential or continue to a verification build before command-line authentication succeeds. Keep the server origin identical everywhere, including the hostname spelling.

    ## 3. Bind the repository and configure Bazel

    First inspect the repository's existing Tuist configuration. When it does not have a `Tuist.swift` or legacy `Tuist/Config.swift` manifest, create or update `tuist.toml` at the repository root so it contains the Tuist project identity and server URL. This format works on both macOS and Linux:

    ```toml
    project = "ACCOUNT_HANDLE/PROJECT_HANDLE"
    url = "#{server_url}"
    ```

    Replace the handle with the project selected in step 1. On macOS, if the repository already has either Swift manifest, preserve it and set `fullHandle` and `url` on its existing `Tuist(...)` value instead of introducing a second source of truth. Linux does not load Swift manifests, so create or update `tuist.toml` there and keep its identity aligned with any tracked Swift manifest. Then run:

    ```sh
    tuist bazel setup
    ```

    This writes `.bazelrc.tuist`, installs a credential helper outside the repository, and normally adds `try-import %workspace%/.bazelrc.tuist` to `.bazelrc`. Use `--no-add-bazelrc-import` only when the user explicitly asks to manage the import manually.

    Read the setup takeaway and inspect `.bazelrc` before verification. Confirm that the exact `try-import` line is present and active. Setup can leave `.bazelrc` unchanged when it cannot identify the workspace, the file is a symbolic link, it already contains managed remote-service options, or the write fails. Add the import manually when it is safe. If existing `--remote_cache` or `--bes_backend` options conflict, do not combine configurations silently; explain the conflict and ask the user which service to keep.

    `.bazelrc.tuist` contains a machine-local credential-helper path. It must never be committed. Add it to `.gitignore` when it is not already ignored, and commit only the stable import in `.bazelrc`. Never copy an access token into either file.

    Build insights are enabled by default. Bazel's [Build Event Protocol](https://bazel.build/remote/bep) stream can include command-line arguments, environment values, and command output. If the user does not want to publish build insights, run `tuist bazel setup --no-build-insights` instead.

    ## 4. Prove the integration

    Choose the smallest meaningful existing target. When build insights are enabled, run it normally without `tuist bazel` or any command wrapper, while making this verification upload deterministic:

    ```sh
    bazel build --bes_upload_mode=wait_for_upload_complete TARGET
    ```

    The upload flag makes this verification run wait for the build-event upload; normal builds can use the generated default. Run the same target a second time after clearing only Bazel's local outputs when that is safe for the repository. Then inspect `list_bazel_invocations`, `get_bazel_invocation`, and `list_bazel_cache_events`. If the invocation is not visible immediately, poll `list_bazel_invocations` every few seconds for no more than 60 seconds before concluding that ingestion failed. Do not report success until the build succeeds, the invocation appears under the intended project, and the remote-cache observations show the expected reads or writes.

    When the user chose `--no-build-insights`, run `bazel build TARGET` without a build-event upload flag. No invocation is expected in Tuist. Verify only that the build succeeds and `list_bazel_cache_events` shows the expected remote-cache reads or writes. Never re-enable build insights merely because no invocation appears.

    For a failed `bazel build`, use the local Bazel output together with `get_bazel_invocation` for the command status and exit code. The invocation-log tools contain sanitized `test.log` artifacts, not general build output. For a failed `bazel test`, call `list_bazel_invocation_logs`, then use `get_bazel_invocation_log` when a specific test-log chunk needs closer inspection. Inspect the invocation and cache events before reporting the exact target, files changed, configuration endpoint, and cache outcome.
    """
  end

  defp server_origin(args) do
    case Map.fetch(args, "server_url") do
      :error ->
        {:ok, Tuist.Environment.app_url()}

      {:ok, nil} ->
        {:ok, Tuist.Environment.app_url()}

      {:ok, candidate} when is_binary(candidate) ->
        if String.trim(candidate) == "" do
          {:ok, Tuist.Environment.app_url()}
        else
          parse_server_origin(candidate)
        end

      {:ok, candidate} ->
        parse_server_origin(candidate)
    end
  end

  defp parse_server_origin(candidate) when is_binary(candidate) do
    trimmed_candidate = String.trim(candidate)

    case URI.new(trimmed_candidate) do
      {:ok,
       %URI{
         scheme: scheme,
         host: host,
         port: port,
         userinfo: nil,
         query: nil,
         fragment: nil,
         path: path
       }}
      when scheme in ["http", "https"] and is_binary(host) and host != "" and
             path in [nil, "", "/"] ->
        if Regex.match?(@server_origin_regex, trimmed_candidate) and valid_port?(port) do
          {:ok, String.trim_trailing(trimmed_candidate, "/")}
        else
          invalid_server_origin()
        end

      _ ->
        invalid_server_origin()
    end
  end

  defp parse_server_origin(_candidate), do: invalid_server_origin()

  defp valid_port?(nil), do: true
  defp valid_port?(port), do: port in 1..65_535

  defp invalid_server_origin do
    {:error, "server_url must be an HTTP or HTTPS origin without credentials, a path, query parameters, or a fragment."}
  end
end
