defmodule TuistLabelsWeb.DashboardLive do
  use Phoenix.LiveView, layout: false
  use Noora
  alias TuistLabels.Store

  @impl true
  def mount(_, _, socket) do
    if connected?(socket), do: Process.send_after(self(), :tick, 5_000)

    {:ok,
     assign(socket,
       config: nil,
       state: nil,
       notice: nil,
       form: to_form(%{"labels" => "", "width" => "50", "height" => "12"})
     )}
  end

  @impl true
  def handle_event("authenticate", %{"id" => id, "token" => token} = config, socket) do
    case Store.request({:status, id, token, true}) do
      {:ok, state} ->
        Phoenix.PubSub.subscribe(TuistLabels.PubSub, "labels:" <> id)
        {:noreply, assign(socket, config: config, state: state, notice: nil)}

      {:error, _, message} ->
        {:noreply, assign(socket, notice: message)}
    end
  end

  def handle_event("create", _, socket) do
    case Store.request({:create, :browser}) do
      {:ok, session} ->
        config = %{
          "id" => session["id"],
          "token" => session["controlToken"],
          "relayToken" => session["relayToken"]
        }

        {:noreply, updated} = handle_event("authenticate", config, socket)
        {:noreply, push_event(updated, "session-created", config)}

      {:error, _, message} ->
        {:noreply, assign(socket, notice: message)}
    end
  end

  def handle_event("client-notice", %{"message" => message}, socket),
    do: {:noreply, assign(socket, notice: String.slice(message, 0, 400))}

  def handle_event("validate", params, socket),
    do: {:noreply, assign(socket, form: to_form(params))}

  def handle_event("submit", params, %{assigns: %{config: config}} = socket)
      when not is_nil(config) do
    with {width, ""} <- Float.parse(params["width"]),
         {height, ""} <- Float.parse(params["height"]) do
      items =
        params["labels"]
        |> String.split(~r/\r?\n/)
        |> Enum.reject(&(String.trim(&1) == ""))
        |> Enum.map(&%{"text" => &1})

      case Store.request(
             {:submit, config["id"], config["token"],
              %{"items" => items, "widthMm" => width, "heightMm" => height}}
           ) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(
             notice: "Labels queued for preview only. No printing requested.",
             form: to_form(Map.put(params, "labels", ""))
           )
           |> refresh()}

        {:error, _, message} ->
          {:noreply, assign(socket, notice: message)}
      end
    else
      _ -> {:noreply, assign(socket, notice: "Enter valid preview dimensions.")}
    end
  end

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
    case Store.request({:status, config["id"], config["token"], true}) do
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
        <p class="eyebrow">BRADY M211 · CLI + BROWSER</p>
        <h1>
          {if @live_action == :relay,
            do: "Connect your printer.",
            else: "Rack labels, without the busywork."}
        </h1>
        <p>
          Prepare labels here or with <code>tuist-labels</code>. Chrome handles Bluetooth; the orb handles jobs.
        </p>
      </section>
      <.alert :if={@notice} id="notice" status="information" title={@notice} />
      <section :if={!@state} class="welcome">
        <.card title="Start a private session" icon="lock">
          <.card_section>
            <p :if={@live_action == :control}>
              Create previews and share a separate private relay link with the Mac beside the printer. Sessions expire after eight hours.
            </p>
            <p :if={@live_action == :relay}>
              Open the private Chrome relay link from <code>tuist-labels links</code>. Zen/Firefox can preview, but cannot connect to Bluetooth.
            </p>
            <.button
              :if={@live_action == :control}
              id="create"
              label="Create session"
              phx-click="create"
            />
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
              <p>Open the relay link in Chrome beside the M211. Keep just one relay tab open.</p>
              <.button
                :if={@live_action == :control && @config["relayToken"]}
                id="copy-relay"
                label="Copy Chrome relay link"
                variant="secondary"
              />
              <div
                :if={@live_action == :relay}
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
        <.card :if={@live_action == :control} title="Prepare label previews" icon="pencil">
          <.card_section>
            <.form for={@form} id="label-form" phx-submit="submit" phx-change="validate">
              <.text_area
                id="labels"
                field={@form[:labels]}
                label="One label per line"
                aria-label="One label per line"
                placeholder={~s(RACK-02-SW01\nRACK-02-P09)}
                rows={3}
                max_length={6000}
                show_character_count={false}
                required
              />
              <div class="dimensions">
                <.text_input
                  id="width"
                  field={@form[:width]}
                  input_type="number"
                  label="Width (mm)"
                  min="10"
                  max="200"
                  step="any"
                  required
                />
                <.text_input
                  id="height"
                  field={@form[:height]}
                  input_type="number"
                  label="Height (mm)"
                  min="5"
                  max="20"
                  step="any"
                  required
                />
                <.button id="submit-labels" label="Queue previews" type="submit" />
              </div>
            </.form>
            <p class="hint">
              Illustrative dimensions at 203 dpi. Confirm the installed supply and printable zone before authorizing output.
            </p>
          </.card_section>
        </.card>
        <.card title={"Label queue · #{length(@state["jobs"])}"} icon="stack_2">
          <.card_section>
            <p :if={@state["jobs"] == []}>
              No labels yet. Use the form or <code>tuist-labels submit-text labels.txt</code>.
            </p>
            <div id="jobs" class="jobs">
              <article :for={job <- @state["jobs"]} class="job" id={"job-#{job["id"]}"}>
                <img :if={job["image"]} src={job["image"]} alt={job["title"]} />
                <p>{job["title"]}</p><.badge label={job["state"]} color="neutral" />
              </article>
            </div>
          </.card_section>
        </.card>
      </div>
      <footer>Phoenix LiveView + Noora · Go CLI · Brady SDK 3.3.3 · analytics off</footer>
    </main>
    """
  end
end
