class SkipWardenForAPIMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    if env['PATH_INFO'].start_with?('/api')
      # If it's an API endpoint, skip Warden's intercept_401 behavior
      # by directly calling the next middleware in the stack
      return @app.call(env)
    end

    @app.call(env)
  end
end
