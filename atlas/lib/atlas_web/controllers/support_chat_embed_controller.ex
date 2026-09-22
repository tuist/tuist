defmodule AtlasWeb.SupportChatEmbedController do
  use AtlasWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_content_type("application/javascript")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(200, embed_script())
  end

  defp embed_script do
    ~S"""
    (() => {
      const script = document.currentScript;
      if (!script?.src) return;

      const atlasOrigin = new URL(script.src, window.location.href).origin;
      if (!customElements.get("atlas-support-chat")) {
        class AtlasSupportChat extends HTMLElement {
          connectedCallback() {
            if (this.shadowRoot) return;

            this.atlasOrigin = this.dataset.endpoint;
            this.storageKey = "atlas-support-chat-conversation";
            this.attachShadow({mode: "open"});
            this.shadowRoot.innerHTML = `
              <style>
                :host {
                  bottom: max(1.5rem, env(safe-area-inset-bottom));
                  display: block;
                  position: fixed;
                  right: max(1.5rem, env(safe-area-inset-right));
                  z-index: 2147483647;
                }

                /* Same enter/exit as the dashboard switcher: 200ms fade + settle
                   in via @starting-style, 150ms back out. The display transition
                   with allow-discrete keeps the panel rendered until the exit
                   transition finishes, since toggling [hidden] slams display: none.
                   NOTE: this style block lives inside a JS template literal, so
                   backticks must never appear anywhere in it. */
                [data-part="panel"] {
                  background: #fff;
                  opacity: 1;
                  transform: translateY(0);
                  transition:
                    opacity 200ms cubic-bezier(0.215, 0.61, 0.355, 1),
                    transform 200ms cubic-bezier(0.215, 0.61, 0.355, 1),
                    display 200ms allow-discrete,
                    height 250ms cubic-bezier(0.215, 0.61, 0.355, 1);
                  border-radius: var(--noora-radius-6, 0.75rem);
                  /* Noora's light-border-default shadow (token wins when the host
                     page defines it), plus two soft drop shadows for depth. */
                  box-shadow:
                    var(--noora-light-border-default,
                      0 1px 1px 0 oklch(16.2% 0 0 / .05),
                      0 0 0 1px oklch(31.8% 0.011 248.2 / .08),
                      0 1px 1px 0 oklch(31.8% 0.011 248.2 / .1)),
                    0 4px 8px 0 rgb(49 51 53 / .08),
                    0 2px 4px 0 rgb(49 51 53 / .04);
                  bottom: calc(100% + 12px);
                  /* Placeholder matching the form's natural height (~480px per the
                     design), so the skeleton fits and the first resize from the
                     LiveView is a near-noop. */
                  height: min(30rem, calc(100vh - 6.75rem));
                  overflow: hidden;
                  position: absolute;
                  right: 0;
                  width: min(26rem, calc(100vw - 2rem));
                }

                @starting-style {
                  [data-part="panel"] {
                    opacity: 0;
                    transform: translateY(-0.25rem);
                  }
                }

                [data-part="panel"][hidden] {
                  display: none;
                  opacity: 0;
                  transform: translateY(-0.25rem);
                  transition-duration: 150ms;
                }

                [data-part="frame"] {
                  border: 0;
                  display: block;
                  height: 100%;
                  opacity: 1;
                  transition: opacity 200ms ease;
                  width: 100%;
                }

                [data-part="panel"][data-loading] [data-part="frame"] {
                  opacity: 0;
                }

                /* While the skeleton is up, height changes from the initial
                   load handshake snap instantly; the height transition only
                   smooths later state changes (form to chat, growing
                   conversations). */
                [data-part="panel"][data-loading] {
                  transition-property: opacity, transform, display;
                }

                /* Skeleton mirroring the chat layout: heading with divider, then
                   Name, Email, Message fields and a hug-width button. */
                [data-part="loader"] {
                  display: flex;
                  flex-direction: column;
                  inset: 0;
                  padding-top: 16px;
                  position: absolute;
                }

                [data-part="loader"][hidden] {
                  display: none;
                }

                [data-part="loader"] [data-skeleton] {
                  animation: atlas-chat-shimmer 1.4s ease infinite;
                  background: linear-gradient(90deg, rgba(17, 17, 17, .06) 25%, rgba(17, 17, 17, .11) 37%, rgba(17, 17, 17, .06) 63%);
                  background-size: 400% 100%;
                  border-radius: 8px;
                  flex: none;
                }

                /* Theme via light-dark() rather than prefers-color-scheme: the
                   widget inherits the HOST page's used color scheme, which is
                   also what the browser hands the chat iframe, so panel and
                   chat content can never resolve to different themes. Each
                   declaration is preceded by a light literal for browsers
                   without light-dark() support. */
                [data-part="panel"] {
                  background: var(--noora-surface-background-primary, light-dark(#fff, #111));
                  box-shadow:
                    var(--noora-light-border-default,
                      0 1px 1px 0 light-dark(oklch(16.2% 0 0 / .05), oklch(16.2% 0 0 / .3)),
                      0 0 0 1px light-dark(oklch(31.8% 0.011 248.2 / .08), oklch(54.9% 0 0 / .45)),
                      0 1px 1px 0 light-dark(oklch(31.8% 0.011 248.2 / .1), oklch(0% 0 0 / .3))),
                    0 4px 8px 0 light-dark(rgb(49 51 53 / .08), rgb(0 0 0 / .16)),
                    0 2px 4px 0 light-dark(rgb(49 51 53 / .04), rgb(0 0 0 / .24));
                }

                [data-part="loader"] [data-skeleton] {
                  background: linear-gradient(90deg,
                    light-dark(rgba(17, 17, 17, .06), rgba(255, 255, 255, .07)) 25%,
                    light-dark(rgba(17, 17, 17, .11), rgba(255, 255, 255, .12)) 37%,
                    light-dark(rgba(17, 17, 17, .06), rgba(255, 255, 255, .07)) 63%);
                  background-size: 400% 100%;
                }

                [data-part="skeleton-header"] {
                  border-color: light-dark(rgba(17, 17, 17, .08), rgba(255, 255, 255, .08));
                }

                @keyframes atlas-chat-shimmer {
                  from {
                    background-position: 100% 0;
                  }

                  to {
                    background-position: 0 0;
                  }
                }

                [data-part="skeleton-header"] {
                  border-bottom: 1px solid rgba(17, 17, 17, .08);
                  display: flex;
                  flex-direction: column;
                  gap: 8px;
                  padding: 0 20px 16px;
                }

                [data-part="skeleton-body"] {
                  display: flex;
                  flex-direction: column;
                  gap: 8px;
                  padding: 16px 20px 20px;
                }

                [data-part="skeleton-line"] {
                  height: 14px;
                }

                [data-part="skeleton-line"][data-width="narrow"] {
                  height: 16px;
                  width: 45%;
                }

                [data-part="skeleton-line"][data-width="wide"] {
                  width: 60%;
                }

                [data-part="skeleton-line"][data-width="label"] {
                  margin-top: 8px;
                  width: 30%;
                }

                [data-part="skeleton-line"][data-width="label"]:first-child {
                  margin-top: 0;
                }

                [data-part="skeleton-input"] {
                  height: 36px;
                }

                [data-part="skeleton-textarea"] {
                  height: 132px;
                }

                [data-part="skeleton-button"] {
                  height: 36px;
                  margin-top: 8px;
                  width: 128px;
                }

                /* Noora primary button tokens, var()-first: this shadow DOM renders
                   on the parent page, so tokens resolve when the host defines them
                   (custom properties inherit into shadow roots) and the literal
                   fallbacks mirror the same values elsewhere. One extra halo shadow
                   from the design is appended to each state. */
                [data-part="trigger"] {
                  align-items: center;
                  background: var(--noora-button-background-primary,
                    linear-gradient(180deg, oklch(100% 0 0 / .06) 0%, oklch(100% 0 0 / 0) 100%),
                    oklch(53.2% 0.276 286.9));
                  border: 0;
                  border-radius: var(--noora-radius-99, 1000px);
                  box-shadow:
                    var(--noora-button-border-primary,
                      0 1px 0 0 oklch(100% 0 0 / .2) inset,
                      0 1px 1px 0 oklch(31.8% 0.011 248.2 / .05),
                      0 0 0 1px oklch(46.9% 0.27 286.9 / .9),
                      0 1px 3px 0 oklch(31.8% 0.011 248.2 / .16)),
                    0 0 0 3px rgb(182 185 188 / .5);
                  color: var(--noora-button-primary-label, oklch(99.4% 0 0));
                  cursor: pointer;
                  display: inline-flex;
                  gap: 2px;
                  padding: var(--noora-spacing-4, 0.5rem);
                  touch-action: manipulation;
                  transition: transform 150ms ease;
                }

                [data-part="trigger"]:not(:disabled):active {
                  transform: scale(0.97);
                }

                /* Noora desktop/body-medium at medium weight; slides in on hover
                   with Noora's --ease-out-cubic. */
                [data-part="trigger-label-wrap"] {
                  display: grid;
                  grid-template-columns: 1fr;
                }

                /* Touch devices have no hover to reveal the label with, so the
                   trigger is the bare icon circle there, same as the desktop
                   resting state, and a tap opens the panel straight away. */
                @media (hover: none), (pointer: coarse) {
                  [data-part="trigger-label-wrap"] {
                    display: none;
                  }
                }

                [data-part="trigger-label-clip"] {
                  display: block;
                  min-width: 0;
                  overflow: hidden;
                }

                /* Custom properties inherit into the shadow root, so when the host
                   page defines Noora tokens these resolve to them; the fallbacks
                   mirror desktop/body-medium for pages that don't. */
                [data-part="trigger-label"] {
                  display: inline-block;
                  font: var(--noora-font-weight-medium, 500) var(--noora-font-body-medium, 0.875rem/1.25rem "Inter Variable", "Noto Sans Georgian", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif);
                  padding: 0 4px;
                  white-space: nowrap;
                }

                @media (hover: hover) and (pointer: fine) {
                  /* Grid 0fr -> 1fr animates the column to the label's exact width;
                     the clip wrapper hides it instead of squishing it. The flex gap
                     collapses too, so the resting state is a true circle. */
                  [data-part="trigger"] {
                    gap: 0;
                    transition:
                      transform 150ms ease,
                      gap 250ms cubic-bezier(0.215, 0.61, 0.355, 1);
                  }

                  [data-part="trigger"]:hover,
                  [data-part="trigger"]:focus-visible,
                  [data-part="trigger"][aria-expanded="true"] {
                    gap: 2px;
                  }

                  [data-part="trigger-label-wrap"] {
                    grid-template-columns: 0fr;
                    transition: grid-template-columns 250ms cubic-bezier(0.215, 0.61, 0.355, 1);
                  }

                  [data-part="trigger-label"] {
                    opacity: 0;
                    transform: translateX(-.25rem);
                    transition:
                      opacity 250ms cubic-bezier(0.215, 0.61, 0.355, 1),
                      transform 250ms cubic-bezier(0.215, 0.61, 0.355, 1);
                  }

                  [data-part="trigger"]:hover [data-part="trigger-label-wrap"],
                  [data-part="trigger"]:focus-visible [data-part="trigger-label-wrap"],
                  [data-part="trigger"][aria-expanded="true"] [data-part="trigger-label-wrap"] {
                    grid-template-columns: 1fr;
                  }

                  [data-part="trigger"]:hover [data-part="trigger-label"],
                  [data-part="trigger"]:focus-visible [data-part="trigger-label"],
                  [data-part="trigger"][aria-expanded="true"] [data-part="trigger-label"] {
                    opacity: 1;
                    transform: translateX(0);
                  }
                }

                @media (prefers-reduced-motion: reduce) {
                  [data-part="trigger"],
                  [data-part="trigger-label-wrap"],
                  [data-part="trigger-label"],
                  [data-part="panel"],
                  [data-part="backdrop"],
                  [data-part="frame"] {
                    transition: none;
                  }

                  [data-part="loader"] [data-skeleton] {
                    animation: none;
                  }
                }

                [data-part="trigger"]:hover,
                [data-part="trigger"][aria-expanded="true"] {
                  background: var(--noora-button-background-primary-hover,
                    linear-gradient(180deg, oklch(100% 0 0 / .18) 0%, oklch(100% 0 0 / 0) 100%),
                    oklch(53.2% 0.276 286.9));
                  box-shadow:
                    var(--noora-button-border-primary-hover,
                      0 1px 1px oklch(31.8% 0.011 248.2 / .12),
                      0 0 0 1px oklch(46.9% 0.27 286.9 / .9),
                      0 2px 3px oklch(31.8% 0.011 248.2 / .16),
                      0 1px 0 oklch(100% 0 0 / .1) inset),
                    0 0 0 3px rgb(182 185 188 / .5);
                }

                [data-part="trigger"]:active {
                  background: var(--noora-button-background-primary-active, oklch(53.2% 0.276 286.9));
                  box-shadow:
                    var(--noora-button-border-primary-active,
                      0 0 0 1px oklch(46.9% 0.27 286.9 / .9),
                      0 1px 4px 0 oklch(0% 0 0 / .3) inset),
                    0 0 0 3px rgb(182 185 188 / .5);
                }

                [data-part="trigger"][hidden] {
                  display: none;
                }

                [data-part="trigger"]:focus-visible {
                  box-shadow: var(--noora-button-border-primary-focus,
                    0 0 0 1px oklch(99.4% 0 0),
                    0 0 0 2.5px oklch(53.2% 0.276 286.9),
                    0 1px 0 0 oklch(100% 0 0 / .2) inset,
                    0 1px 1px 0 oklch(31.8% 0.011 248.2 / .12),
                    0 0 0 1px oklch(46.9% 0.27 286.9 / .9),
                    0 2px 3px 0 oklch(31.8% 0.011 248.2 / .16));
                  outline: none;
                }

                [data-part="trigger-icon"] {
                  height: 20px;
                  width: 20px;
                }

                /* Desktop popover needs no backdrop; the phone drawer below
                   enables it. */
                [data-part="backdrop"] {
                  display: none;
                }

                @media (max-width: 767px) {
                  /* Phone drawer, same pattern as the marketing filter/plan
                     selects: a content-height sheet slides up from the bottom
                     edge over Noora's blurred overlay, keeping the base
                     durations and easing. The host stays pinned bottom-right so
                     the trigger keeps its corner position. */
                  [data-part="backdrop"] {
                    backdrop-filter: blur(2.5px);
                    background: var(--noora-surface-overlay, oklch(31.8% 0 0 / 0.24));
                    display: block;
                    inset: 0;
                    opacity: 1;
                    position: fixed;
                    transition:
                      opacity 200ms cubic-bezier(0.215, 0.61, 0.355, 1),
                      display 200ms allow-discrete;
                  }

                  [data-part="backdrop"][hidden] {
                    display: none;
                    opacity: 0;
                    transition-duration: 150ms;
                  }

                  [data-part="panel"] {
                    border-radius: var(--noora-radius-6, 0.75rem) var(--noora-radius-6, 0.75rem) 0 0;
                    bottom: 0;
                    box-shadow: none;
                    box-sizing: border-box;
                    left: 0;
                    max-height: calc(100dvh - 3rem) !important;
                    padding-bottom: max(var(--noora-spacing-6, 1rem), env(safe-area-inset-bottom));
                    position: fixed;
                    right: 0;
                    top: auto;
                    transform: translateY(0);
                    width: 100vw;
                  }

                  [data-part="panel"][hidden] {
                    transform: translateY(100%);
                  }

                  /* The drawer covers the trigger's corner; hide it while open
                     so it cannot paint on top of the sheet. */
                  [data-part="trigger"][aria-expanded="true"] {
                    display: none;
                  }

                  @starting-style {
                    [data-part="backdrop"] {
                      opacity: 0;
                    }

                    [data-part="panel"] {
                      opacity: 0;
                      transform: translateY(100%);
                    }
                  }
                }
              </style>
              <div data-part="backdrop" hidden></div>
              <section data-part="panel" hidden>
                <div data-part="loader" hidden>
                  <div data-part="skeleton-header">
                    <span data-part="skeleton-line" data-width="narrow" data-skeleton></span>
                    <span data-part="skeleton-line" data-width="wide" data-skeleton></span>
                  </div>
                  <div data-part="skeleton-body">
                    <span data-part="skeleton-line" data-width="label" data-skeleton></span>
                    <span data-part="skeleton-input" data-skeleton></span>
                    <span data-part="skeleton-line" data-width="label" data-skeleton></span>
                    <span data-part="skeleton-input" data-skeleton></span>
                    <span data-part="skeleton-line" data-width="label" data-skeleton></span>
                    <span data-part="skeleton-textarea" data-skeleton></span>
                    <span data-part="skeleton-button" data-skeleton></span>
                  </div>
                </div>
                <iframe
                  id="atlas-support-chat-frame"
                  data-part="frame"
                  title="Tuist support chat"
                  loading="lazy"
                ></iframe>
              </section>
              <button
                type="button"
                data-part="trigger"
                aria-controls="atlas-support-chat-frame"
                aria-expanded="false"
              >
                <svg data-part="trigger-icon" viewBox="0 0 24 24" aria-hidden="true" fill="none">
                  <path d="M6.32716 4.87046C10.1061 2.43419 15.3212 2.72689 18.7315 5.6351C22.287 8.66848 22.7878 13.6223 19.8525 17.1839C17.005 20.6391 11.8197 21.6954 7.61231 19.7845L3.15626 20.7337C2.89315 20.7897 2.61969 20.6999 2.44044 20.4994C2.26156 20.2989 2.20322 20.018 2.28809 19.763L3.47462 16.2025C1.16992 12.4536 2.23681 7.76079 5.96583 5.1146L6.32716 4.87046ZM17.7578 6.77573C14.768 4.22656 10.0839 4.03307 6.83399 6.33823L6.83302 6.33725C3.61661 8.61989 2.8411 12.604 4.92091 15.68C5.05151 15.8732 5.08544 16.1161 5.01173 16.3373L4.12599 18.9935L7.54395 18.2669L7.667 18.2503C7.79083 18.2449 7.91468 18.2709 8.02735 18.3255C11.6971 20.1071 16.2649 19.1789 18.6953 16.2298C21.0919 13.3215 20.7122 9.29727 17.7578 6.77671V6.77573Z" fill="currentColor" />
                </svg>
                <span data-part="trigger-label-wrap"><span data-part="trigger-label-clip"><span data-part="trigger-label">Get help</span></span></span>
              </button>
            `;

            this.panel = this.shadowRoot.querySelector('[data-part="panel"]');
            this.backdrop = this.shadowRoot.querySelector('[data-part="backdrop"]');
            this.loader = this.shadowRoot.querySelector('[data-part="loader"]');
            this.frame = this.shadowRoot.querySelector('[data-part="frame"]');
            this.trigger = this.shadowRoot.querySelector('[data-part="trigger"]');
            this.handleMessage = this.handleMessage.bind(this);
            this.handleViewportResize = this.handleViewportResize.bind(this);
            this.handleDocumentClick = this.handleDocumentClick.bind(this);

            this.trigger.addEventListener("click", () => this.toggle());
            this.backdrop.addEventListener("click", () => this.close(false));

            // One theme decision for panel chrome (via color-scheme, which
            // light-dark() resolves against) and the chat iframe (via the
            // theme param): the host page's declared scheme wins, the OS
            // preference fills in when the host declares none.
            this.themeMedia = window.matchMedia("(prefers-color-scheme: dark)");
            this.syncScheme = () => {
              this.dark = this.computeDark();
              this.style.colorScheme = this.dark ? "dark" : "light";
              this.postTheme();
            };
            this.themeMedia.addEventListener("change", this.syncScheme);
            this.syncScheme();
            window.addEventListener("message", this.handleMessage);
            window.addEventListener("resize", this.handleViewportResize);
            document.addEventListener("click", this.handleDocumentClick);
          }

          disconnectedCallback() {
            clearTimeout(this.revealTimer);
            window.removeEventListener("message", this.handleMessage);
            window.removeEventListener("resize", this.handleViewportResize);
            document.removeEventListener("click", this.handleDocumentClick);
            this.themeMedia.removeEventListener("change", this.syncScheme);
          }

          postTheme() {
            // Keep an already-loaded chat frame in sync when the theme flips.
            if (!this.frame || !this.frame.src || !this.frame.contentWindow) return;

            this.frame.contentWindow.postMessage(
              {type: "atlas-support-chat-theme", theme: this.dark ? "dark" : "light"},
              this.atlasOrigin
            );
          }

          computeDark() {
            // Clear our own override so the measurement sees the scheme the
            // host page hands down, not the value we set last time.
            this.style.colorScheme = "";
            const scheme = getComputedStyle(this).colorScheme || "normal";
            if (scheme.includes("dark") && !scheme.includes("light")) return true;
            if (scheme.includes("light") && !scheme.includes("dark")) return false;
            return this.themeMedia.matches;
          }

          handleDocumentClick(event) {
            if (this.panel.hidden) return;
            if (event.composedPath().includes(this)) return;
            this.close(false);
          }

          toggle() {
            const open = this.panel.hidden;

            if (open) {
              this.panel.hidden = false;
              this.backdrop.hidden = false;
              this.trigger.setAttribute("aria-expanded", "true");
              if (!this.frame.src) this.loadChat();
            } else {
              this.close();
            }
          }

          close(focusTrigger = true) {
            if (this.panel.hidden) return;

            this.panel.hidden = true;
            this.backdrop.hidden = true;
            this.trigger.setAttribute("aria-expanded", "false");
            if (focusTrigger) this.trigger.focus();
          }

          loadChat() {
            const url = new URL("/support/chat", this.atlasOrigin);
            url.searchParams.set("source", window.location.href);
            url.searchParams.set("parent_origin", window.location.origin);
            // Hand the widget's resolved theme to the chat page, so panel
            // chrome and iframe content agree in every browser (Safari lacks
            // Chrome's embedder color-scheme inheritance).
            url.searchParams.set("theme", this.dark ? "dark" : "light");

            const conversation = this.readConversation();
            if (conversation) url.searchParams.set("conversation", conversation);

            this.panel.dataset.loading = "";
            this.loader.hidden = false;
            // Hard cap so the skeleton can never get stuck if neither the
            // resize handshake nor the frame's load event arrives.
            this.revealTimer = setTimeout(() => this.revealChat(), 4000);
            this.frame.addEventListener(
              "load",
              () => {
                // Faster fallback once the page is in but the handshake is not.
                clearTimeout(this.revealTimer);
                this.revealTimer = setTimeout(() => this.revealChat(), 1200);
              },
              {once: true}
            );
            this.frame.src = url.toString();
          }

          revealChat() {
            clearTimeout(this.revealTimer);
            delete this.panel.dataset.loading;
            this.loader.hidden = true;
          }

          resizePanel(height) {
            this.lastPanelHeight = height;
            // The phone drawer carries safe-area padding inside its border
            // box; without adding it the iframe ends up shorter than the page
            // and the bottom of the form gets cut.
            const styles = getComputedStyle(this.panel);
            const padding = (parseFloat(styles.paddingTop) || 0) + (parseFloat(styles.paddingBottom) || 0);
            // Grows with the conversation up to 700px so long threads keep
            // more context in view, bounded by the viewport minus the host's
            // bottom inset, the trigger, the 12px gap, and headroom above.
            const maxHeight = Math.min(700, window.innerHeight - 108);
            this.panel.style.height = `${Math.min(height + padding, maxHeight)}px`;
          }

          handleViewportResize() {
            if (this.lastPanelHeight) this.resizePanel(this.lastPanelHeight);
          }

          readConversation() {
            try {
              return window.localStorage.getItem(this.storageKey);
            } catch (_) {
              return null;
            }
          }

          writeConversation(token) {
            try {
              window.localStorage.setItem(this.storageKey, token);
            } catch (_) {
              // Privacy modes can reject persistent storage. The open frame still works.
            }
          }

          handleMessage(event) {
            if (event.origin !== this.atlasOrigin) return;

            if (event.data?.type === "atlas-support-chat-resize" && Number.isFinite(event.data.height)) {
              // Measurements from a closed panel reflect the hidden iframe,
              // not real content size.
              if (this.panel.hidden || event.data.height <= 0) return;

              this.revealChat();
              this.resizePanel(event.data.height);
              return;
            }

            if (event.data?.type === "atlas-support-chat-close") {
              this.close();
              return;
            }

            if (event.data?.type !== "atlas-support-chat-session") return;
            if (typeof event.data.conversation !== "string" || event.data.conversation.length === 0) return;

            this.writeConversation(event.data.conversation);
          }
        }

        customElements.define("atlas-support-chat", AtlasSupportChat);
      }

      if (document.querySelector('[data-part="atlas-support-chat"]')) return;

      const chat = document.createElement("atlas-support-chat");
      chat.dataset.part = "atlas-support-chat";
      chat.dataset.endpoint = atlasOrigin;
      document.body.append(chat);
    })();
    """
  end
end
