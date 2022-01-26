module Cucumber
  module HTMLFormatter
    class AssetsLoader
      def template
        read_asset('index.mustache.html')
      end

      def css
        read_asset('cucumber-react.css')
      end

      def script
        read_asset('cucumber-html.js')
      end

      private

      def read_asset(name)
        File.read(File.join(assets_path, name))
      end

      def assets_path
        "#{html_formatter_path}/assets"
      end

      def html_formatter_path
        Gem.loaded_specs['cucumber-html-formatter'].full_gem_path
      rescue
        '.'
      end

    end
  end
end