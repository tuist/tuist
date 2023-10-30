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
tuist/cache-warm:
	./make/tasks/tuist/cache-warm.sh $(ARGS)
tuist/run:
	./make/tasks/tuist/run.sh $(ARGS)

# Shared
workspace/build/tuistbenchmark:
	./make/tasks/workspace/build/tuistbenchmark.sh $(ARGS)
workspace/build/tuistfixturegenerator:
	./make/tasks/workspace/build/tuistfixturegenerator.sh $(ARGS)
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
	./make/tasks/workspace/build-with-spm.sh $(ARGS)
workspace/release/bundle:
	./make/tasks/workspace/release/bundle.sh

