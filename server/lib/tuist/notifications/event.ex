defmodule Tuist.Notifications.Event do
  @moduledoc """
  A kind of event users can be notified about, such as a preview being
  published. Each event module defines:

  - its identifier, title and description, which the REST and MCP APIs list;
  - the `Tuist.Authorization` action under the `:notification` object that
    decides who can subscribe to it for a project, checked when a rule is saved
    and again for each recipient when the event fires;
  - a JSON Schema for its conditions, `cast_conditions/1` to validate and
    normalize them, and `matches?/3` to evaluate them against an event;
  - `condition_options/1`, values a client can suggest for a project.

  To add an event type, add a module here, its `:notification` policy action,
  and a sender that calls `Tuist.Notifications.recipients/3` when it fires.
  """

  alias Tuist.Projects.Project

  @callback id() :: String.t()
  @callback title() :: String.t()
  @callback description() :: String.t()
  @callback authorization_action() :: atom()
  @callback conditions_schema() :: map()
  @callback cast_conditions(map()) :: {:ok, map()} | {:error, String.t()}
  @callback matches?(conditions :: map(), subject :: struct(), user_id :: integer()) :: boolean()
  @callback condition_options(Project.t()) :: map()

  @events [Tuist.Notifications.Events.PreviewPublished]

  def all, do: @events

  def get(id) when is_binary(id), do: Enum.find(@events, &(&1.id() == id))
  def get(_id), do: nil
end
