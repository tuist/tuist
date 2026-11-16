defmodule Tuist.Threads.Repository do
  @moduledoc "Fresh, account-scoped GitHub repository authorization for Threads."

  alias Tuist.GitHub.App
  alias Tuist.GitHub.Client
  alias Tuist.Threads.Review
  alias Tuist.Threads.Workspace
  alias Tuist.VCS

  @protection_query """
  query($owner: String!, $name: String!) {
    repository(owner: $owner, name: $name) {
      branchProtectionRules(first: 100) { totalCount nodes { pattern } }
    }
  }
  """

  @update_refs """
  mutation($input: UpdateRefsInput!) {
    updateRefs(input: $input) { clientMutationId }
  }
  """

  def list(account) do
    with {:ok, installation} <- installation(account),
         {:ok, repositories} <- pages(installation, [], [], 0) do
      {:ok, Enum.filter(repositories, &valid_repository?/1)}
    else
      _ -> {:error, :repositories_unavailable}
    end
  end

  def authorize(account, name) when is_binary(name) do
    with true <- valid_name?(name),
         {:ok, repositories} <- list(account),
         repository when not is_nil(repository) <-
           Enum.find(repositories, &(String.downcase(&1.full_name) == String.downcase(name))) do
      {:ok, %{name: repository.full_name, default_branch: repository.default_branch}}
    else
      _ -> {:error, :repository_not_authorized}
    end
  end

  def authorize(_, _), do: {:error, :repository_not_authorized}

  # Tokens never enter a remote URL, local git config, a tool result or a log.
  def environment(account, repository, :read) do
    with {:ok, authorized} <- authorize(account, repository),
         {:ok, installation} <- installation(account),
         [_owner, name] <- String.split(authorized.name, "/"),
         {:ok, %{token: token}} <-
           App.create_scoped_installation_token(installation, [name], %{"contents" => "read"}) do
      header = "AUTHORIZATION: basic " <> Base.encode64("x-access-token:#{token}")

      {:ok,
       %{
         "GIT_CONFIG_COUNT" => "3",
         "GIT_CONFIG_KEY_0" => "http.https://github.com/.extraheader",
         "GIT_CONFIG_VALUE_0" => header,
         "GIT_CONFIG_KEY_1" => "credential.helper",
         "GIT_CONFIG_VALUE_1" => "",
         "GIT_CONFIG_KEY_2" => "http.followRedirects",
         "GIT_CONFIG_VALUE_2" => "false",
         "GIT_TERMINAL_PROMPT" => "0"
       }}
    else
      _ -> {:error, :repository_credentials_unavailable}
    end
  end

  def environment(_, _, _), do: {:error, :write_credentials_server_only}

  def review(account, snapshot, objects) do
    with {:ok, repository} <- authorize(account, snapshot.repository),
         true <- repository.name == snapshot.repository,
         {:ok, installation} <- installation(account),
         [_owner, name] <- String.split(repository.name, "/"),
         {:ok, %{token: token}} <- App.create_scoped_installation_token(installation, [name], %{"contents" => "read"}) do
      Review.diff(snapshot, objects, fn path ->
        case api(:get, snapshot, path, token) do
          {:ok, 200, body} -> {:ok, body}
          _ -> {:error, :shipping_review_unavailable}
        end
      end)
    else
      _ -> {:error, :shipping_review_unavailable}
    end
  end

  @doc "Read-only positive reconciliation; absence is not proof of no in-flight effect."
  def reconcile(account, approval) do
    with {:ok, repository} <- authorize(account, approval.repository),
         true <- repository.name == approval.repository,
         {:ok, installation} <- installation(account),
         [_owner, name] <- String.split(repository.name, "/"),
         {:ok, %{token: token}} <- App.create_scoped_installation_token(installation, [name], %{"contents" => "read"}),
         {:ok, head} <- remote_head(approval, token),
         true <- head == approval.head_sha do
      :ok
    else
      _ -> {:error, :shipping_uncertain}
    end
  end

  @doc "Server-only Git object broker. The export callback never receives a token."
  def ship(account, approval, export, fence) do
    with :ok <- fence.(),
         {:ok, repository} <- authorize(account, approval.repository),
         true <- repository.name == approval.repository,
         {:ok, installation} <- installation(account),
         [_owner, name] <- String.split(repository.name, "/"),
         {:ok, %{token: token}} <- App.create_scoped_installation_token(installation, [name], %{"contents" => "write"}),
         {:ok, remote} <- remote_head(approval, token) do
      cond do
        remote == approval.head_sha ->
          :ok

        not expected_remote?(approval, remote) ->
          {:error, :shipping_base_changed}

        true ->
          publish(account, approval, export, remote, token, fence)
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :shipping_unavailable}
    end
  end

  defp publish(account, approval, export, remote, token, fence) do
    with :ok <- shipping_policy(account, approval.repository, approval.target_branch),
         {:ok, objects} <- export.(),
         :ok <- upload_commit(approval, objects, token) do
      # A ref write may succeed even when its response is lost. Never
      # repeat a write before observing the immutable reviewed head.
      case update_ref(approval, remote, token, fence) do
        {:error, :stale_run} = error ->
          error

        _ ->
          case remote_head(approval, token) do
            {:ok, head} when head == approval.head_sha -> :ok
            _ -> {:error, :shipping_uncertain}
          end
      end
    end
  end

  defp upload_commit(approval, %{"tree_sha" => tree, "entries" => entries}, token)
       when is_list(entries) and length(entries) in 1..200 do
    with true <- Workspace.sha?(tree),
         true <- Enum.all?(entries, &valid_entry?/1),
         true <- Enum.sum(Enum.map(entries, &byte_size(&1["content"] || ""))) <= 700_000,
         :ok <- upload_blobs(approval, entries, token),
         {:ok, 200, %{"tree" => %{"sha" => base_tree}}} <- api(:get, approval, "/git/commits/#{approval.base_sha}", token),
         {:ok, 201, %{"sha" => ^tree}} <-
           api(:post, approval, "/git/trees", token, %{
             base_tree: base_tree,
             tree: Enum.map(entries, &Map.take(&1, ~w(path mode type sha)))
           }),
         identity = %{name: "Tuist Threads", email: "threads@tuist.dev", date: "2000-01-01T00:00:00Z"},
         {:ok, 201, %{"sha" => head}} <-
           api(:post, approval, "/git/commits", token, %{
             message: "Tuist Threads #{approval.thread_id}\n",
             tree: tree,
             parents: [approval.base_sha],
             author: identity,
             committer: identity
           }),
         true <- head == approval.head_sha do
      :ok
    else
      _ -> {:error, :shipping_objects_invalid}
    end
  end

  defp upload_commit(_, _, _), do: {:error, :shipping_objects_invalid}

  defp upload_blobs(approval, entries, token) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      if is_nil(entry["sha"]) do
        {:cont, :ok}
      else
        expected = entry["sha"]

        case api(:post, approval, "/git/blobs", token, %{content: entry["content"], encoding: "base64"}) do
          {:ok, 201, %{"sha" => ^expected}} -> {:cont, :ok}
          _ -> {:halt, {:error, :shipping_objects_invalid}}
        end
      end
    end)
  end

  defp valid_entry?(%{"path" => path, "mode" => mode, "type" => "blob", "sha" => sha} = entry) do
    is_binary(path) and byte_size(path) in 1..4096 and
      not String.contains?(path, <<0>>) and
      Enum.all?(String.split(path, "/"), &(&1 not in ["", ".", "..", ".git"])) and
      mode in ["100644", "100755", "120000"] and
      ((is_nil(sha) and is_nil(entry["content"])) or valid_blob?(sha, entry["content"]))
  end

  defp valid_entry?(_), do: false

  defp valid_blob?(sha, content) when is_binary(content) and byte_size(content) <= 700_000 do
    with true <- Workspace.sha?(sha), {:ok, bytes} <- Base.decode64(content) do
      Base.encode16(:crypto.hash(:sha, ["blob #{byte_size(bytes)}", <<0>>, bytes]), case: :lower) == sha
    else
      _ -> false
    end
  end

  defp valid_blob?(_, _), do: false

  defp remote_head(approval, token) do
    case api(:get, approval, "/git/ref/heads/#{URI.encode_www_form(approval.target_branch)}", token) do
      {:ok, 200, %{"object" => %{"sha" => sha}}} ->
        if Workspace.sha?(sha), do: {:ok, sha}, else: {:error, :shipping_uncertain}

      {:ok, 404, _} ->
        {:ok, nil}

      _ ->
        {:error, :shipping_uncertain}
    end
  end

  defp update_ref(approval, remote, token, fence) do
    # GitHub's atomic updateRefs beforeOid is a real compare-and-swap, including
    # all-zero beforeOid for creation. force:false independently forbids history
    # rewrites. REST update-ref has no expected-head precondition.
    with {:ok, 200, %{"node_id" => repository_id}} <- api(:get, approval, "", token),
         input = %{
           repositoryId: repository_id,
           refUpdates: [
             %{
               name: "refs/heads/#{approval.target_branch}",
               beforeOid: remote || String.duplicate("0", 40),
               afterOid: approval.head_sha,
               force: false
             }
           ]
         },
         :ok <- fence.(),
         {:ok, %{status: 200, body: body}} <-
           Req.post(
             url: "https://api.github.com/graphql",
             headers: [{"authorization", "Bearer #{token}"}],
             json: %{query: @update_refs, variables: %{input: input}},
             redirect: false,
             retry: false,
             receive_timeout: 15_000
           ) do
      # GraphQL errors can follow a partially completed operation. Only the
      # subsequent observation of the approved head establishes publication.
      if Map.has_key?(body, "errors"), do: {:error, :shipping_uncertain}, else: :ok
    else
      {:error, :stale_run} = error -> error
      _ -> {:error, :shipping_uncertain}
    end
  end

  defp expected_remote?(%{mode: :branch}, nil), do: true
  defp expected_remote?(approval, remote), do: remote == approval.base_sha

  defp api(method, approval, path, token, body \\ nil) do
    opts = [
      method: method,
      url: "https://api.github.com/repos/#{approval.repository}" <> path,
      headers: [{"authorization", "Bearer #{token}"}, {"accept", "application/vnd.github+json"}],
      redirect: false,
      retry: false,
      compressed: false,
      into: &bounded_body/2,
      receive_timeout: 15_000
    ]

    opts = if is_nil(body), do: opts, else: Keyword.put(opts, :json, body)

    case Req.request(opts) do
      {:ok, %{status: status, body: body}} -> {:ok, status, body}
      _ -> {:error, :github_unavailable}
    end
  end

  defp bounded_body({:data, chunk}, {request, response}) do
    body = response.body || ""

    if byte_size(body) + byte_size(chunk) <= 8_388_608,
      do: {:cont, {request, %{response | body: body <> chunk}}},
      else: {:halt, {request, %{response | status: 413, body: ""}}}
  end

  @doc "Fail closed on unknown policy, including Apps configured to bypass PR rules."
  def shipping_policy(account, repository, branch) do
    with {:ok, authorized} <- authorize(account, repository),
         {:ok, installation} <- installation(account),
         [owner, name] <- String.split(authorized.name, "/"),
         {:ok, %{token: token}} <- App.create_scoped_installation_token(installation, [name], %{"contents" => "read"}),
         {:ok, %{status: 200, body: rules}} when is_list(rules) <-
           Req.get(
             url: "https://api.github.com/repos/#{authorized.name}/rules/branches/#{URI.encode_www_form(branch)}",
             headers: [{"authorization", "Bearer #{token}"}, {"accept", "application/vnd.github+json"}],
             redirect: false,
             retry: false
           ),
         {:ok, %{status: 200, body: %{"data" => %{"repository" => %{"branchProtectionRules" => classic}}}}} <-
           Req.post(
             url: "https://api.github.com/graphql",
             headers: [{"authorization", "Bearer #{token}"}],
             json: %{query: @protection_query, variables: %{owner: owner, name: name}},
             redirect: false,
             retry: false
           ),
         %{"totalCount" => count, "nodes" => patterns} when is_integer(count) and count <= 100 and is_list(patterns) <-
           classic,
         true <- length(patterns) == count do
      # Installation actors may be configured as bypass actors. Conservatively
      # refuse every applicable protection, not just PR rules, rather than let
      # an App bypass a gate a normal user would have had to satisfy.
      cond do
        Enum.any?(rules, &(&1["type"] == "pull_request")) -> {:error, :pull_request_required}
        rules != [] or Enum.any?(patterns, &protected_pattern?(&1["pattern"], branch)) -> {:error, :protected_branch}
        true -> :ok
      end
    else
      _ -> {:error, :shipping_policy_unavailable}
    end
  end

  defp installation(account) do
    with {:ok, installation} <- VCS.get_github_app_installation_for_account(account.id),
         true <- installation.client_url in [nil, "https://github.com", "https://github.com/"] do
      {:ok, installation}
    else
      _ -> {:error, :github_installation_unavailable}
    end
  end

  defp pages(_installation, _opts, _repositories, 100), do: {:error, :repository_catalog_too_large}

  defp pages(installation, opts, repositories, page) do
    case Client.list_installation_repositories(installation, opts) do
      {:ok, %{repositories: batch, meta: %{next_url: nil}}} ->
        {:ok, repositories ++ batch}

      {:ok, %{repositories: batch, meta: %{next_url: next}}} ->
        pages(installation, [next_url: next], repositories ++ batch, page + 1)

      _ ->
        {:error, :repositories_unavailable}
    end
  end

  defp valid_repository?(repository),
    do:
      valid_name?(repository.full_name) and is_binary(repository.default_branch) and
        byte_size(repository.default_branch) in 1..255

  defp valid_name?(name),
    do:
      is_binary(name) and byte_size(name) <= 201 and
        Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9][A-Za-z0-9_.-]*\z/, name)

  defp protected_pattern?(pattern, branch) when is_binary(pattern) do
    # Overmatch unsupported glob constructs rather than miss a protection.
    if String.contains?(pattern, ["[", "]", "\\"]) do
      true
    else
      regex = pattern |> Regex.escape() |> String.replace("\\*", ".*") |> String.replace("\\?", ".")
      Regex.match?(Regex.compile!("\\A" <> regex <> "\\z"), branch)
    end
  end

  defp protected_pattern?(_, _), do: true
end
