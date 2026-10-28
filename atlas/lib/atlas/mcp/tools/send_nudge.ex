defmodule Atlas.MCP.Tools.SendNudge do
  @moduledoc """
  Queues the drafted email for a claimed nudge via
  `Atlas.GTM.DirectEmails` and transitions the nudge to `sent`.
  """

  use Atlas.MCP.Tool,
    name: "send_nudge",
    schema: %{
      "type" => "object",
      "required" => ["nudge_id"],
      "properties" => %{"nudge_id" => %{"type" => "string"}}
    },
    output_schema: Atlas.MCP.Serializers.Nudges.nudge_schema()

  alias Atlas.MCP.Serializers.Nudges, as: NudgeSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Nudges
  alias Atlas.Users.User

  @impl EMCP.Tool
  def description do
    "Queue the drafted email for a claimed nudge and transition it to sent. Only the claimant, or an operator with the admin:write scope, may call this."
  end

  def execute(conn, %{"nudge_id" => nudge_id}) when is_binary(nudge_id) do
    with :ok <- Tool.authorize_scope(conn, "accounts:write", "Nudge tools"),
         %User{} = actor <- Tool.current_user(conn),
         {:ok, nudge} <- Nudges.send(nudge_id, actor) do
      {:ok, NudgeSerializer.nudge(nudge)}
    else
      nil ->
        {:error, "MCP user could not be resolved."}

      {:error, :not_found} ->
        {:error, "Nudge not found: #{nudge_id}"}

      {:error, :not_authorized} ->
        {:error, "You must be the claimant or hold admin:write to send this nudge."}

      {:error, {:invalid_state, state}} ->
        {:error, "Nudge is in state #{state}; only claimed nudges can be sent."}

      {:error, :contact_missing} ->
        {:error, "This nudge has no contact. Add or edit a contact on the account first."}

      {:error, :contact_email_missing} ->
        {:error, "The nudge's contact has no email address."}

      {:error, :contact_bounced} ->
        {:error, "The nudge's contact is marked as bounced."}

      {:error, :contact_opted_out} ->
        {:error, "The nudge's contact has opted out of outreach."}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, Tool.format_changeset_errors(changeset)}

      {:error, reason} ->
        {:error, "Could not send the nudge: #{inspect(reason)}"}
    end
  end

  def execute(_conn, _args), do: {:error, "nudge_id is required."}
end
