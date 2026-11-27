defmodule LuftServer.Prompts do
  @moduledoc "Organization-owned saved prompts. Tuist supplies membership, never prompt storage."

  import Ecto.Query

  alias LuftServer.Audit
  alias LuftServer.Prompts.Prompt
  alias LuftServer.Repo

  @defaults [
    {"ship", "Ship",
     "Prepare these changes for Ship. Inspect the diff, run the relevant checks and summarize what will be published and any remaining risks. Use Luft's reviewed Ship flow for publication; this prompt does not approve a commit, push, merge, pull request or deployment."},
    {"review", "Review",
     "Review this thread's changes for correctness, security and regressions. Read the relevant code and tests. Report actionable findings with file locations and explain their impact. Do not change code unless I ask."},
    {"update-base", "Rebase",
     "Update this thread's work onto the latest target branch. Inspect the working tree first, preserve unrelated changes and resolve conflicts without dropping intended behavior. Run the relevant checks and report any unresolved conflicts. Do not rewrite published history or publish changes."},
    {"refactor-commits", "Restack",
     "Inspect this thread's diff and propose logical, independently reviewable commits without changing behavior. Explain the proposed boundaries. Leave commit creation and publication to Luft's reviewed Ship flow."},
    {"summarize", "Summarize",
     "Summarize what this thread addresses, why it matters and how the changes address it. State the checks actually run, any remaining blockers and whether the work is local or published. Keep it to a few sentences."}
  ]

  def list(organization_id) when is_integer(organization_id) do
    ensure_defaults(organization_id)
    Repo.all(from p in Prompt, where: p.organization_id == ^organization_id, order_by: p.name)
  end

  def get(organization_id, name) when is_integer(organization_id) do
    ensure_defaults(organization_id)
    Repo.get_by(Prompt, organization_id: organization_id, name: name)
  end

  def standard?(name), do: Enum.any?(@defaults, &(elem(&1, 0) == name))

  def put(actor, organization_id, name, attrs) do
    if is_binary(name) and Regex.match?(~r/\A[a-z][a-z0-9-]{0,63}\z/, name) do
      transaction(organization_id, fn ->
        prompt =
          get(organization_id, name) || %Prompt{organization_id: organization_id, name: name}

        case prompt
             |> Prompt.changeset(Map.take(attrs, ~w(title body)))
             |> Repo.insert_or_update(log: false) do
          {:ok, saved} ->
            record!(actor, "prompt.saved", saved)
            saved

          {:error, _changeset} ->
            Repo.rollback(:invalid_prompt)
        end
      end)
    else
      {:error, :invalid_prompt}
    end
  end

  # Removing a standard prompt restores its original text; it remains available.
  def delete(actor, organization_id, name) do
    transaction(organization_id, fn ->
      if prompt = get(organization_id, name) do
        case Enum.find(@defaults, &(elem(&1, 0) == name)) do
          {_, title, body} ->
            saved =
              prompt |> Prompt.changeset(%{title: title, body: body}) |> Repo.update!(log: false)

            record!(actor, "prompt.reset", saved)

          nil ->
            Repo.delete!(prompt, log: false)
            record!(actor, "prompt.deleted", prompt)
        end
      end

      :ok
    end)
  end

  @doc "Expands a leading /name once; the message retains both the input and resolved text."
  def expand(organization_id, input) when is_integer(organization_id) do
    case Regex.run(~r/\A\/([a-z][a-z0-9-]{0,63})(?:\s+([\s\S]*))?\z/, input) do
      [_, name | tail] ->
        case get(organization_id, name) do
          nil ->
            {:ok, input, nil}

          prompt ->
            extra = tail |> List.first("") |> String.trim()
            body = prompt.body <> if(extra == "", do: "", else: "\n\n" <> extra)

            if byte_size(body) <= 16_000,
              do: {:ok, body, %{"name" => name, "input" => input}},
              else: {:error, :invalid_arguments}
        end

      _ ->
        {:ok, input, nil}
    end
  end

  def expand(_personal, input), do: {:ok, input, nil}

  defp ensure_defaults(organization_id) do
    now = DateTime.utc_now(:second)

    rows =
      Enum.map(@defaults, fn {name, title, body} ->
        %{
          id: Ecto.UUID.generate(),
          organization_id: organization_id,
          name: name,
          title: title,
          body: body,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(Prompt, rows,
      on_conflict: :nothing,
      conflict_target: [:organization_id, :name],
      log: false
    )
  end

  defp transaction(organization_id, fun) do
    Repo.transaction(fn ->
      Repo.query!(
        "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
        ["organization-prompts:#{organization_id}"],
        log: false
      )

      fun.()
    end)
  end

  defp record!(actor, action, prompt),
    do:
      Audit.record!(actor, action, "organization:#{prompt.organization_id}", prompt.id, %{
        "name" => prompt.name
      })
end
