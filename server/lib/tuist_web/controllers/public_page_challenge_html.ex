defmodule TuistWeb.PublicPageChallengeHTML do
  @moduledoc ~S"""
  Renders the Turnstile challenge page shown at
  `GET /turnstile-challenge`. Kept intentionally self-contained: no
  LiveView, no LayoutLive, no dashboard chrome. The page loads
  Cloudflare's `api.js`, renders a widget bound to the
  `public_page_challenge` action, and posts the token back to the
  controller inside a CSRF-protected form.

  The inline script deliberately mirrors the shape of
  `server/assets/app/js/Turnstile.js`. This page runs OUTSIDE the
  LiveView bundle, so we cannot rely on `phx-hook`; carrying the
  same explicit-render + onload-callback contract keeps the fallback
  in step with the widget the signup flow uses.
  """
  use TuistWeb, :html

  def render("show.html", assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="robots" content="noindex, nofollow" />
        <title>{dgettext("dashboard_auth", "Verify you're human")}</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
            background: #f5f5f7;
            color: #1d1d1f;
          }
          .card {
            background: #ffffff;
            border-radius: 16px;
            padding: 32px 28px;
            width: min(420px, 92vw);
            box-shadow: 0 12px 32px rgba(0, 0, 0, 0.06);
            text-align: center;
          }
          .card h1 {
            font-size: 20px;
            margin: 0 0 8px 0;
          }
          .card p {
            margin: 0 0 20px 0;
            color: #4b4b4f;
            font-size: 14px;
          }
          .widget {
            display: flex;
            justify-content: center;
            margin: 16px 0;
          }
          .error {
            color: #b3261e;
            font-size: 13px;
            margin-top: 12px;
          }
          .fallback {
            font-size: 12px;
            color: #86868b;
            margin-top: 16px;
          }
          button {
            font: inherit;
            border: none;
            background: #0071e3;
            color: #ffffff;
            padding: 10px 18px;
            border-radius: 999px;
            cursor: pointer;
          }
          button[disabled] {
            background: #a0a0a0;
            cursor: not-allowed;
          }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>{dgettext("dashboard_auth", "Just a quick check")}</h1>
          <p>
            {dgettext(
              "dashboard_auth",
              "Public dashboards are protected against automated scraping. Confirm you're human to continue."
            )}
          </p>

          <form method="post" action={@verify_path} id="public-page-challenge-form">
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <input type="hidden" name="return_to" value={@return_to || "/"} />
            <input type="hidden" name="cf-turnstile-response" id="turnstile-response" value="" />

            <div
              :if={@turnstile_required? and is_binary(@turnstile_site_key)}
              id="turnstile-widget"
              class="widget"
              data-sitekey={@turnstile_site_key}
              data-action={@expected_action}
            >
            </div>

            <div :if={not @turnstile_required? or not is_binary(@turnstile_site_key)} class="fallback">
              {dgettext(
                "dashboard_auth",
                "Turnstile is unavailable. Please try again shortly."
              )}
            </div>

            <p :if={@error} class="error" role="alert">{@error}</p>

            <button type="submit" id="public-page-challenge-submit" disabled>
              {dgettext("dashboard_auth", "Continue")}
            </button>
          </form>
        </div>

        <script :if={@turnstile_required? and is_binary(@turnstile_site_key)} nonce={get_csp_nonce()}>
          (function () {
            var API_URL = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
            var ONLOAD_CALLBACK = "__tuistPublicPageChallengeOnLoad";
            var container = document.getElementById("turnstile-widget");
            var responseInput = document.getElementById("turnstile-response");
            var submitButton = document.getElementById("public-page-challenge-submit");
            var form = document.getElementById("public-page-challenge-form");

            function setSubmitEnabled(enabled) {
              if (submitButton) submitButton.disabled = !enabled;
            }

            window[ONLOAD_CALLBACK] = function () {
              if (!window.turnstile || !container) return;
              try {
                window.turnstile.render(container, {
                  sitekey: container.dataset.sitekey,
                  action: container.dataset.action,
                  "response-field": false,
                  callback: function (token) {
                    if (responseInput) responseInput.value = token;
                    setSubmitEnabled(true);
                    if (form && typeof form.requestSubmit === "function") {
                      form.requestSubmit();
                    } else if (form) {
                      form.submit();
                    }
                  },
                  "expired-callback": function () {
                    if (responseInput) responseInput.value = "";
                    setSubmitEnabled(false);
                  },
                  "error-callback": function () {
                    if (responseInput) responseInput.value = "";
                    setSubmitEnabled(false);
                  },
                  "timeout-callback": function () {
                    if (responseInput) responseInput.value = "";
                    setSubmitEnabled(false);
                  }
                });
              } catch (_e) {
                setSubmitEnabled(false);
              }
            };

            var script = document.createElement("script");
            script.src = API_URL + "&onload=" + ONLOAD_CALLBACK;
            script.async = true;
            script.defer = true;
            script.onerror = function () { setSubmitEnabled(false); };
            document.head.appendChild(script);
          })();
        </script>
      </body>
    </html>
    """
  end
end
