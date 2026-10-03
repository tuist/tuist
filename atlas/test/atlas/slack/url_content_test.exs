defmodule Atlas.Slack.URLContentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Slack.URLContent

  setup :verify_on_exit!

  test "fetches and normalizes public HTML content" do
    Req
    |> expect(:run, fn %Req.Request{} = request ->
      assert URI.to_string(request.url) == "https://example.com/docs"
      assert request.options.receive_timeout == 10_000
      assert request.options.redirect == false
      assert request.options.max_redirects == 0

      assert request.headers["accept"] == [
               "text/html, text/plain;q=0.9, text/markdown;q=0.9, application/json;q=0.8, application/xml;q=0.7, text/xml;q=0.7"
             ]

      {request,
       %Req.Response{
         status: 200,
         headers: %{"content-type" => ["text/html; charset=utf-8"]},
         body: """
         <html>
           <head>
             <title>Toss Docs</title>
             <style>body { color: red; }</style>
           </head>
           <body>
             <h1>Setup</h1>
             <p>Use the domain <strong>toss.im</strong>.</p>
             <ul><li>Create the account</li><li>Send pricing</li></ul>
           </body>
         </html>
         """
       }}
    end)

    assert {:ok, result} = URLContent.fetch("https://example.com/docs")
    assert result.final_url == "https://example.com/docs"
    assert result.content_type == "text/html"
    assert result.title == "Toss Docs"
    assert result.redirects_followed == 0
    assert result.truncated == false
    assert result.content =~ "Setup"
    assert result.content =~ "Use the domain toss.im."
    assert result.content =~ "- Create the account"
  end

  test "follows public redirects before returning content" do
    Req
    |> stub(:run, fn %Req.Request{} = request ->
      case URI.to_string(request.url) do
        "https://example.com/start" ->
          {request,
           %Req.Response{
             status: 302,
             headers: %{"location" => ["/final"]},
             body: ""
           }}

        "https://example.com/final" ->
          {request,
           %Req.Response{
             status: 200,
             headers: %{"content-type" => ["text/plain"]},
             body: "Final page"
           }}
      end
    end)

    assert {:ok, result} = URLContent.fetch("https://example.com/start")
    assert result.final_url == "https://example.com/final"
    assert result.redirects_followed == 1
    assert result.content == "Final page"
  end

  test "rejects local hosts without issuing a request" do
    Req
    |> reject(:run, 1)

    assert {:error, message} = URLContent.fetch("https://localhost/private")
    assert message =~ "local or private network host"
  end

  test "rejects private IP literals without issuing a request" do
    Req
    |> reject(:run, 1)

    assert {:error, message} = URLContent.fetch("http://192.168.1.20/secret")
    assert message =~ "local or private network host"
  end

  test "rejects unsupported content types" do
    Req
    |> expect(:run, fn %Req.Request{} = request ->
      {request,
       %Req.Response{
         status: 200,
         headers: %{"content-type" => ["application/pdf"]},
         body: "%PDF-1.7"
       }}
    end)

    assert {:error, message} = URLContent.fetch("https://example.com/file.pdf")
    assert message =~ "Unsupported content type application/pdf"
  end
end
