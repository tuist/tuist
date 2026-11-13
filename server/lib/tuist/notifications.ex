defmodule Tuist.Notifications do
  @moduledoc """
  A user's own notification rules, independent of how notifications are
  delivered. A rule says: when an event (`Tuist.Notifications.Event`, today
  only `preview_published`) happens in one of the rule's projects, or in any
  project the user can subscribe to when it lists none, and the event meets the
  rule's conditions, run its actions (`Tuist.Notifications.Action`, today only
  `push`). A user with no rules gets no notifications.

  Who can subscribe to an event for a project is decided by the event's
  `:notification` policy in `Tuist.Authorization`. It is checked when a rule is
  saved and again for each recipient when the event fires, so a user who leaves
  an organization stops getting its notifications even though their rules stay.

  Rules are private to their user. The REST API (`/api/me/notification-rules`)
  and the MCP tools act only for the authenticated user.

  Transactional email (sign-in, security, invitations, billing; see
  `Tuist.Accounts.UserNotifier`) is never governed by these rules.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.Role
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserRole
  alias Tuist.Authorization
  alias Tuist.Notifications.Action
  alias Tuist.Notifications.Event
  alias Tuist.Notifications.Rule
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Repo

  @max_rules_per_user 100
  @max_projects_per_rule 100

  def max_rules_per_user, do: @max_rules_per_user
  def max_projects_per_rule, do: @max_projects_per_rule

  @doc "The event types rules can subscribe to."
  def events, do: Event.all()

  @doc "The action types rules can run."
  def action_types, do: Action.types()

  @doc "`user`'s rules, oldest first, with their projects and accounts loaded."
  def list_rules(%User{id: user_id}) do
    Rule
    |> where([r], r.user_id == ^user_id)
    |> order_by([r], asc: r.inserted_at, asc: r.id)
    |> preload(projects: :account)
    |> Repo.all()
  end

  @doc "One of `user`'s rules, or `{:error, :not_found}`."
  def get_rule(%User{id: user_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Rule{} = rule <- Rule |> where([r], r.id == ^id and r.user_id == ^user_id) |> Repo.one() do
      {:ok, Repo.preload(rule, projects: :account)}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Creates a rule for `user` from `attrs`: `event`, `conditions`, `actions`,
  optional `enabled`, and `projects`, a list of `account/project` handles (empty
  or missing for any project). Each project must be one the user can subscribe
  to for the event.

  Returns `{:ok, rule}`, `{:error, %Ecto.Changeset{}}`, `{:error, {:invalid, message}}`
  or `{:error, :limit_reached}`.
  """
  def create_rule(%User{id: user_id} = user, attrs) when is_map(attrs) do
    attrs = stringify(attrs)

    with :ok <- check_rule_limit(user_id),
         {:ok, projects} <- authorized_projects(user, attrs["event"], Map.get(attrs, "projects", [])) do
      %Rule{user_id: user_id}
      |> Rule.changeset(attrs, projects)
      |> Repo.insert()
      |> preload_result()
    end
  end

  @doc """
  Updates `rule` with the given fields of `attrs`. The event can't change.
  Passing `projects` replaces the rule's projects. Returns what `create_rule/2` does.
  """
  def update_rule(%User{id: user_id} = user, %Rule{user_id: user_id} = rule, attrs) when is_map(attrs) do
    attrs = attrs |> stringify() |> Map.delete("event")
    rule = Repo.preload(rule, projects: :account)

    projects =
      case Map.fetch(attrs, "projects") do
        {:ok, handles} -> authorized_projects(user, rule.event, handles)
        :error -> {:ok, rule.projects}
      end

    with {:ok, projects} <- projects do
      rule
      |> Rule.changeset(attrs, projects)
      |> Repo.update()
      |> preload_result()
    end
  end

  @doc "Deletes one of `user`'s rules."
  def delete_rule(%User{id: user_id}, %Rule{user_id: user_id} = rule) do
    {:ok, _rule} = Repo.delete(rule)
    :ok
  end

  @doc """
  The JSON representation of `rule` that the REST and MCP APIs return, with
  string keys. Its projects must be loaded with their accounts.
  """
  def rule_to_map(%Rule{} = rule) do
    %{
      "id" => rule.id,
      "event" => rule.event,
      "enabled" => rule.enabled,
      "projects" => rule.projects |> Enum.map(&"#{&1.account.name}/#{&1.name}") |> Enum.sort(),
      "conditions" => rule.conditions,
      "actions" => rule.actions,
      "inserted_at" => DateTime.to_iso8601(rule.inserted_at),
      "updated_at" => DateTime.to_iso8601(rule.updated_at)
    }
  end

  @doc "The JSON representation of an event type, for listing."
  def event_to_map(event) do
    %{
      "id" => event.id(),
      "title" => event.title(),
      "description" => event.description(),
      "conditions_schema" => event.conditions_schema()
    }
  end

  @doc "A sentence describing why `create_rule/2` or `update_rule/3` failed."
  def error_message(:limit_reached), do: "You can have at most #{@max_rules_per_user} notification rules."
  def error_message({:invalid, message}), do: message

  def error_message(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc -> String.replace(acc, "%{#{key}}", to_string(value)) end)
    end)
    |> Enum.flat_map(fn {field, messages} -> Enum.map(List.wrap(messages), &"#{field} #{&1}") end)
    |> Enum.join("; ")
  end

  @doc """
  Values a client can suggest for `event_id`'s conditions on `project`, or
  `{:error, :not_found}` when the event is unknown or the user can't subscribe
  to it for the project.
  """
  def condition_options(%User{} = user, event_id, %Project{} = project) do
    with event when not is_nil(event) <- Event.get(event_id),
         :ok <- Authorization.authorize(event.authorization_action(), user, project) do
      {:ok, event.condition_options(project)}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Who to notify about `subject`, an `event` that happened in `project`: one
  `{user_id, action_types}` entry for each user with an enabled rule for the
  event that covers the project, meets `subject`, and who may subscribe to the
  event for the project right now. `action_types` is the union of their
  matching rules' action types, so several matching rules notify once.
  """
  def recipients(event, %Project{} = project, subject) do
    project = Repo.preload(project, :account)
    event_id = event.id()
    project_id = project.id

    rules =
      Rule
      |> from(as: :rule)
      |> where([r], r.user_id in ^member_ids(project.account) and r.event == ^event_id and r.enabled)
      |> where(
        [r],
        not exists(from(rp in "notification_rule_projects", where: rp.rule_id == parent_as(:rule).id, select: 1)) or
          exists(
            from(rp in "notification_rule_projects",
              where: rp.rule_id == parent_as(:rule).id and rp.project_id == ^project_id,
              select: 1
            )
          )
      )
      |> Repo.all()

    users = User |> where([u], u.id in ^Enum.map(rules, & &1.user_id)) |> Repo.all() |> Map.new(&{&1.id, &1})

    rules
    |> Enum.group_by(& &1.user_id)
    |> Enum.filter(fn {user_id, _rules} ->
      Authorization.authorize(event.authorization_action(), Map.fetch!(users, user_id), project) == :ok
    end)
    |> Enum.flat_map(fn {user_id, rules} ->
      action_types =
        rules
        |> Enum.filter(&event.matches?(&1.conditions, subject, user_id))
        |> Enum.flat_map(fn rule -> Enum.map(rule.actions, & &1["type"]) end)
        |> Enum.uniq()

      if action_types == [], do: [], else: [{user_id, action_types}]
    end)
    |> Enum.sort()
  end

  defp member_ids(%Account{user_id: user_id}) when is_integer(user_id), do: [user_id]

  defp member_ids(%Account{organization_id: organization_id}) do
    UserRole
    |> join(:inner, [ur], r in Role, on: ur.role_id == r.id)
    |> where([_ur, r], r.resource_type == "Organization" and r.resource_id == ^organization_id)
    |> distinct(true)
    |> select([ur], ur.user_id)
    |> Repo.all()
  end

  defp check_rule_limit(user_id) do
    count = Rule |> where([r], r.user_id == ^user_id) |> Repo.aggregate(:count)
    if count < @max_rules_per_user, do: :ok, else: {:error, :limit_reached}
  end

  defp authorized_projects(_user, _event_id, nil), do: {:ok, []}

  defp authorized_projects(user, event_id, handles) when is_list(handles) do
    cond do
      length(handles) > @max_projects_per_rule ->
        {:error, {:invalid, "A rule can list at most #{@max_projects_per_rule} projects."}}

      not Enum.all?(handles, &is_binary/1) ->
        {:error, {:invalid, "Projects must be account/project handles."}}

      true ->
        event = Event.get(event_id)

        handles
        |> Enum.uniq()
        |> Enum.reduce_while({:ok, []}, fn handle, {:ok, acc} ->
          case authorized_project(user, event, handle) do
            {:ok, project} -> {:cont, {:ok, acc ++ [project]}}
            :error -> {:halt, {:error, {:invalid, "#{handle} isn't a project you can get these notifications for."}}}
          end
        end)
    end
  end

  defp authorized_projects(_user, _event_id, _handles), do: {:error, {:invalid, "Projects must be a list."}}

  # An unknown event fails later in the changeset; without one, no project can be authorized.
  defp authorized_project(_user, nil, _handle), do: :error

  defp authorized_project(user, event, handle) do
    with {:ok, project} <- Projects.get_project_by_slug(handle),
         :ok <- Authorization.authorize(event.authorization_action(), user, project) do
      {:ok, project}
    else
      _ -> :error
    end
  end

  defp preload_result({:ok, rule}), do: {:ok, Repo.preload(rule, [projects: :account], force: true)}
  defp preload_result(error), do: error

  defp stringify(attrs), do: Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
end
