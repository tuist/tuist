defmodule TuistWeb.Marketing.Components.Posts.Rust.BuildTimes do
  @moduledoc """
  Compares clean CI builds of Codex with plain Cargo and with Tuist after two real
  upstream changes, for the Rust announcement post. Medians of five benchmark runs.
  """
  use TuistWeb, :live_component
  use Noora

  @changes [
    %{
      crate: "codex-cli",
      description: "a crate few others depend on",
      cargo: 174,
      tuist: 22
    },
    %{
      crate: "codex-core",
      description: "the crate almost everything depends on",
      cargo: 175,
      tuist: 127
    }
  ]

  def update(assigns, socket) do
    longest = @changes |> Enum.map(& &1.cargo) |> Enum.max()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changes, @changes)
     |> assign(:longest, longest)}
  end

  def render(assigns) do
    ~H"""
    <div id={@id} data-part="rust-build-times">
      <style :type={TuistWeb.ColocatedCSS}>
        [data-part="rust-build-times"] {
          margin: var(--noora-spacing-7) 0;
          color: var(--noora-surface-label-primary);
          font: var(--noora-font-weight-regular) var(--noora-font-body-small);

          & [data-part="change-title"] code,
          & [data-part="note"] code { font-size: 0.9em; }

          & [data-part="change"] + [data-part="change"] { margin-top: var(--noora-spacing-8); }

          & [data-part="change-title"] {
            margin-bottom: var(--noora-spacing-4);

            & span { color: var(--noora-surface-label-secondary); }
          }

          & [data-part="row"] {
            display: grid;
            grid-template-columns: 3.5rem 1fr 4.5rem;
            align-items: center;
            gap: var(--noora-spacing-4);
          }

          & [data-part="row"] + [data-part="row"] { margin-top: var(--noora-spacing-3); }

          & [data-part="tool"] { color: var(--noora-surface-label-secondary); }

          & [data-part="bar"] {
            height: 22px;
            border-radius: var(--noora-radius-2);
            background: var(--noora-surface-background-secondary);
            overflow: hidden;
          }

          & [data-part="fill"] {
            height: 100%;
            min-width: 3px;
            border-radius: var(--noora-radius-2);
            background: var(--noora-surface-label-tertiary);
          }

          & [data-tool="tuist"] [data-part="fill"] { background: var(--noora-button-primary-background); }
          & [data-tool="tuist"] [data-part="tool"],
          & [data-tool="tuist"] [data-part="time"] { color: var(--noora-surface-label-primary); font-weight: var(--noora-font-weight-medium); }

          & [data-part="time"] {
            text-align: right;
            font-variant-numeric: tabular-nums;
          }

          & [data-part="note"] {
            margin-top: var(--noora-spacing-7);
            color: var(--noora-surface-label-tertiary);
          }
        }
      </style>

      <.card icon="clock_hour_4" title="Clean CI build of Codex after a change">
        <.card_section>
          <div :for={change <- @changes} data-part="change">
            <div data-part="change-title">
              Change to <code>{change.crate}</code> <span>· {change.description}</span>
            </div>
            <div
              :for={
                {tool, label, seconds} <- [
                  {"cargo", "Cargo", change.cargo},
                  {"tuist", "Tuist", change.tuist}
                ]
              }
              data-part="row"
              data-tool={tool}
            >
              <span data-part="tool">{label}</span>
              <div data-part="bar" aria-hidden="true">
                <div data-part="fill" style={"width: #{seconds / @longest * 100}%"}></div>
              </div>
              <span data-part="time">{format_duration(seconds)}</span>
            </div>
          </div>
          <div data-part="note">
            Medians of five clean builds of <code>codex-cli</code>
            with <code>CI</code>
            set, on an Apple silicon Mac, with a local cache filled by the commit before the change.
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) do
    "#{div(seconds, 60)}m #{seconds |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}s"
  end
end
