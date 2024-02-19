# typed: true
# frozen_string_literal: true

class ResponseRequestIdMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)

    # Get the x-request-id header from the request
    request_id = env['HTTP_X_REQUEST_ID']

    # Set the x-request-id header in the response
    headers['X-Request-Id'] = request_id if request_id

    [status, headers, body]
  end
end
