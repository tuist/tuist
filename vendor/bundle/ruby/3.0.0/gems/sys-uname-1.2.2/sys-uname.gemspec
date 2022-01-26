require 'rubygems'

Gem::Specification.new do |spec|
  spec.name       = 'sys-uname'
  spec.version    = '1.2.2'
  spec.author     = 'Daniel J. Berger'
  spec.email      = 'djberg96@gmail.com'
  spec.homepage   = 'http://github.com/djberg96/sys-uname'
  spec.summary    = 'An interface for returning uname (platform) information'
  spec.license    = 'Apache-2.0'
  spec.files      = Dir['**/*'].reject{ |f| f.include?('git') } 
  spec.test_files = Dir['spec/*_spec.rb']
  spec.cert_chain = ['certs/djberg96_pub.pem']

  spec.extra_rdoc_files = Dir['doc/*.rdoc']

  spec.add_dependency('ffi', '~> 1.1')
  spec.add_development_dependency('rspec', '~> 3.9')
  spec.add_development_dependency('rake')

  spec.metadata = {
    'homepage_uri'      => 'https://github.com/djberg96/sys-uname',
    'bug_tracker_uri'   => 'https://github.com/djberg96/sys-uname/issues',
    'changelog_uri'     => 'https://github.com/djberg96/sys-uname/blob/ffi/CHANGES.md',
    'documentation_uri' => 'https://github.com/djberg96/sys-uname/wiki',
    'source_code_uri'   => 'https://github.com/djberg96/sys-uname',
    'wiki_uri'          => 'https://github.com/djberg96/sys-uname/wiki'
  }

  spec.description = <<-EOF
    The sys-uname library provides an interface for gathering information
    about your current platform. The library is named after the Unix 'uname'
    command but also works on MS Windows. Available information includes
    OS name, OS version, system name and so on. Additional information is
    available for certain platforms.
  EOF
end
