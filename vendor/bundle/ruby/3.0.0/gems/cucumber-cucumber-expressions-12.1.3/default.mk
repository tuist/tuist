SHELL := /usr/bin/env bash
RUBY_SOURCE_FILES = $(shell find . -name "*.rb")
GEMSPEC = $(shell find . -name "*.gemspec")
LIBNAME := $(shell basename $$(dirname $$(pwd)))
GEM := cucumber-$(LIBNAME)-$(NEW_VERSION).gem
IS_TESTDATA = $(findstring -testdata,${CURDIR})

# https://stackoverflow.com/questions/2483182/recursive-wildcards-in-gnu-make
rwildcard=$(foreach d,$(wildcard $(1:=/*)),$(call rwildcard,$d,$2) $(filter $(subst *,%,$2),$d))

default: .tested
.PHONY: default

.deps: Gemfile.lock
	touch $@

Gemfile.lock: Gemfile $(GEMSPEC)
	bundle install
	touch $@

.tested: .deps $(RUBY_SOURCE_FILES)
	bundle exec rspec --color
	touch $@

update-dependencies:
	./scripts/update-gemspec
.PHONY: update-dependencies

ifdef NEW_VERSION
ifneq (,$(GEMSPEC))
gem: $(GEM)
else
gem:
	@echo "Not building gem because there is no gemspec"
endif
endif
.PHONY: gem

$(GEM): .tested
	gem build $(GEMSPEC)
	test -s "$(GEM)" || { echo "Gem not built: $(GEM)"; exit 1; }

remove-local-dependencies:
	cat Gemfile | sed 's/^gem /#gem /' > Gemfile.tmp
	mv Gemfile.tmp Gemfile
.PHONY: remove-local-dependencies

pre-release: remove-local-dependencies update-version update-dependencies gem
.PHONY: pre-release

update-version:
ifeq ($(IS_TESTDATA),-testdata)
	# no-op
else
ifdef NEW_VERSION
	@echo "$(NEW_VERSION)" > VERSION
endif
endif
.PHONY: update-version

publish: gem
ifeq ($(IS_TESTDATA),-testdata)
	# no-op
else
ifneq (,$(GEMSPEC))
	gem push $(GEM)
else
	@echo "Not publishing because there is no gemspec"
endif
endif
.PHONY: publish

post-release:
	cat Gemfile | sed 's/^#gem /gem /' > Gemfile.tmp
	mv Gemfile.tmp Gemfile
.PHONY: post-release

clean: clean-ruby
.PHONY: clean

clean-ruby:
	rm -rf .deps .linked .tested* Gemfile.lock *.gem acceptance
.PHONY: clean-ruby

### COMMON stuff for all platforms

BERP_VERSION = 1.3.0
BERP_GRAMMAR = gherkin.berp

define berp-generate-parser =
-! dotnet tool list --tool-path /usr/bin | grep "berp\s*$(BERP_VERSION)" && dotnet tool update Berp --version $(BERP_VERSION) --tool-path /usr/bin
berp -g $(BERP_GRAMMAR) -t $< -o $@ --noBOM
endef
