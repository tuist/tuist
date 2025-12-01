defmodule TuistWeb.Marketing.Components.BlogIframeLayout do
  @moduledoc false
  use Phoenix.Component

  import Phoenix.HTML
  import TuistWeb.CSP, only: [get_csp_nonce: 0]

  @doc """
  Shared layout component for blog post iframe visualizations.

  ## Attributes
  - `custom_styles` - Custom CSS styles for the visualization (as a string)
  - `custom_script` - Custom JavaScript code for the visualization (as a string)
  - `custom_head` - Additional head elements (optional)

  ## Slots
  - `inner_block` - The HTML content for the visualization body
  """

  attr :custom_styles, :string, required: true
  attr :custom_script, :string, required: true
  attr :custom_head, :string, default: nil
  slot :inner_block, required: true

  def base(assigns) do
    nonce = get_csp_nonce()
    assigns = assign(assigns, :csp_nonce, nonce)

    ~H"""
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <%= if @custom_head do %>
          {raw(@custom_head)}
        <% end %>

        <style>
          * {
            box-sizing: border-box;
          }

          html, body {
            margin: 0;
            padding: 0;
            width: 100%;
            height: 100%;
            overflow: hidden;
          }

          body {
            background: transparent;
            font: var(--noora-font-weight-regular) var(--noora-font-body-large);
          }

          /* Sankey diagram link styling */
          .link {
            fill: none;
            stroke-opacity: 0.3;
          }

          <%= raw(@custom_styles) %>
        </style>
      </head>
      <body>
        {render_slot(@inner_block)}

        <script nonce={@csp_nonce}>
          let isPaused = true;
          let hasStarted = false;

          // Pause animations when page is hidden
          document.addEventListener('visibilitychange', () => {
            if (document.hidden) {
              isPaused = true;
              if (typeof onPause === 'function') onPause();
            } else if (hasStarted) {
              isPaused = false;
              if (typeof onResume === 'function') onResume();
            }
          });

          // Listen for pause/resume messages from parent page
          window.addEventListener('message', (event) => {
            if (event.data.action === 'pause') {
              isPaused = true;
              if (typeof onPause === 'function') onPause();
            } else if (event.data.action === 'resume') {
              hasStarted = true;
              isPaused = false;
              if (typeof onResume === 'function') onResume();
            } else if (event.data.action === 'start') {
              hasStarted = true;
              isPaused = false;
              if (typeof onResume === 'function') onResume();
            }
          });

          <%= raw(@custom_script) %>
        </script>
      </body>
    </html>
    """
  end
end
