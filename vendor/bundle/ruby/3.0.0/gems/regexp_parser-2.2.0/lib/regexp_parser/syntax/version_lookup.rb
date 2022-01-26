module Regexp::Syntax
  VERSION_FORMAT = '\Aruby/\d+\.\d+(\.\d+)?\z'
  VERSION_REGEXP = /#{VERSION_FORMAT}/
  VERSION_CONST_REGEXP = /\AV\d+_\d+(?:_\d+)?\z/

  class InvalidVersionNameError < Regexp::Syntax::SyntaxError
    def initialize(name)
      super "Invalid version name '#{name}'. Expected format is '#{VERSION_FORMAT}'"
    end
  end

  class UnknownSyntaxNameError < Regexp::Syntax::SyntaxError
    def initialize(name)
      super "Unknown syntax name '#{name}'."
    end
  end

  module_function

  # Loads and instantiates an instance of the syntax specification class for
  # the given syntax version name. The special names 'any' and '*' return an
  # instance of Syntax::Any.
  def new(name)
    return Regexp::Syntax::Any.new if ['*', 'any'].include?(name.to_s)
    version_class(name).new
  end

  def supported?(name)
    name =~ VERSION_REGEXP &&
      comparable_version(name) >= comparable_version('1.8.6')
  end

  def version_class(version)
    version =~ VERSION_REGEXP || raise(InvalidVersionNameError, version)
    version_const_name = version_const_name(version)
    const_get(version_const_name) || raise(UnknownSyntaxNameError, version)
  end

  def version_const_name(version_string)
    "V#{version_string.to_s.scan(/\d+/).join('_')}"
  end

  def const_missing(const_name)
    if const_name =~ VERSION_CONST_REGEXP
      return fallback_version_class(const_name)
    end
    super
  end

  def fallback_version_class(version)
    sorted_versions = (specified_versions + [version])
                      .sort_by { |name| comparable_version(name) }
    return if (version_index = sorted_versions.index(version)) < 1

    next_lower_version = sorted_versions[version_index - 1]
    inherit_from_version(next_lower_version, version)
  end

  def inherit_from_version(parent_version, new_version)
    new_const = version_const_name(new_version)
    parent = const_get(version_const_name(parent_version))
    const_defined?(new_const) || const_set(new_const, Class.new(parent))
    warn_if_future_version(new_const)
    const_get(new_const)
  end

  def specified_versions
    constants.select { |const_name| const_name =~ VERSION_CONST_REGEXP }
  end

  def comparable_version(name)
    # add .99 to treat versions without a patch value as latest patch version
    Gem::Version.new((name.to_s.scan(/\d+/) << 99).join('.'))
  end

  def warn_if_future_version(const_name)
    return if comparable_version(const_name) < comparable_version('4.0.0')

    warn('This library has only been tested up to Ruby 3.x, '\
         "but you are running with #{const_get(const_name).inspect}")
  end
end
