defmodule TuistWeb.Marketing.Components.CacheLatencyLab do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <script :type={Phoenix.LiveView.ColocatedHook} name=".CacheLatency">
      export default {
        mounted() {
          this.latency = this.el.querySelector('[data-latency]')
          this.bandwidth = this.el.querySelector('[data-bandwidth]')
          this.onInput = () => this.draw()
          this.el.addEventListener('input', this.onInput)
          this.draw()
        },

        destroyed() {
          this.el.removeEventListener('input', this.onInput)
        },

        draw() {
          const latency = Number(this.latency.value)
          const bandwidth = Number(this.bandwidth.value)
          const scale = latency + 16 / bandwidth * 1000
          const format = (value) => Number(value.toFixed(2)).toLocaleString('en-US')
          this.el.querySelector('[data-latency-value]').textContent = `${latency} milliseconds`
          this.el.querySelector('[data-bandwidth-value]').textContent = `${bandwidth} megabytes/second`
          this.latency.setAttribute('aria-valuetext', `${latency} milliseconds`)
          this.bandwidth.setAttribute('aria-valuetext', `${bandwidth} megabytes per second`)

          this.el.querySelectorAll('[data-size]').forEach((row) => {
            const transfer = Number(row.dataset.size) / bandwidth * 1000
            row.querySelector('[data-wait-bar]').style.width = `${latency / scale * 100}%`
            row.querySelector('[data-transfer-bar]').style.width = `${transfer / scale * 100}%`
            row.querySelector('[data-total]').textContent = `${format(latency + transfer)} milliseconds`
            row.querySelector('[data-breakdown]').textContent =
              `${format(latency)} waiting + ${format(transfer)} transferring`
          })
        },
      }
    </script>

    <style :type={TuistWeb.ColocatedCSS}>
      .cache-latency-lab {
        margin: var(--noora-spacing-7) 0;
        color: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);
      }

      .cache-latency-lab__controls {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: var(--noora-spacing-6);
        margin-bottom: var(--noora-spacing-7);
      }

      .cache-latency-lab__control {
        display: flex;
        flex-direction: column;
        gap: var(--noora-spacing-3);
      }

      .cache-latency-lab input {
        width: 100%;
        margin: 0;
        accent-color: var(--noora-button-primary-background);
      }

      .cache-latency-lab__row + .cache-latency-lab__row {
        margin-top: var(--noora-spacing-7);
      }

      .cache-latency-lab__heading {
        display: flex;
        justify-content: space-between;
        flex-wrap: wrap;
        gap: var(--noora-spacing-2);
        margin-bottom: var(--noora-spacing-3);
      }

      .cache-latency-lab__bar {
        display: flex;
        height: 22px;
        margin: var(--noora-spacing-3) 0;
        background: var(--noora-surface-background-secondary);
        border-radius: var(--noora-radius-2);
        overflow: hidden;
      }

      .cache-latency-lab__wait { background: var(--noora-button-primary-background); }
      .cache-latency-lab__transfer { background: var(--noora-surface-label-secondary); }

      .cache-latency-lab__legend {
        display: flex;
        flex-wrap: wrap;
        gap: var(--noora-spacing-6);
        margin-top: var(--noora-spacing-7);
      }

      .cache-latency-lab__legend i {
        display: inline-block;
        width: 10px;
        height: 10px;
        margin-right: var(--noora-spacing-2);
      }

      .cache-latency-lab__note,
      .cache-latency-lab [data-breakdown],
      .cache-latency-lab output {
        color: var(--noora-surface-label-secondary);
      }

      .cache-latency-lab__note { margin-top: var(--noora-spacing-6); }

      @media (max-width: 480px) {
        .cache-latency-lab__controls { grid-template-columns: 1fr; }
      }
    </style>

    <div class="cache-latency-lab">
      <.card icon="database" title="Where a cache request spends its time">
        <.card_section>
          <div id={@id <> "-controls"} phx-hook=".CacheLatency" phx-update="ignore">
            <div class="cache-latency-lab__controls">
              <div class="cache-latency-lab__control">
                <label for={@id <> "-latency"}>Round-trip latency</label>
                <input id={@id <> "-latency"} data-latency type="range" min="1" max="200" value="100" />
                <output for={@id <> "-latency"} data-latency-value>100 milliseconds</output>
              </div>
              <div class="cache-latency-lab__control">
                <label for={@id <> "-bandwidth"}>Transfer speed</label>
                <input
                  id={@id <> "-bandwidth"}
                  data-bandwidth
                  type="range"
                  min="10"
                  max="200"
                  value="50"
                />
                <output for={@id <> "-bandwidth"} data-bandwidth-value>50 megabytes/second</output>
              </div>
            </div>

            <div class="cache-latency-lab__row" data-size="16">
              <div class="cache-latency-lab__heading">
                <strong>Large artifact · 16 megabytes</strong>
                <span data-total>420 milliseconds</span>
              </div>
              <div class="cache-latency-lab__bar" aria-hidden="true">
                <span class="cache-latency-lab__wait" data-wait-bar style="width: 23.8095%"></span>
                <span class="cache-latency-lab__transfer" data-transfer-bar style="width: 76.1905%"></span>
              </div>
              <div data-breakdown>100 waiting + 320 transferring</div>
            </div>

            <div class="cache-latency-lab__row" data-size="0.016">
              <div class="cache-latency-lab__heading">
                <strong>Small artifact · 16 kilobytes</strong>
                <span data-total>100.32 milliseconds</span>
              </div>
              <div class="cache-latency-lab__bar" aria-hidden="true">
                <span class="cache-latency-lab__wait" data-wait-bar style="width: 23.8095%"></span>
                <span class="cache-latency-lab__transfer" data-transfer-bar style="width: 0.0762%"></span>
              </div>
              <div data-breakdown>100 waiting + 0.32 transferring</div>
            </div>
          </div>

          <div class="cache-latency-lab__legend">
            <span><i class="cache-latency-lab__wait"></i>Waiting for the response</span>
            <span><i class="cache-latency-lab__transfer"></i>Transferring bytes</span>
          </div>
          <div class="cache-latency-lab__note">
            Try increasing transfer speed, then reducing latency. Faster transfers help the large
            artifact; the small one spends most of its time waiting. A build repeats that wait
            for each request it cannot overlap with another.
          </div>
          <div class="cache-latency-lab__note">
            Illustrative values, with one round trip per request and an already established connection.
            Both bars share a time scale. Disk and server processing time are excluded.
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end
end
