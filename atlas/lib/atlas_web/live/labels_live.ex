defmodule AtlasWeb.LabelsLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Labels

  def mount(_, _, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, 5_000)
    {:ok, assign(socket, page_title: "Labels", state: nil, job: nil, session_id: nil, job_id: nil)}
  end

  def handle_params(params, _, socket) do
    {:noreply, socket |> assign(session_id: params["id"], job_id: params["jobId"]) |> refresh()}
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
           %{"jobId" => socket.assigns.job_id},
           "dashboard"
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Single-use operation approved. Check the physical printer for the result.")
         |> refresh()}

      {:error, _, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp refresh(socket) do
    case Labels.request(socket.assigns.current_user, :status, socket.assigns.session_id, %{}, "dashboard") do
      {:ok, state} -> assign(socket, state: state, job: Enum.find(state["jobs"], &(&1["id"] == socket.assigns.job_id)))
      {:error, _, message} -> socket |> assign(state: nil, job: nil) |> put_flash(:error, message)
    end
  end

  defp connection(nil), do: "Waiting for Chrome"
  defp connection(%{"stale" => true}), do: "Relay offline"
  defp connection(%{"connected" => true}), do: "Connected"
  defp connection(_), do: "Not connected"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="labels" data-part="labels">
        <div data-part="header">
          <h1>{if @job_id, do: "Review printer operation", else: "Printer connection"}</h1>
          <p>Your agent prepares labels in Atlas. Chrome beside the printer supplies Bluetooth.</p>
        </div>
        <div :if={@state && !@job_id} data-part="connection-grid">
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
              <p>
                {length(@state["jobs"])} jobs. Your agent reads previews and results through Atlas.
              </p>
            </.card_section>
          </.card>
          <.card title="Your approval controls output" icon="lock">
            <.card_section>
              <p>
                Submitting labels only creates previews. Your agent sends an Atlas approval link for the exact label, printer and supply before output.
              </p>
              <p>
                One copy, no automatic cut. Cutting requires a separate approval. Uncertain output never retries automatically.
              </p>
              <p>
                Zen/Firefox cannot relay Bluetooth. Use Chrome for this tab; your agent can run anywhere.
              </p>
            </.card_section>
          </.card>
        </div>
        <.card :if={@state && @job} title="Review this operation" icon="lock">
          <.card_section>
            <p id="approval-operation">
              <strong>
                {if @job["action"] == "cut",
                  do: "Cut existing label only",
                  else: "Print one copy — no automatic cut"}
              </strong>
            </p>
            <img
              :if={@job["action"] == "print"}
              id="label-preview"
              src={"/operations/labels/#{@session_id}/jobs/#{@job_id}/preview"}
              alt={@job["title"]}
            />
            <dl>
              <div :for={key <- ~w(title printer supply state)}>
                <dt>{key}</dt>
                <dd>{@job[key]}</dd>
              </div>
            </dl>
            <p :if={@job["action"] == "print"}>
              Preview size: {@job["widthMm"]} × {@job["heightMm"]} mm. The SDK fits the image to the installed supply, preserving aspect ratio.
            </p>
            <p :for={zone <- @job["zoneDimensions"] || []}>
              SDK printable zone: {zone["Width"]} × {zone["Height"]}.
            </p>
            <p>
              Check the preview, installed cartridge and printable dimensions. Approval expires ten minutes after the request. Keep the separate connection tab open.
            </p>
            <p :if={@job["action"] == "cut"}>
              Confirm the printed label is ready to detach. This sends only a cut, never a print or feed.
            </p>
            <.button
              id="approve-label"
              label={
                if @job["action"] == "cut", do: "Approve one cut", else: "Approve & print one copy"
              }
              phx-click="approve"
              disabled={@job["state"] != "awaiting-approval"}
            />
            <p id="job-state">
              {@job["state"]}. SDK confirmation still requires checking the physical output. Never automatically retry uncertain output.
            </p>
          </.card_section>
        </.card>
      </div>
    </Layouts.app>
    """
  end
end
