# -*- encoding: utf-8 -*-
# stub: sys-uname 1.2.2 ruby lib

Gem::Specification.new do |s|
  s.name = "sys-uname".freeze
  s.version = "1.2.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/djberg96/sys-uname/issues", "changelog_uri" => "https://github.com/djberg96/sys-uname/blob/ffi/CHANGES.md", "documentation_uri" => "https://github.com/djberg96/sys-uname/wiki", "homepage_uri" => "https://github.com/djberg96/sys-uname", "source_code_uri" => "https://github.com/djberg96/sys-uname", "wiki_uri" => "https://github.com/djberg96/sys-uname/wiki" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Daniel J. Berger".freeze]
  s.cert_chain = ["-----BEGIN CERTIFICATE-----\nMIIEcDCCAtigAwIBAgIBATANBgkqhkiG9w0BAQsFADA/MREwDwYDVQQDDAhkamJl\ncmc5NjEVMBMGCgmSJomT8ixkARkWBWdtYWlsMRMwEQYKCZImiZPyLGQBGRYDY29t\nMB4XDTE4MDMxODE1MjIwN1oXDTI4MDMxNTE1MjIwN1owPzERMA8GA1UEAwwIZGpi\nZXJnOTYxFTATBgoJkiaJk/IsZAEZFgVnbWFpbDETMBEGCgmSJomT8ixkARkWA2Nv\nbTCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBALgfaroVM6CI06cxr0/h\nA+j+pc8fgpRgBVmHFaFunq28GPC3IvW7Nvc3Y8SnAW7pP1EQIbhlwRIaQzJ93/yj\nu95KpkP7tA9erypnV7dpzBkzNlX14ACaFD/6pHoXoe2ltBxk3CCyyzx70mTqJpph\n75IB03ni9a8yqn8pmse+s83bFJOAqddSj009sGPcQO+QOWiNxqYv1n5EHcvj2ebO\n6hN7YTmhx7aSia4qL/quc4DlIaGMWoAhvML7u1fmo53CYxkKskfN8MOecq2vfEmL\niLu+SsVVEAufMDDFMXMJlvDsviolUSGMSNRTujkyCcJoXKYYxZSNtIiyd9etI0X3\nctu0uhrFyrMZXCedutvXNjUolD5r9KGBFSWH1R9u2I3n3SAyFF2yzv/7idQHLJJq\n74BMnx0FIq6fCpu5slAipvxZ3ZkZpEXZFr3cIBtO1gFvQWW7E/Y3ijliWJS1GQFq\n058qERadHGu1yu1dojmFRo6W2KZvY9al2yIlbkpDrD5MYQIDAQABo3cwdTAJBgNV\nHRMEAjAAMAsGA1UdDwQEAwIEsDAdBgNVHQ4EFgQUFZsMapgzJimzsbaBG2Tm8j5e\nAzgwHQYDVR0RBBYwFIESZGpiZXJnOTZAZ21haWwuY29tMB0GA1UdEgQWMBSBEmRq\nYmVyZzk2QGdtYWlsLmNvbTANBgkqhkiG9w0BAQsFAAOCAYEAW2tnYixXQtKxgGXq\n/3iSWG2bLwvxS4go3srO+aRXZHrFUMlJ5W0mCxl03aazxxKTsVVpZD8QZxvK91OQ\nh9zr9JBYqCLcCVbr8SkmYCi/laxIZxsNE5YI8cC8vvlLI7AMgSfPSnn/Epq1GjGY\n6L1iRcEDtanGCIvjqlCXO9+BmsnCfEVehqZkQHeYczA03tpOWb6pon2wzvMKSsKH\nks0ApVdstSLz1kzzAqem/uHdG9FyXdbTAwH1G4ZPv69sQAFAOCgAqYmdnzedsQtE\n1LQfaQrx0twO+CZJPcRLEESjq8ScQxWRRkfuh2VeR7cEU7L7KqT10mtUwrvw7APf\nDYoeCY9KyjIBjQXfbj2ke5u1hZj94Fsq9FfbEQg8ygCgwThnmkTrrKEiMSs3alYR\nORVCZpRuCPpmC8qmqxUnARDArzucjaclkxjLWvCVHeFa9UP7K3Nl9oTjJNv+7/jM\nWZs4eecIcUc4tKdHxcAJ0MO/Dkqq7hGaiHpwKY76wQ1+8xAh\n-----END CERTIFICATE-----\n".freeze]
  s.date = "2020-10-30"
  s.description = "    The sys-uname library provides an interface for gathering information\n    about your current platform. The library is named after the Unix 'uname'\n    command but also works on MS Windows. Available information includes\n    OS name, OS version, system name and so on. Additional information is\n    available for certain platforms.\n".freeze
  s.email = "djberg96@gmail.com".freeze
  s.extra_rdoc_files = ["doc/uname.rdoc".freeze]
  s.files = ["doc/uname.rdoc".freeze]
  s.homepage = "http://github.com/djberg96/sys-uname".freeze
  s.licenses = ["Apache-2.0".freeze]
  s.rubygems_version = "3.2.32".freeze
  s.summary = "An interface for returning uname (platform) information".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<ffi>.freeze, ["~> 1.1"])
    s.add_development_dependency(%q<rspec>.freeze, ["~> 3.9"])
    s.add_development_dependency(%q<rake>.freeze, [">= 0"])
  else
    s.add_dependency(%q<ffi>.freeze, ["~> 1.1"])
    s.add_dependency(%q<rspec>.freeze, ["~> 3.9"])
    s.add_dependency(%q<rake>.freeze, [">= 0"])
  end
end
