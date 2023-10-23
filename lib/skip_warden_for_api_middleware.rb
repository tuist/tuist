class SkipWardenForAPIMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    if env['PATH_INFO'].start_with?('/api')
      env['warden'].config.intercept_401 = false
    end
    @app.call(env)
  end
end
