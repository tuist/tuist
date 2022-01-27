# REXML

REXML was inspired by the Electric XML library for Java, which features an easy-to-use API, small size, and speed. Hopefully, REXML, designed with the same philosophy, has these same features. I've tried to keep the API as intuitive as possible, and have followed the Ruby methodology for method naming and code flow, rather than mirroring the Java API.

REXML supports both tree and stream document parsing. Stream parsing is faster (about 1.5 times as fast). However, with stream parsing, you don't get access to features such as XPath.

## API

See the {API documentation}[https://ruby.github.io/rexml/]

## Usage

We'll start with parsing an XML document

```ruby
require "rexml/document"
file = File.new( "mydoc.xml" )
doc = REXML::Document.new file
```

Line 3 creates a new document and parses the supplied file. You can also do the following

```ruby
require "rexml/document"
include REXML  # so that we don't have to prefix everything with REXML::...
string = <<EOF
  <mydoc>
    <someelement attribute="nanoo">Text, text, text</someelement>
  </mydoc>
EOF
doc = Document.new string
```

So parsing a string is just as easy as parsing a file.

## Development

After checking out the repo, run `rake test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby/rexml.

## License

The gem is available as open source under the terms of the [BSD-2-Clause](LICENSE.txt).
