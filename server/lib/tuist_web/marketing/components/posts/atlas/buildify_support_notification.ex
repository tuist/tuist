defmodule TuistWeb.Marketing.Components.Posts.Atlas.BuildifySupportNotification do
  @moduledoc false
  use TuistWeb, :live_component

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign_new(:open?, fn -> false end)}
  end

  def handle_event("open_conversation", _params, socket) do
    {:noreply, update(socket, :open?, &(!&1))}
  end

  def render(assigns) do
    ~H"""
    <style :type={TuistWeb.ColocatedCSS}>
      [data-part="buildify-support-notification"] {
        margin: var(--noora-spacing-7) 0;
        overflow: hidden;
        border: 1px solid light-dark(#d8d8dc, #3d3f42);
        border-radius: 12px;
        background: light-dark(#ffffff, #1a1d21);
        color: light-dark(#1d1c1d, #f4f4f5);
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }

      [data-part="buildify-support-notification"] [data-part="header"] {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 20px 22px 16px;
        border-bottom: 1px solid light-dark(#ececef, #313338);
      }

      [data-part="buildify-support-notification"] [data-part="atlas-mark"] {
        display: grid;
        width: 38px;
        height: 38px;
        place-items: center;
        border-radius: 9px;
        background: linear-gradient(145deg, #8a5cff, #5d2fe8);
        color: white;
        font-size: 20px;
        font-weight: 800;
      }

      [data-part="buildify-support-notification"] [data-part="app-name"] {
        font-size: 17px;
        font-weight: 760;
      }

      [data-part="buildify-support-notification"] [data-part="app-badge"] {
        margin-left: 6px;
        padding: 2px 5px;
        border-radius: 4px;
        background: light-dark(#ececef, #34363b);
        color: light-dark(#5d5c62, #d2d2d7);
        font-size: 11px;
        font-weight: 700;
      }

      [data-part="buildify-support-notification"] [data-part="timestamp"] {
        margin-left: auto;
        color: light-dark(#71717a, #a1a1aa);
        font-size: 14px;
      }

      [data-part="buildify-support-notification"] [data-part="content"] {
        padding: 22px;
      }

      [data-part="buildify-support-notification"] [data-part="title"] {
        margin: 0 0 20px;
        font-size: 24px;
        font-weight: 760;
        letter-spacing: -0.025em;
      }

      [data-part="buildify-support-notification"] [data-part="source"] {
        display: flex;
        align-items: center;
        gap: 8px;
        margin-bottom: 22px;
        color: light-dark(#68676d, #b7b7bd);
        font-size: 16px;
        font-weight: 650;
      }

      [data-part="buildify-support-notification"] [data-part="source-mark"] {
        display: grid;
        width: 24px;
        height: 24px;
        place-items: center;
        border-radius: 5px;
        background: linear-gradient(145deg, #8a5cff, #5d2fe8);
        color: white;
        font-size: 13px;
        font-weight: 800;
      }

      [data-part="buildify-support-notification"] [data-part="details"] {
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(0, 1.45fr);
        gap: 20px 36px;
      }

      [data-part="buildify-support-notification"] [data-part="label"] {
        display: block;
        margin-bottom: 4px;
        color: light-dark(#27272a, #f4f4f5);
        font-size: 14px;
        font-weight: 760;
      }

      [data-part="buildify-support-notification"] [data-part="value"] {
        color: light-dark(#4b4a50, #c9c9d0);
        font-size: 16px;
        line-height: 1.42;
      }

      [data-part="buildify-support-notification"] [data-part="status"] {
        color: light-dark(#9a6700, #facc15);
        font-weight: 650;
      }

      [data-part="buildify-support-notification"] [data-part="sent-by"] {
        margin: 24px 0 18px;
        color: light-dark(#3f3f46, #d4d4d8);
        font-size: 16px;
      }

      [data-part="buildify-support-notification"] [data-part="action"] {
        padding: 10px 16px;
        border: 0;
        border-radius: 7px;
        background: #2e7d5c;
        color: white;
        cursor: pointer;
        font: inherit;
        font-weight: 720;
      }

      [data-part="buildify-support-notification"] [data-part="action"]:hover {
        background: #256749;
      }

      [data-part="buildify-support-notification"] [data-part="conversation"] {
        margin-top: 18px;
        padding: 14px 16px;
        border-radius: 8px;
        background: light-dark(#f6f6f8, #24262b);
        color: light-dark(#4b4a50, #d4d4d8);
        font-size: 15px;
        line-height: 1.45;
      }

      @media (max-width: 520px) {
        [data-part="buildify-support-notification"] [data-part="details"] {
          grid-template-columns: 1fr;
          gap: 16px;
        }

        [data-part="buildify-support-notification"] [data-part="timestamp"] {
          display: none;
        }
      }
    </style>

    <section
      id={@id}
      data-part="buildify-support-notification"
      aria-label="Atlas support reply notification"
    >
      <header data-part="header">
        <span data-part="atlas-mark" aria-hidden="true">A</span>
        <span data-part="app-name">Tuist Atlas</span>
        <span data-part="app-badge">APP</span>
        <time data-part="timestamp">12:10 PM</time>
      </header>

      <div data-part="content">
        <h3 data-part="title">Support reply sent</h3>

        <div data-part="source">
          <span data-part="source-mark" aria-hidden="true">A</span>
          <span>Atlas Support</span>
        </div>

        <div data-part="details">
          <div>
            <span data-part="label">Customer</span>
            <span data-part="value">Maya Chen (maya@buildify.example)</span>
          </div>
          <div>
            <span data-part="label">Subject</span>
            <span data-part="value">Cache upload stalls after a successful build</span>
          </div>
          <div>
            <span data-part="label">Status</span>
            <span data-part="value" data-part-status="waiting">Waiting</span>
          </div>
          <div>
            <span data-part="label">Account</span>
            <span data-part="value">Buildify</span>
          </div>
        </div>

        <p data-part="sent-by">A reply was sent by Pedro Piñera Buendía.</p>
        <button type="button" data-part="action" phx-click="open_conversation" phx-target={@myself}>
          {if @open?, do: "Close conversation", else: "Open conversation"}
        </button>

        <div :if={@open?} data-part="conversation">
          Buildify reported that uploads stall after a successful build. Atlas has the account context, recent feature usage, and the support thread in one place for the next reply.
        </div>
      </div>
    </section>
    """
  end
end
