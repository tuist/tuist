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
      <.text_input
        id="reason"
        name="reason"
        label="Reason"
        placeholder="Recorded on the rollout's audit trail"
        required
        show_required
      />
      <label data-part="action-label" for="action">Action</label>
      <select name="action" id="action" data-part="action-select">
        <option :if={@rollout.status == :running} value="pause">Pause</option>
        <option :if={@rollout.status == :paused} value="resume">Resume (re-attempt)</option>
        <option value="expedite">Expedite (fan out remainder)</option>
        <option value="abort">Abort</option>
      </select>
      <.button type="submit" variant="primary" label="Apply" />
    </form>
    """
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
    <.table id={@id} rows={@rollouts}>
      <:col :let={rollout} label="Tag">
        <.link data-part="rollout-link" navigate={~p"/ops/kura/rollouts/#{rollout.id}"}>
          {rollout.image_tag}
        </.link>
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
