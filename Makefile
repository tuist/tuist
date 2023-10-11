# Documentation
docs/tuist/preview:
	./make/tasks/docs/tuist/preview.sh
docs/tuist/build:
	./make/tasks/docs/tuist/build.sh

# Tuist
tuist/edit:
	./make/tasks/tuist/edit.sh
tuist/fetch:
	./make/tasks/tuist/fetch.sh $(ARGS)
tuist/generate:
	./make/tasks/tuist/generate.sh $(ARGS)
tuist/generate/with-cloud:
	TUIST_INCLUDE_TUIST_CLOUD=1 ./make/tasks/tuist/generate.sh $(ARGS)
tuist/run:
	./make/tasks/tuist/run.sh $(ARGS)

# Shared
workspace/lint-fix:
	./make/tasks/workspace/lint-fix.sh
workspace/lint:
	./make/tasks/workspace/lint.sh
workspace/lint/lockfiles:
	./make/tasks/workspace/lint/lockfiles.sh
workspace/generate/cloud-openapi-code:
	./make/tasks/workspace/generate/cloud-openapi-code.sh
workspace/up:
	./make/tasks/workspace/up.sh
workspace/clean:
	./make/tasks/workspace/clean.sh
workspace/build-with-spm:
	$(ARGS) ./make/tasks/workspace/build-with-spm.sh
workspace/release:
	./make/tasks/workspace/release/bundle.sh
workspace/release/bundle:
	./make/tasks/workspace/release/bundle.sh

