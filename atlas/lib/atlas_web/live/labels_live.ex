defmodule AtlasWeb.LabelsLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Labels

  def mount(_, _, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, 5_000)
    {:ok, assign(socket, page_title: "Labels", state: nil, batch: [], session_id: nil, batch_id: nil)}
  end

  def handle_params(params, _, socket) do
    {:noreply, socket |> assign(session_id: params["id"], batch_id: params["batchId"]) |> refresh()}
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, 5_000)
    {:noreply, refresh(socket)}
  end

  def handle_event("approve", _, socket) do
    case Labels.request(
           socket.assigns.current_user,
           :approve,
           socket.assigns.session_id,
           %{"batchId" => socket.assigns.batch_id},
           "dashboard"
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Batch approved. Check the physical labels as they print.")
         |> refresh()}

      {:error, _, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("relay_token", %{"clientId" => client}, socket) do
    case Labels.request(
           socket.assigns.current_user,
           :relay_token,
           socket.assigns.session_id,
           %{"clientId" => client},
           "dashboard"
         ) do
      {:ok, %{"relayToken" => token}} -> {:reply, %{token: token}, socket}
      {:error, _, message} -> {:reply, %{error: message}, socket}
    end
  end

  defp refresh(socket) do
    case Labels.request(socket.assigns.current_user, :status, socket.assigns.session_id, %{}, "dashboard") do
      {:ok, state} ->
        batch =
          state["jobs"]
          |> Enum.filter(&(socket.assigns.batch_id && &1["batchId"] == socket.assigns.batch_id))
          |> Enum.sort_by(& &1["batchIndex"])

        assign(socket, state: state, batch: batch)

      {:error, _, message} ->
        socket |> assign(state: nil, batch: []) |> put_flash(:error, message)
    end
  end

  defp connection(nil), do: "Waiting for Chrome"
  defp connection(%{"stale" => true}), do: "Relay offline"
  defp connection(%{"connected" => true}), do: "Connected"
  defp connection(_), do: "Not connected"

  defp operation([%{"action" => "cut"} | _]), do: "Cut only"

  defp operation([first | _] = batch),
    do: "Print #{length(batch)} #{if length(batch) == 1, do: "label", else: "labels"}, #{cut_mode(first)}"

  defp operation(_), do: "Nothing to approve"

  defp cut_mode(%{"cut" => true}), do: "cut after each label"
  defp cut_mode(_), do: "no cuts"

  defp result(job) do
    [job["state"], job["printResult"] && "print #{job["printResult"]}", job["cutResult"] && "cut #{job["cutResult"]}"]
    |> Enum.reject(&(&1 in [nil, "cut not-requested"]))
    |> Enum.join(" · ")
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="labels" data-part="labels">
        <div data-part="header">
          <h1>{if @batch_id, do: "Review label batch", else: "Printer connection"}</h1>
          <p>
            Your agent prepares and prints labels in Atlas. Chrome beside the printer supplies Bluetooth.
          </p>
        </div>
        <div :if={@state && !@batch_id} data-part="connection-grid">
          <.card title="Printer connection" icon="device_mobile_share">
            <:actions>
              <.badge
                label={connection(@state["relay"])}
                color={
                  if @state["relay"] && @state["relay"]["connected"], do: "success", else: "neutral"
                }
              />
            </:actions>
            <.card_section>
              <p>Connect once and keep this single Chrome tab open and the computer awake.</p>
              <div
                id="label-relay"
                phx-hook="LabelPrinterRelay"
                phx-update="ignore"
                data-session-id={@session_id}
              >
                <div data-part="actions">
                  <.button id="connect" label="Connect M211" disabled />
                  <.button id="disconnect" label="Disconnect & release" variant="secondary" disabled />
                </div>
                <p id="capability" role="status">Loading relay…</p>
              </div>
              <dl :if={@state["relay"]}>
                <div
                  :for={key <- ~w(model name supply dimensions printerStatus message)}
                  :if={@state["relay"][key] not in [nil, ""]}
                >
                  <dt>{key}</dt>
                  <dd>{@state["relay"][key]}</dd>
                </div>
              </dl>
            </.card_section>
          </.card>
          <.card title="While this tab is connected" icon="lock_open_2">
            <.card_section>
              <p>
                Your agent can print batches and cut through this tab without asking, except printing on zoneless continuous tape always requires your review. Disconnect or close the tab to stop it.
              </p>
              <p>
                Labels print one at a time in order and are cut after each label unless the agent turns cutting off. When your agent asks for a review, it sends an Atlas link showing the whole batch first.
              </p>
              <p>
                Uncertain output stops everything still queued and is never retried automatically. Zen/Firefox cannot relay Bluetooth; use Chrome for this tab.
              </p>
            </.card_section>
          </.card>
        </div>
        <.card :if={@state && !@batch_id} title="Labels in this session" icon="checkup_list">
          <.card_section>
            <p id="label-counts">
              {length(@state["jobs"])} jobs{for {state, count} <- Enum.sort(@state["counts"]),
                                                do: " · #{count} #{state}"}
            </p>
            <.labels_table id="session-labels" jobs={@state["jobs"]} session_id={@session_id} />
          </.card_section>
        </.card>
        <.card :if={@state && @batch_id} title="Review this batch" icon="lock">
          <.card_section>
            <p id="approval-operation"><strong>{operation(@batch)}</strong></p>
            <dl :if={@batch != []}>
              <div :for={key <- ~w(printer supply)}>
                <dt>{key}</dt>
                <dd>{hd(@batch)[key]}</dd>
              </div>
            </dl>
            <p :for={zone <- (@batch != [] && hd(@batch)["zoneDimensions"]) || []}>
              SDK printable zone: {zone["Width"]} × {zone["Height"]}. The SDK fits each image to the installed supply, preserving aspect ratio.
            </p>
            <p>
              Labels print in this order. Approval expires ten minutes after the request; keep the separate connection tab open.
            </p>
            <.labels_table id="batch-labels" jobs={@batch} session_id={@session_id} />
            <.button
              id="approve-label"
              label={"Approve: #{String.downcase(operation(@batch))}"}
              phx-click="approve"
              disabled={@batch == [] or Enum.any?(@batch, &(&1["state"] != "awaiting-approval"))}
            />
            <p id="job-state">
              SDK confirmation still requires checking the physical output. Never automatically retry uncertain output.
            </p>
          </.card_section>
        </.card>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :jobs, :list, required: true
  attr :session_id, :string, required: true

  defp labels_table(assigns) do
    ~H"""
    <.table id={@id} rows={Enum.with_index(@jobs, 1)} row_key={fn {job, _} -> job["id"] end}>
      <:col :let={{_, position}} label="#">
        <span data-part="label-position">{position}</span>
      </:col>
      <:col :let={{job, _}} label="Label">
        <img
          :if={job["action"] == "print"}
          data-part="label-preview"
          src={"/operations/labels/#{@session_id}/jobs/#{job["id"]}/preview"}
          alt={job["title"]}
        />
        <div :if={job["sizing"]} data-part="label-sizing">
          <p>
            Bitmap: {job["sizing"]["bitmapWidthPx"]} × {job["sizing"]["bitmapHeightPx"]} px.
            Preview request: {job["widthMm"]} × {job["heightMm"]} mm.
          </p>
          <p :if={job["sizing"]["mode"] == "continuous"}>
            Nominal SDK page length before feed/trailer: {Float.round(
              job["sizing"]["nominalLengthMm"],
              1
            )} mm (before margin adjustments).
          </p>
          <p>{job["sizing"]["notice"]}</p>
        </div>
        <span :if={job["action"] == "cut"}>Cut only</span>
      </:col>
      <:col :let={{job, _}} label="Text">{job["title"]}</:col>
      <:col :let={{job, _}} label="State">
        <span data-part="label-state" data-state={job["state"]}>{result(job)}</span>
        <span :if={job["note"] && job["state"] == "preview-only"} data-part="label-note">
          {job["note"]}
        </span>
      </:col>
    </.table>
    """
  end
end
