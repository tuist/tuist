defmodule TuistWeb.OpsKuraComponents do
  @moduledoc """
  Shared pieces of the Kura rollout ops views: the rollout facts grid,
  the operator controls, and the waves/events/history tables. The index
  shows the latest rollout with recent items; the history and detail
  pages paginate the full sets with the same markup.
  """
  use TuistWeb, :html
  use Noora

  alias Tuist.Kura.Rollouts

  @doc """
  Dispatches an operator verb from a LiveView `operate` event. Returns
  the verb result; unknown actions error rather than defaulting.
  """
  def operate(nil, _action, _actor, _reason), do: {:error, :no_rollout}

  def operate(_rollout, action, _actor, _reason) when action in [nil, ""] do
    {:error, :no_action_selected}
  end

  def operate(rollout, action, actor, reason) do
    case action do
      "pause" -> Rollouts.pause(rollout, actor, reason)
      "resume" -> Rollouts.resume(rollout, actor, reason)
      "expedite" -> Rollouts.expedite(rollout, actor, reason)
      "abort" -> Rollouts.abort(rollout, actor, reason)
      _ -> {:error, :unknown_action}
    end
  end

  attr :rollout, :map, required: true

  def rollout_facts(assigns) do
    ~H"""
    <dl data-part="rollout-facts">
      <div data-part="fact">
        <dt>Status</dt>
        <dd>{@rollout.status}</dd>
      </div>
      <div data-part="fact">
        <dt>Mode</dt>
        <dd>{@rollout.mode}</dd>
      </div>
      <div data-part="fact">
        <dt>Wave</dt>
        <dd>{@rollout.current_wave}</dd>
      </div>
      <div data-part="fact">
        <dt>Baseline</dt>
        <dd>{@rollout.baseline_image_tag || "none"}</dd>
      </div>
      <div data-part="fact">
        <dt>Wave started</dt>
        <dd>{@rollout.wave_started_at || "-"}</dd>
      </div>
      <div data-part="fact">
        <dt>Healthy since</dt>
        <dd>{@rollout.wave_healthy_since || "-"}</dd>
      </div>
      <div :if={@rollout.status == :paused} data-part="fact">
        <dt>Paused</dt>
        <dd>{@rollout.paused_at} ({@rollout.pause_reason})</dd>
      </div>
      <div data-part="fact">
        <dt>Created</dt>
        <dd>{@rollout.inserted_at}</dd>
      </div>
    </dl>
    """
  end

  attr :rollout, :map, required: true

  def rollout_controls(assigns) do
    ~H"""
    <form phx-submit="operate" data-part="rollout-controls">
      <div data-part="reason-field">
        <.text_input
          id="reason"
          name="reason"
          label="Reason"
          placeholder="Recorded on the rollout's audit trail"
          required
          show_required
        />
      </div>
      <div class="select-field">
        <.label label="Action" required />
        <%!-- The id carries the status so a verb that changes it remounts
        the hook: its item collection and selected value live in JS, and a
        stale "Resume" would otherwise linger on a now-running rollout. --%>
        <.select
          id={"rollout-action-#{@rollout.status}"}
          name="action"
          value=""
          label="Select an action"
        >
          <:item :for={{value, label} <- operator_actions(@rollout)} value={value} label={label} />
        </.select>
      </div>
      <.button type="submit" variant="primary" label="Apply" />
    </form>
    """
  end

  @doc """
  Message for a failed operator verb. The dropdown starts unselected —
  its hook initializes the underlying select empty, and an operator verb
  is worth choosing deliberately — so an empty action is a normal
  outcome, not an internal error.
  """
  def operate_error_message(:no_action_selected, _action), do: "Choose an action to apply."

  def operate_error_message(:no_rollout, _action), do: "There is no rollout to operate on."

  def operate_error_message(reason, action), do: "Could not #{action} the rollout: #{inspect(reason)}"

  # Resume and pause are mutually exclusive on status; expedite and abort
  # apply to any non-terminal rollout.
  defp operator_actions(%{status: :running}) do
    [{"pause", "Pause"} | shared_operator_actions()]
  end

  defp operator_actions(%{status: :paused}) do
    [{"resume", "Resume (re-attempt)"} | shared_operator_actions()]
  end

  defp shared_operator_actions do
    [{"expedite", "Expedite (fan out remainder)"}, {"abort", "Abort"}]
  end

  attr :id, :string, required: true
  attr :waves, :list, required: true

  def waves_table(assigns) do
    ~H"""
    <.table id={@id} rows={@waves}>
      <:col :let={wave} label="Wave">
        <.text_cell label={to_string(wave.wave)} />
      </:col>
      <:col :let={wave} label="Accounts">
        <.text_cell label={to_string(wave.accounts)} />
      </:col>
      <:col :let={wave} label="Servers">
        <.text_cell label={to_string(wave.servers)} />
      </:col>
      <:col :let={wave} label="Converged">
        <.text_cell label={"#{wave.converged}/#{wave.servers}"} />
      </:col>
      <:col :let={wave} label="Soak-eligible">
        <.text_cell label={to_string(wave.soak_eligible)} />
      </:col>
      <:empty_state>
        <.table_empty_state
          icon="chart_column"
          title="No waves scheduled yet"
          subtitle="Waves appear once the reconciler opens them."
        />
      </:empty_state>
    </.table>
    """
  end

  attr :id, :string, required: true
  attr :events, :list, required: true

  def events_table(assigns) do
    ~H"""
    <.table id={@id} rows={@events}>
      <:col :let={event} label="When">
        <.text_cell label={to_string(event.inserted_at)} />
      </:col>
      <:col :let={event} label="Action">
        <.text_cell label={event.action} />
      </:col>
      <:col :let={event} label="Actor">
        <.text_cell label={event.actor} />
      </:col>
      <:col :let={event} label="Reason">
        <.text_cell label={event.reason || ""} />
      </:col>
      <:col :let={event} label="Details">
        <.text_cell label={format_metadata(event.metadata)} />
      </:col>
      <:empty_state>
        <.table_empty_state icon="history" title="No events" subtitle="" />
      </:empty_state>
    </.table>
    """
  end

  attr :id, :string, required: true
  attr :rollouts, :list, required: true

  def rollouts_table(assigns) do
    ~H"""
    <.table
      id={@id}
      rows={@rollouts}
      row_navigate={fn rollout -> ~p"/ops/kura/rollouts/#{rollout.id}" end}
    >
      <:col :let={rollout} label="Tag">
        <.text_cell label={rollout.image_tag} />
      </:col>
      <:col :let={rollout} label="Status">
        <.text_cell label={to_string(rollout.status)} />
      </:col>
      <:col :let={rollout} label="Mode">
        <.text_cell label={to_string(rollout.mode)} />
      </:col>
      <:col :let={rollout} label="Created">
        <.text_cell label={to_string(rollout.inserted_at)} />
      </:col>
      <:col :let={rollout} label="Completed">
        <.text_cell label={to_string(rollout.completed_at || "-")} />
      </:col>
      <:empty_state>
        <.table_empty_state icon="stack_2" title="No rollouts" subtitle="" />
      </:empty_state>
    </.table>
    """
  end

  def format_metadata(metadata) when metadata == %{}, do: ""

  def format_metadata(metadata) do
    Enum.map_join(metadata, ", ", fn {key, value} -> "#{key}: #{value}" end)
  end

  def parse_page(nil), do: 1

  def parse_page(value) do
    case Integer.parse(to_string(value)) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end
end
