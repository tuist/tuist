defmodule TuistLabelsWeb.RelayLive do
  use Phoenix.LiveView, layout: false
  use Noora
  alias TuistLabels.Store

  @impl true
  def mount(_, _, socket) do
    if connected?(socket), do: Process.send_after(self(), :tick, 5_000)

    {:ok, assign(socket, config: nil, state: nil, notice: nil)}
  end

  @impl true
  def handle_event("authenticate", %{"id" => id, "token" => token} = config, socket) do
    case Store.request({:status, id, token, false}) do
      {:ok, state} ->
        Phoenix.PubSub.subscribe(TuistLabels.PubSub, "labels:" <> id)
        {:noreply, assign(socket, config: config, state: state, notice: nil)}

      {:error, _, message} ->
        {:noreply, assign(socket, notice: message)}
    end
  end

  def handle_event("client-notice", %{"message" => message}, socket),
    do: {:noreply, assign(socket, notice: String.slice(message, 0, 400))}

  @impl true
  def handle_info(:refresh, socket) do
    # PubSub updates immediately; the timer additionally expires stale relay reports.
    {:noreply, refresh(socket)}
  end

  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, 5_000)
    {:noreply, refresh(socket)}
  end

  defp refresh(%{assigns: %{config: nil}} = socket), do: socket

  defp refresh(%{assigns: %{config: config}} = socket) do
    case Store.request({:status, config["id"], config["token"], false}) do
      {:ok, state} -> assign(socket, state: state)
      {:error, _, message} -> assign(socket, state: nil, notice: message)
    end
  end

  defp connection(nil), do: "Waiting for Chrome"
  defp connection(%{"stale" => true}), do: "Relay offline"
  defp connection(%{"connected" => true}), do: "Connected"
  defp connection(_), do: "Not connected"

  @impl true
  def render(assigns) do
    ~H"""
    <main id="labels-app" phx-hook="BrowserSession">
      <header>
        <a class="brand" href="/">Tuist <span>Labels</span></a>
        <.badge
          label={
            if @state && @state["printingEnabled"], do: "Single-use approval", else: "Preview only"
          }
          color="warning"
        />
      </header>
      <section class="intro">
        <p class="eyebrow">BRADY M211 · AGENT-DRIVEN PRINTING</p>
        <h1>Connect your printer.</h1>
        <p>
          Your agent prepares and submits labels from the orb. This Chrome tab bridges local Bluetooth.
        </p>
      </section>
      <.alert :if={@notice} id="notice" status="information" title={@notice} />
      <section :if={!@state} class="welcome">
        <.card title="Open your agent's connection link" icon="lock">
          <.card_section>
            <p>
              Ask your agent to run <code>tuist-labels init</code>
              on the job host and share the private Chrome relay link.
              Open it in Chrome on the Mac beside the M211. Sessions expire after eight hours.
            </p>
            <p>
              No label entry is needed here. Use Chrome, not Zen/Firefox, for the Bluetooth connection.
            </p>
          </.card_section>
        </.card>
      </section>
      <div :if={@state} id="workspace">
        <div class="columns">
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
              <p>Connect once and keep this single Chrome tab open while your agent works.</p>
              <div
                id="relay-transport"
                phx-hook="PrinterRelay"
                phx-update="ignore"
              >
                <div class="actions">
                  <.button id="connect" label="Connect M211" disabled /><.button
                    id="disconnect"
                    label="Disconnect & release"
                    variant="secondary"
                    disabled
                  />
                </div>
                <p id="capability" role="status">Loading relay…</p>
              </div>
              <dl :if={@state["relay"]}>
                <div
                  :for={key <- ~w(model name supply dimensions printerStatus message)}
                  :if={@state["relay"][key] not in [nil, ""]}
                >
                  <dt>{key}</dt><dd>{@state["relay"][key]}</dd>
                </div>
              </dl>
              <p class="hint">
                {length(@state["jobs"])} jobs in this session. Your agent reads job results with <code>tuist-labels status</code>.
              </p>
            </.card_section>
          </.card>
          <.card title="Explicit approval only" icon="lock">
            <.card_section>
              <p :if={!@state["printingEnabled"]}>
                Printing is disabled. Previews never print automatically.
              </p>
              <p :if={@state["printingEnabled"]}>
                One copy of <strong>{@state["printAuthorization"]["text"]}</strong>
                is authorized. Cutting requires separate approval.
              </p>
              <p>
                No feed, reset, firmware or configuration controls. Uncertain output is never automatically retried.
              </p>
            </.card_section>
          </.card>
        </div>
      </div>
      <footer>Phoenix LiveView + Noora · Go CLI · Brady SDK 3.3.3 · analytics off</footer>
    </main>
    """
  end
end
