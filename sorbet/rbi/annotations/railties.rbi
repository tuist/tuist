# typed: true

# DO NOT EDIT MANUALLY
# This file was pulled from a central RBI files repository.
# Please run `bin/tapioca annotations` to update it.

module Rails
  class << self
    sig { returns(Rails::Application) }
    def application; end

    sig { returns(ActiveSupport::BacktraceCleaner) }
    def backtrace_cleaner; end

    sig { returns(ActiveSupport::Cache::Store) }
    def cache; end

    sig { returns(ActiveSupport::EnvironmentInquirer) }
    def env; end

    sig { returns(ActiveSupport::ErrorReporter) }
    def error; end

    sig { returns(ActiveSupport::Logger) }
    def logger; end

    sig { returns(Pathname) }
    def root; end

    sig { returns(String) }
    def version; end
  end
end

class Rails::Application < ::Rails::Engine
  class << self
    sig { params(block: T.proc.bind(Rails::Application).void).void }
    def configure(&block); end
  end

  sig { params(block: T.proc.bind(Rails::Application).void).void }
  def configure(&block); end

  sig { returns(T.untyped) }
  def config; end
end

class Rails::Engine < ::Rails::Railtie
  sig { params(block: T.untyped).returns(ActionDispatch::Routing::RouteSet) }
  def routes(&block); end
end

class Rails::Railtie
  sig { params(block: T.proc.bind(Rails::Railtie).void).void }
  def configure(&block); end
end

class Rails::Railtie::Configuration
  sig { params(blk: T.proc.bind(ActiveSupport::Reloader).void).void }
  def to_prepare(&blk); end
end
