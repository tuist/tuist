defmodule Atlas.Slack do
  @moduledoc """
  Context for the Atlas Slack app, tracked channels, user caches, and captured
  messages.

  Bot credentials live in env vars (see `Atlas.Slack.Bot`); only per-channel
  state, channel ownership, cached users, and message history are persisted.

  Tenancy-defining foreign keys (`slack_channel_id`, `slack_user_id`,
  `account_event_id`, `account_id`) are never set via `cast` on
  user-facing changesets — callers go through this module so the FKs
  are stamped on the struct directly.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Audit
  alias Atlas.Repo
  alias Atlas.Slack.API
  alias Atlas.Slack.Bot
  alias Atlas.Slack.Channel
  alias Atlas.Slack.Installation
  alias Atlas.Slack.Message
  alias Atlas.Slack.User

  require Logger

  # ----------------------------------------------------------------------
  # Installations
  # ----------------------------------------------------------------------

  def list_installations do
    Installation
    |> order_by([installation], asc: installation.app_key)
    |> Repo.all()
  end

  def get_installation(id) when is_binary(id), do: Repo.get(Installation, id)

  def find_installation_by_team_id(team_id) when is_binary(team_id) and team_id != "" do
    Installation
    |> where([installation], installation.team_id == ^team_id)
    |> Repo.one()
  end

  def find_installation_by_team_id(_team_id), do: nil

  # ----------------------------------------------------------------------
  # Channels
  # ----------------------------------------------------------------------

  @doc """
  Inserts a tracked channel. The optional `account_id` link FK is
  stamped on the struct (not cast) so it cannot be overridden via params.
  """
  def add_channel(attrs) do
    {account_id, attrs} = pop_string_or_atom(attrs, :account_id)
    {slack_app, attrs} = pop_string_or_atom(attrs, :slack_app)

    result =
      %Channel{
        account_id: blank_to_nil(account_id),
        slack_app: normalize_optional_app_key(slack_app)
      }
      |> Channel.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, channel} = success ->
        audit_channel("slack_channel.tracked", channel)
        success

      error ->
        error
    end
  end

  def delete_channel(id) do
    case Repo.get(Channel, id) do
      nil ->
        {:error, :not_found}

      channel ->
        case Repo.delete(channel) do
          {:ok, deleted} = success ->
            audit_channel("slack_channel.untracked", deleted)
            success

          error ->
            error
        end
    end
  end

  def list_channels do
    Channel
    |> order_by([c], asc: c.slack_app, asc: c.channel_name)
    |> Repo.all()
  end

  def list_channels(app_key) do
    slack_app = Bot.normalize_app_key!(app_key)

    Channel
    |> where([c], c.slack_app == ^slack_app)
    |> order_by([c], asc: c.channel_name)
    |> Repo.all()
  end

  def list_channels_for_account(%Account{id: account_id}) do
    Channel
    |> where([c], c.account_id == ^account_id)
    |> order_by([c], asc: c.slack_app, asc: c.channel_name)
    |> Repo.all()
  end

  def find_channel(app_key, channel_id) when is_binary(channel_id) do
    slack_app = Bot.normalize_app_key!(app_key)

    Channel
    |> where([c], c.slack_app == ^slack_app and c.channel_id == ^channel_id)
    |> Repo.one()
  end

  @doc """
  Looks up a channel by its human name (with or without the leading `#`).
  Returns the `Channel` struct or `nil` when the bot has never seen that
  channel. Useful for well-known channels (`customers`, `commercial`) that
  we address by name rather than a rotating ID.
  """
  def find_channel_by_name(app_key, name) when is_binary(name) do
    slack_app = Bot.normalize_app_key!(app_key)
    normalized = String.trim_leading(name, "#")

    Channel
    |> where([c], c.slack_app == ^slack_app and c.channel_name == ^normalized)
    |> Repo.one()
  end

  @doc """
  Updates the `account_id` foreign key on a channel using a dedicated
  changeset that does not call `cast`.
  """
  def update_channel_account(%Channel{} = channel, account_id) do
    channel
    |> Channel.account_changeset(blank_to_nil(account_id))
    |> Repo.update()
  end

  @doc """
  Lists every channel the bot can see, including Slack Connect
  (externally shared) channels. Falls back to channels already tracked
  in the database when the Slack API call fails (typical in dev when
  no token is configured).

  Each entry is a map shaped like:

      %{
        slack_app: :company,
        slack_channel_id: "C123",
        name: "support",
        is_shared: false,
        is_ext_shared: false
      }
  """
  def list_available_channels do
    Bot.app_keys()
    |> Enum.flat_map(&available_channels_for_app/1)
    |> Enum.sort_by(&{&1.name, Atom.to_string(&1.slack_app)})
  end

  defp available_channels_for_app(app_key) do
    case API.list_channels(app_key) do
      {:ok, channels} ->
        Enum.map(channels, &option_from_api/1)

      {:error, reason} ->
        Logger.debug("Slack list_channels failed for #{app_key} (#{inspect(reason)}); falling back to tracked channels")

        app_key
        |> list_channels()
        |> Enum.map(&option_from_record/1)
    end
  end

  defp option_from_api(channel) do
    %{
      slack_app: channel.slack_app,
      slack_channel_id: channel.slack_channel_id,
      name: channel.name,
      is_shared: channel.is_shared,
      is_ext_shared: channel.is_ext_shared
    }
  end

  defp option_from_record(channel) do
    %{
      slack_app: channel.slack_app,
      slack_channel_id: channel.channel_id,
      name: channel.channel_name,
      is_shared: channel.is_shared,
      is_ext_shared: channel.is_ext_shared
    }
  end

  @doc """
  Sets the Slack channel linked to the account. Pass `""` or `nil` to
  unlink any currently-linked channel.

  `value` is the Slack app plus channel id (e.g. `"company:C123"`). The
  matching `slack_channels` row is created if it does not already exist (e.g.
  the operator picked a channel that has been seen via
  `conversations.list` but never inserted by a prior event).
  """
  def set_account_channel(%Account{} = account, value, _available) when value in [nil, "", "_none"] do
    previous_channels = linked_channel_refs(account)

    account
    |> unlink_account_channels()
    |> record_account_channel_change(account, previous_channels)
  end

  def set_account_channel(%Account{} = account, channel_id, available_channels) when is_binary(channel_id) do
    case find_option(available_channels, channel_id) do
      nil ->
        {:error, :unknown_channel}

      option ->
        previous_channels = linked_channel_refs(account)

        account
        |> link_account_channel(option)
        |> record_account_channel_change(account, previous_channels)
    end
  end

  defp unlink_account_channels(account) do
    Repo.transaction(fn ->
      Enum.each(list_channels_for_account(account), fn channel ->
        case update_channel_account(channel, nil) do
          {:ok, _channel} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp link_account_channel(account, %{slack_app: slack_app, slack_channel_id: slack_channel_id} = option) do
    Repo.transaction(fn ->
      unlink_other_account_channels(account, slack_app, slack_channel_id)
      upsert_account_channel(account, option)
    end)
    |> case do
      {:ok, %Channel{}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp unlink_other_account_channels(account, slack_app, slack_channel_id) do
    for channel <- list_channels_for_account(account),
        channel.slack_app != slack_app or channel.channel_id != slack_channel_id do
      case update_channel_account(channel, nil) do
        {:ok, _channel} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end
  end

  defp upsert_account_channel(account, %{slack_app: slack_app, slack_channel_id: slack_channel_id} = option) do
    case Repo.get_by(Channel, slack_app: slack_app, channel_id: slack_channel_id) do
      nil -> insert_account_channel(account, option)
      existing -> update_account_channel(existing, account.id, option)
    end
    |> case do
      {:ok, channel} -> channel
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp record_account_channel_change(:ok, account, previous_channels) do
    channels = linked_channel_refs(account)

    if channels != previous_channels do
      Audit.record("account.slack_channel_changed", %{
        target_type: "account",
        target_id: account.id,
        target_label: account.name,
        metadata: %{
          "path" => "/commercial/sales/accounts/#{account.id}",
          "previous_channels" => previous_channels,
          "channels" => channels
        }
      })
    end

    :ok
  end

  defp record_account_channel_change(result, _account, _previous_channels), do: result

  defp linked_channel_refs(account) do
    account
    |> list_channels_for_account()
    |> Enum.map(fn channel ->
      %{
        "slack_app" => Atom.to_string(channel.slack_app),
        "slack_channel_id" => channel.channel_id
      }
    end)
  end

  defp insert_account_channel(account, option) do
    %Channel{account_id: account.id, slack_app: option.slack_app}
    |> Channel.changeset(%{
      channel_id: option.slack_channel_id,
      channel_name: option.name,
      is_shared: Map.get(option, :is_shared, false),
      is_ext_shared: Map.get(option, :is_ext_shared, false)
    })
    |> Repo.insert()
  end

  defp update_account_channel(channel, account_id, option) do
    channel
    |> Channel.changeset(%{
      channel_id: option.slack_channel_id,
      channel_name: option.name,
      is_shared: Map.get(option, :is_shared, channel.is_shared),
      is_ext_shared: Map.get(option, :is_ext_shared, channel.is_ext_shared)
    })
    |> Repo.update()
    |> case do
      {:ok, channel} -> update_channel_account(channel, account_id)
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp find_option(options, value) do
    {slack_app, channel_id} = parse_channel_value(value)

    Enum.find(options, fn option ->
      option.slack_channel_id == channel_id and option.slack_app == slack_app
    end)
  end

  defp parse_channel_value(value) do
    case String.split(value, ":", parts: 2) do
      [app_key, channel_id] ->
        case Bot.normalize_app_key(app_key) do
          {:ok, slack_app} -> {slack_app, channel_id}
          :error -> {nil, value}
        end

      [_channel_id] ->
        {nil, value}
    end
  end

  # ----------------------------------------------------------------------
  # Users
  # ----------------------------------------------------------------------

  @doc """
  Inserts or updates a `slack_users` row keyed by Slack app and
  `slack_user_id`.
  """
  def upsert_user(app_key, attrs) when is_map(attrs) do
    slack_app = Bot.normalize_app_key!(app_key)
    slack_user_id = Map.fetch!(attrs, :slack_user_id)
    attrs = Map.put(attrs, :last_synced_at, now())

    case Repo.get_by(User, slack_app: slack_app, slack_user_id: slack_user_id) do
      nil ->
        %User{slack_app: slack_app}
        |> User.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> User.changeset(attrs)
        |> Repo.update()
    end
  end

  def get_user(app_key, slack_user_id) when is_binary(slack_user_id) do
    slack_app = Bot.normalize_app_key!(app_key)

    Repo.get_by(User, slack_app: slack_app, slack_user_id: slack_user_id)
  end

  # ----------------------------------------------------------------------
  # Messages
  # ----------------------------------------------------------------------

  @doc """
  Inserts a Slack message for a channel. Tenancy FKs (`slack_channel_id`,
  `slack_user_id`, `account_event_id`) are stamped on the struct rather
  than cast from the attrs map.
  """
  def insert_message(%Channel{} = channel, slack_user, account_event, attrs) when is_map(attrs) do
    %Message{
      slack_channel_id: channel.id,
      slack_user_id: slack_user_id(slack_user),
      account_event_id: account_event_id(account_event)
    }
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  def get_message_by_ts(%Channel{id: channel_id}, slack_ts) when is_binary(slack_ts) do
    Repo.get_by(Message, slack_channel_id: channel_id, slack_ts: slack_ts)
  end

  def list_thread_replies(%Channel{id: channel_id}, thread_ts) when is_binary(thread_ts) do
    Message
    |> where(
      [m],
      m.slack_channel_id == ^channel_id and m.thread_ts == ^thread_ts and m.slack_ts != ^thread_ts
    )
    |> order_by([m], asc: m.posted_at)
    |> Repo.all()
    |> Repo.preload(:slack_user)
  end

  @doc """
  Returns a map of `account_event_id` to a list of Slack thread reply messages
  (with `:slack_user` preloaded), for the given list of account event ids.
  """
  def thread_replies_by_account_event(event_ids) when is_list(event_ids) do
    case event_ids do
      [] ->
        %{}

      _ ->
        parents =
          Message
          |> where([m], m.account_event_id in ^event_ids)
          |> select([m], {m.account_event_id, m.slack_channel_id, m.slack_ts})
          |> Repo.all()

        if parents == [] do
          %{}
        else
          parent_lookup =
            Map.new(parents, fn {event_id, channel_id, slack_ts} ->
              {{channel_id, slack_ts}, event_id}
            end)

          channel_ids = parents |> Enum.map(fn {_e, c, _t} -> c end) |> Enum.uniq()
          thread_tses = parents |> Enum.map(fn {_e, _c, t} -> t end) |> Enum.uniq()

          Message
          |> where([m], m.slack_channel_id in ^channel_ids)
          |> where([m], m.thread_ts in ^thread_tses)
          |> where([m], m.thread_ts != m.slack_ts)
          |> order_by([m], asc: m.posted_at)
          |> preload(:slack_user)
          |> Repo.all()
          |> Enum.group_by(fn reply ->
            Map.get(parent_lookup, {reply.slack_channel_id, reply.thread_ts})
          end)
          |> Map.delete(nil)
        end
    end
  end

  # ----------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------

  defp slack_user_id(nil), do: nil
  defp slack_user_id(%User{id: id}), do: id

  defp account_event_id(nil), do: nil
  defp account_event_id(%Event{id: id}), do: id

  defp audit_channel(action, %Channel{} = channel) do
    metadata = %{
      "slack_app" => Atom.to_string(channel.slack_app),
      "slack_channel_id" => channel.channel_id,
      "account_id" => channel.account_id,
      "is_shared" => channel.is_shared,
      "is_ext_shared" => channel.is_ext_shared
    }

    metadata =
      if channel.account_id do
        Map.put(metadata, "path", "/commercial/sales/accounts/#{channel.account_id}")
      else
        metadata
      end

    Audit.record(action, %{
      target_type: "slack_channel",
      target_id: channel.id,
      target_label: channel.channel_name,
      metadata: metadata
    })
  end

  defp pop_string_or_atom(map, key) when is_atom(key) do
    case Map.pop(map, key) do
      {nil, rest} -> Map.pop(rest, Atom.to_string(key), nil)
      {value, rest} -> {value, rest}
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp normalize_optional_app_key(nil), do: :company
  defp normalize_optional_app_key(app_key), do: Bot.normalize_app_key!(app_key)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
