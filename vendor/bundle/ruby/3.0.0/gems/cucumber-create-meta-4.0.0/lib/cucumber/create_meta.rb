require 'uri'
require 'cucumber/messages'
require 'sys/uname'
require 'json'

module Cucumber
  module CreateMeta
    CI_DICT = JSON.parse(IO.read(File.join(File.dirname(__FILE__), "ciDict.json")))

    def create_meta(tool_name, tool_version, env = ENV)
      Cucumber::Messages::Meta.new(
          protocol_version: Cucumber::Messages::VERSION,
          implementation: Cucumber::Messages::Meta::Product.new(
              name: tool_name,
              version: tool_version
          ),
          runtime: Cucumber::Messages::Meta::Product.new(
              name: RUBY_ENGINE,
              version: RUBY_VERSION
          ),
          os: Cucumber::Messages::Meta::Product.new(
              name: RbConfig::CONFIG['target_os'],
              version: Sys::Uname.uname.version
          ),
          cpu: Cucumber::Messages::Meta::Product.new(
              name: RbConfig::CONFIG['target_cpu']
          ),
          ci: detect_ci(env)
      )
    end

    def detect_ci(env)
      detected = CI_DICT.map do |ci_name, ci_system|
        create_ci(ci_name, ci_system, env)
      end.compact

      detected.length == 1 ? detected[0] : nil
    end

    def create_ci(ci_name, ci_system, env)
      url = evaluate(ci_system['url'], env)
      return nil if url.nil?

      Cucumber::Messages::Meta::CI.new(
          url: url,
          name: ci_name,
          git: Cucumber::Messages::Meta::CI::Git.new(
              remote: remove_userinfo_from_url(evaluate(ci_system['git']['remote'], env)),
              revision: evaluate(ci_system['git']['revision'], env),
              branch: evaluate(ci_system['git']['branch'], env),
              tag: evaluate(ci_system['git']['tag'], env),
          )
      )
    end

    def evaluate(template, env)
      return nil if template.nil?
      begin
        template.gsub(/\${((refbranch|reftag)\s+)?([^\s}]+)(\s+\|\s+([^}]+))?}/) do
          func = $2
          variable = $3
          default_value = $5 == "" ? nil : $5
          value = env[variable] || default_value

          if func == 'refbranch'
            value = group1(value, /^refs\/heads\/(.*)/)
          elsif func == 'reftag'
            value = group1(value, /^refs\/tags\/(.*)/)
          end
          raise "Undefined variable: #{variable}" if value.nil?
          value
        end
      rescue
        nil
      end
    end

    def group1(value, regexp)
      m = value.match(regexp)
      raise "No match" if m.nil?
      m[1]
    end

    def remove_userinfo_from_url(value)
      return nil if value.nil?
      begin
        uri = URI(value)
        uri.userinfo = ''
        uri.to_s
      rescue
        value
      end
    end

    module_function :create_meta, :detect_ci, :create_ci, :group1, :evaluate, :remove_userinfo_from_url
  end
end
