require 'net/http'
require 'tempfile'
require 'shellwords'

module Cucumber
  module Formatter
    class HTTPIO
      class << self
        # Returns an IO that will write to a HTTP request's body
        # https_verify_mode can be set to OpenSSL::SSL::VERIFY_NONE
        # to ignore unsigned certificate - setting to nil will verify the certificate
        def open(url, https_verify_mode = nil, reporter = nil)
          @https_verify_mode = https_verify_mode
          uri, method, headers = CurlOptionParser.parse(url)
          IOHTTPBuffer.new(uri, method, headers, https_verify_mode, reporter)
        end
      end
    end

    class CurlOptionParser
      def self.parse(options)
        args = Shellwords.split(options)

        url = nil
        http_method = 'PUT'
        headers = {}

        until args.empty?
          arg = args.shift
          case arg
          when '-X', '--request'
            http_method = remove_arg_for(args, arg)
          when '-H'
            header_arg = remove_arg_for(args, arg)
            headers = headers.merge(parse_header(header_arg))
          else
            raise StandardError, "#{options} was not a valid curl command. Can't set url to #{arg} it is already set to #{url}" if url
            url = arg
          end
        end
        raise StandardError, "#{options} was not a valid curl command" unless url

        [
          url,
          http_method,
          headers
        ]
      end

      def self.remove_arg_for(args, arg)
        return args.shift unless args.empty?
        raise StandardError, "Missing argument for #{arg}"
      end

      def self.parse_header(header_arg)
        parts = header_arg.split(':', 2)
        raise StandardError, "#{header_arg} was not a valid header" unless parts.length == 2
        { parts[0].strip => parts[1].strip }
      end
    end

    class IOHTTPBuffer
      attr_reader :uri, :method, :headers

      def initialize(uri, method, headers = {}, https_verify_mode = nil, reporter = nil)
        @uri = URI(uri)
        @method = method
        @headers = headers
        @write_io = Tempfile.new('cucumber', encoding: 'UTF-8')
        @https_verify_mode = https_verify_mode
        @reporter = reporter || NoReporter.new
      end

      def close
        response = send_content(@uri, @method, @headers)
        @reporter.report(response.body)
        @write_io.close
        return if response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
        raise StandardError, "request to #{uri} failed with status #{response.code}"
      end

      def write(data)
        @write_io.write(data)
      end

      def flush
        @write_io.flush
      end

      def closed?
        @write_io.closed?
      end

      private

      def send_content(uri, method, headers, attempt = 10)
        content = (method == 'GET' ? StringIO.new : @write_io)
        http = build_client(uri, @https_verify_mode)

        raise StandardError, "request to #{uri} failed (too many redirections)" if attempt <= 0
        req = build_request(
          uri,
          method,
          headers.merge(
            'Content-Length' => content.size.to_s
          )
        )

        content.rewind
        req.body_stream = content

        begin
          response = http.request(req)
        rescue SystemCallError
          # We may get the redirect response before pushing the file.
          response = http.request(build_request(uri, method, headers))
        end

        case response
        when Net::HTTPAccepted
          send_content(URI(response['Location']), 'PUT', {}, attempt - 1) if response['Location']
        when Net::HTTPRedirection
          send_content(URI(response['Location']), method, headers, attempt - 1)
        end
        response
      end

      def build_request(uri, method, headers)
        method_class_name = "#{method[0].upcase}#{method[1..-1].downcase}"
        req = Net::HTTP.const_get(method_class_name).new(uri)
        headers.each do |header, value|
          req[header] = value
        end
        req
      end

      def build_client(uri, https_verify_mode)
        http = Net::HTTP.new(uri.hostname, uri.port)
        if uri.scheme == 'https'
          http.use_ssl = true
          http.verify_mode = https_verify_mode if https_verify_mode
        end
        http
      end
    end
  end
end
