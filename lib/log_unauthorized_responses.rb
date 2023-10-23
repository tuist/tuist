# frozen_string_literal: true

class LogUnauthorizedResponses
  def initialize(app, middleware_name = nil)
    @app = app
    @middleware_name = middleware_name
  end

  def call(env)
    status, headers, response = @app.call(env)

    if status == 401
      Rails.logger.warn("[401 Unauthorized] (After middlweare #{@middleware_name}) Path: #{env['REQUEST_PATH']}"\
        " Method: #{env['REQUEST_METHOD']}, Agent: #{env['HTTP_USER_AGENT']},"\
        " Origin: #{env['REMOTE_ADDR']}")

      if env['action_dispatch.exception']
        Rails.logger.warn(env['action_dispatch.exception'].backtrace.join("\n"))
      end
    end

    [status, headers, response]
  end
end
