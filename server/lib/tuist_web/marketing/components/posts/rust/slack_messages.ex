defmodule TuistWeb.Marketing.Components.Posts.Rust.SlackMessages do
  @moduledoc """
  Renders two Slack messages from the Tuist app as Slack shows them: the daily
  report that `Tuist.Slack.Reports.report/2` built from the Codex test runs in
  the Rust post, and an example of the message the default flaky-test
  automation posts.
  """
  use TuistWeb, :live_component

  def render(assigns) do
    ~H"""
    <figure data-part="slack-messages" data-variant="slack">
      <style :type={TuistWeb.ColocatedCSS}>
        #marketing-blog-post figure[data-part="slack-messages"][data-variant="slack"] {
          margin: var(--noora-spacing-7) 0;
          border-radius: var(--noora-radius-3);
          border: 1px solid light-dark(#e6e6e6, #3d3f42);
          background: light-dark(#ffffff, #1a1d21);
          color: light-dark(#1d1c1d, #d1d2d3);
          font-family: "Lato", "Slack-Lato", -apple-system, system-ui, sans-serif;
          font-size: 15px;
          line-height: 1.46;
          overflow: hidden;

          & p {
            margin: 0;
            padding: 0;
          }

          & a[href],
          & [data-part="link"] {
            color: light-dark(#1264a3, #1d9bd1);
            text-decoration: none;
          }

          & [data-part="channel"] {
            display: flex;
            align-items: center;
            gap: 6px;
            padding: 10px 20px;
            border-bottom: 1px solid light-dark(#e6e6e6, #3d3f42);
            font-weight: 900;
            font-size: 16px;
          }

          & [data-part="channel"] span {
            color: light-dark(#616061, #ababad);
            font-weight: 400;
          }

          & [data-part="message"] {
            display: flex;
            gap: 12px;
            padding: 14px 20px;
          }

          & [data-part="message"] + [data-part="message"] {
            border-top: 1px solid light-dark(#f0f0f0, #2c2e33);
          }

          & img[data-part="avatar"] {
            flex-shrink: 0;
            width: 36px;
            max-width: 36px;
            height: 36px;
            margin: 0;
            padding: 6px;
            border-radius: 6px;
            background: light-dark(#f4f1fe, #2a2540);
            box-shadow: none;
            box-sizing: border-box;
          }

          & [data-part="content"] {
            flex: 1;
            min-width: 0;
          }

          & [data-part="author"] {
            display: flex;
            align-items: baseline;
            gap: 6px;
            margin-bottom: 2px;
          }

          & [data-part="name"] {
            font-weight: 900;
          }

          & [data-part="app-badge"] {
            padding: 0 3px;
            border-radius: 2px;
            background: light-dark(rgba(29, 28, 29, 0.13), rgba(232, 232, 232, 0.13));
            color: light-dark(#616061, #ababad);
            font-size: 10px;
            font-weight: 700;
            line-height: 1.4;
          }

          & [data-part="time"],
          & [data-part="context"] {
            color: light-dark(#616061, #ababad);
            font-size: 12px;
          }

          & [data-part="header"] {
            margin: 4px 0 2px;
            font-size: 18px;
            font-weight: 900;
            line-height: 1.33;
          }

          & [data-part="context"] {
            margin: 4px 0;
          }

          & hr[data-part="divider"] {
            margin: 10px 0;
            border: 0;
            border-top: 1px solid light-dark(#dddddd, #3d3f42);
          }

          & [data-part="section"] {
            margin: 6px 0;
          }

          & code {
            padding: 1px 3px;
            border-radius: 3px;
            border: 1px solid light-dark(rgba(29, 28, 29, 0.13), rgba(232, 232, 232, 0.13));
            background: light-dark(rgba(29, 28, 29, 0.04), rgba(232, 232, 232, 0.04));
            color: light-dark(#e01e5a, #e8912d);
            font-size: 12px;
          }
        }
      </style>
      <div data-part="channel"># codex-ci <span>· Tuist</span></div>
      <div data-part="message">
        <img data-part="avatar" src="/marketing/images/brand/tuist-logo.svg" alt="Tuist" />
        <div data-part="content">
          <div data-part="author">
            <span data-part="name">Tuist</span>
            <span data-part="app-badge">APP</span>
            <span data-part="time">12:05 PM</span>
          </div>
          <p data-part="header">Daily codex Report</p>
          <p data-part="context">
            Report period: Nov 12, 12:05 PM - Nov 13, 12:05 PM<br />
            Previous period: Nov 11, 12:05 PM - Nov 12, 12:05 PM
          </p>
          <hr data-part="divider" />
          <p data-part="section"><b>🧪 Test Duration</b><br />Local: 336ms</p>
          <p data-part="context"><span data-part="link">View analytics</span></p>
        </div>
      </div>
      <div data-part="message">
        <img data-part="avatar" src="/marketing/images/brand/tuist-logo.svg" alt="Tuist" />
        <div data-part="content">
          <div data-part="author">
            <span data-part="name">Tuist</span>
            <span data-part="app-badge">APP</span>
            <span data-part="time">12:18 PM</span>
          </div>
          <p data-part="header">🤖 Auto-quarantine flaky tests</p>
          <p data-part="section">
            ⚠️ <b>cancel_exits_run</b>
            in module <code>codex-file-search</code>
            has been detected as flaky by automation <b>Auto-quarantine flaky tests</b>.
          </p>
          <p data-part="section"><span data-part="link">View test case</span></p>
        </div>
      </div>
    </figure>
    """
  end
end
