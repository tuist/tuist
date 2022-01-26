# frozen_string_literal: true

require "action_dispatch/http/request"

module ActionDispatch
  # This middleware guards from DNS rebinding attacks by explicitly permitting
  # the hosts a request can be sent to, and is passed the options set in
  # +config.host_authorization+.
  #
  # Requests can opt-out of Host Authorization with +exclude+:
  #
  #    config.host_authorization = { exclude: ->(request) { request.path =~ /healthcheck/ } }
  #
  # When a request comes to an unauthorized host, the +response_app+
  # application will be executed and rendered. If no +response_app+ is given, a
  # default one will run, which responds with <tt>403 Forbidden</tt>.
  class HostAuthorization
    ALLOWED_HOSTS_IN_DEVELOPMENT = [".localhost", IPAddr.new("0.0.0.0/0"), IPAddr.new("::/0")]
    PORT_REGEX = /(?::\d+)/ # :nodoc:
    IPV4_HOSTNAME = /(?<host>\d+\.\d+\.\d+\.\d+)#{PORT_REGEX}?/ # :nodoc:
    IPV6_HOSTNAME = /(?<host>[a-f0-9]*:[a-f0-9.:]+)/i # :nodoc:
    IPV6_HOSTNAME_WITH_PORT = /\[#{IPV6_HOSTNAME}\]#{PORT_REGEX}/i # :nodoc:
    VALID_IP_HOSTNAME = Regexp.union( # :nodoc:
      /\A#{IPV4_HOSTNAME}\z/,
      /\A#{IPV6_HOSTNAME}\z/,
      /\A#{IPV6_HOSTNAME_WITH_PORT}\z/,
    )

    class Permissions # :nodoc:
      def initialize(hosts)
        @hosts = sanitize_hosts(hosts)
      end

      def empty?
        @hosts.empty?
      end

      def allows?(host)
        @hosts.any? do |allowed|
          if allowed.is_a?(IPAddr)
            begin
              allowed === extract_hostname(host)
            rescue
              # IPAddr#=== raises an error if you give it a hostname instead of
              # IP. Treat similar errors as blocked access.
              false
            end
          else
            allowed === host
          end
        end
      end

      private
        def sanitize_hosts(hosts)
          Array(hosts).map do |host|
            case host
            when Regexp then sanitize_regexp(host)
            when String then sanitize_string(host)
            else host
            end
          end
        end

        def sanitize_regexp(host)
          /\A#{host}#{PORT_REGEX}?\z/
        end

        def sanitize_string(host)
          if host.start_with?(".")
            /\A([a-z0-9-]+\.)?#{Regexp.escape(host[1..-1])}#{PORT_REGEX}?\z/i
          else
            /\A#{Regexp.escape host}#{PORT_REGEX}?\z/i
          end
        end

        def extract_hostname(host)
          host.slice(VALID_IP_HOSTNAME, "host") || host
        end
    end

    DEFAULT_RESPONSE_APP = -> env do
      request = Request.new(env)

      format = request.xhr? ? "text/plain" : "text/html"
      template = DebugView.new(host: request.host)
      body = template.render(template: "rescues/blocked_host", layout: "rescues/layout")

      [403, {
        "Content-Type" => "#{format}; charset=#{Response.default_charset}",
        "Content-Length" => body.bytesize.to_s,
      }, [body]]
    end

    def initialize(app, hosts, deprecated_response_app = nil, exclude: nil, response_app: nil)
      @app = app
      @permissions = Permissions.new(hosts)
      @exclude = exclude

      unless deprecated_response_app.nil?
        ActiveSupport::Deprecation.warn(<<-MSG.squish)
          `action_dispatch.hosts_response_app` is deprecated and will be ignored in Rails 6.2.
          Use the Host Authorization `response_app` setting instead.
        MSG

        response_app ||= deprecated_response_app
      end

      @response_app = response_app || DEFAULT_RESPONSE_APP
    end

    def call(env)
      return @app.call(env) if @permissions.empty?

      request = Request.new(env)

      if authorized?(request) || excluded?(request)
        mark_as_authorized(request)
        @app.call(env)
      else
        @response_app.call(env)
      end
    end

    private
      def authorized?(request)
        origin_host = request.get_header("HTTP_HOST")
        forwarded_host = request.x_forwarded_host&.split(/,\s?/)&.last

        @permissions.allows?(origin_host) && (forwarded_host.blank? || @permissions.allows?(forwarded_host))
      end

      def excluded?(request)
        @exclude && @exclude.call(request)
      end

      def mark_as_authorized(request)
        request.set_header("action_dispatch.authorized_host", request.host)
      end
  end
end
