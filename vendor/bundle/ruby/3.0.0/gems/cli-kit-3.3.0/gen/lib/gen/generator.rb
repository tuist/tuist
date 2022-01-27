require 'gen'
require 'fileutils'
require 'open3'
require 'pathname'
require 'tmpdir'

module Gen
  class Generator
    def self.run(project_name)
      new(project_name).run
    end

    TEMPLATE_ROOT = File.expand_path('gen/template', Gen::ROOT)

    VALID_PROJECT_NAME = /\A[a-z][a-z0-9]*\z/
    private_constant :VALID_PROJECT_NAME

    # false  -> delete file
    # string -> rename file before applying template substitutions
    VENDOR_TRANSLATIONS = {
      'Gemfile'            => false,
      'exe/__app__-gems'   => false,
      'exe/__app__-vendor' => 'exe/__app__',
      'dev-gems.yml'       => false,
      'dev-vendor.yml'     => 'dev.yml',
    }.freeze
    private_constant :VENDOR_TRANSLATIONS

    BUNDLER_TRANSLATIONS = {
      'bin/update-deps'    => false,
      'exe/__app__-gems'   => 'exe/__app__',
      'exe/__app__-vendor' => false,
      'dev-gems.yml'       => 'dev.yml',
      'dev-vendor.yml'     => false,
    }.freeze
    private_constant :BUNDLER_TRANSLATIONS

    def initialize(project_name)
      raise(
        CLI::Kit::Abort,
        "project name must match {{bold:#{VALID_PROJECT_NAME}}} (but can be changed later)"
      ) unless project_name =~ VALID_PROJECT_NAME
      @project_name = project_name
      @title_case_project_name = @project_name.sub(/^./, &:upcase)
    end

    def run
      vendor = ask_vendor?
      create_project_dir
      if vendor
        copy_files(translations: VENDOR_TRANSLATIONS)
        update_deps
      else
        copy_files(translations: BUNDLER_TRANSLATIONS)
      end
    end

    private

    def ask_vendor?
      return 'vendor' if ENV['DEPS'] == 'vendor'
      return 'bundler' if ENV['DEPS'] == 'bundler'

      vendor = nil
      CLI::UI::Frame.open('Configuration') do
        q = 'How would you like the application to consume {{command:cli-kit}} and {{command:cli-ui}}?'
        vendor = CLI::UI::Prompt.ask(q) do |c|
          c.option('Vendor  {{italic:(faster execution, more difficult to update deps)}}') { 'vendor' }
          c.option('Bundler {{italic:(slower execution, easier dep management)}}') { 'bundler' }
        end
      end
      vendor == 'vendor'
    end

    def create_project_dir
      info(create: '')
      FileUtils.mkdir(@project_name)
    rescue Errno::EEXIST
      error("directory already exists: #{@project_name}")
    end

    def copy_files(translations:)
      each_template_file do |source_name|
        target_name = translations.fetch(source_name, source_name)
        next if target_name == false
        target_name = apply_template_variables(target_name)

        source = File.join(TEMPLATE_ROOT, source_name)
        target = File.join(@project_name, target_name)

        info(create: target_name)

        if Dir.exist?(source)
          FileUtils.mkdir(target)
        else
          content = apply_template_variables(File.read(source))
          File.write(target, content)
        end
        File.chmod(File.stat(source).mode, target)
      end
    end

    def update_deps
      Dir.mktmpdir do |tmp|
        clone(tmp, 'cli-ui')
        clone(tmp, 'cli-kit')
        info(run: 'bin/update-deps')
        Dir.chdir(@project_name) do
          system({ 'SOURCE_ROOT' => tmp }, 'bin/update-deps')
        end
      end
    end

    def clone(dir, repo)
      info(clone: repo)
      out, stat = Open3.capture2e('git', '-C', dir, 'clone', "https://github.com/shopify/#{repo}")
      unless stat.success?
        STDERR.puts(out)
        error("git clone failed")
      end
    end

    def each_template_file
      return enum_for(:each_template_file) unless block_given?

      root = Pathname.new(TEMPLATE_ROOT)
      Dir.glob("#{TEMPLATE_ROOT}/**/*").each do |f|
        el = Pathname.new(f)
        yield(el.relative_path_from(root).to_s)
      end
    end

    def apply_template_variables(s)
      s
        .gsub(/__app__/, @project_name)
        .gsub(/__App__/, @title_case_project_name)
        .gsub(/__cli-kit-version__/, cli_kit_version)
        .gsub(/__cli-ui-version__/, cli_ui_version)
    end

    def cli_kit_version
      require 'cli/kit/version'
      CLI::Kit::VERSION.to_s
    end

    def cli_ui_version
      require 'cli/ui/version'
      CLI::UI::VERSION.to_s
    end

    def info(create: nil, clone: nil, run: nil)
      if clone
        puts(CLI::UI.fmt("\t{{bold:{{yellow:clone}}\t#{clone}}}"))
      elsif create
        puts(CLI::UI.fmt("\t{{bold:{{blue:create}}\t#{create}}}"))
      elsif run
        puts(CLI::UI.fmt("\t{{bold:{{green:run}}\t#{run}}}"))
      end
    end

    def error(msg)
      raise(CLI::Kit::Abort, msg)
    end
  end
end
