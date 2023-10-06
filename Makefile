# Documentation
docs/tuist/preview:
	./make/tasks/docs/tuist/preview.sh
docs/tuist/build:
	./make/tasks/docs/tuist/build.sh

# Tuist
tuist/edit:
	./make/tasks/tuist/edit.sh
tuist/fetch:
	./make/tasks/fetch.sh $(ARGS)
tuist/generate:
	./make/tasks/generate.sh $(ARGS)
tuist/generate/with-cloud:
	TUIST_INCLUDE_TUIST_CLOUD=1 ./make/tasks/generate.sh $(ARGS)
tuist/run:
	./make/tasks/run.sh $(ARGS)

# Shared
shared/lint-fix:
	./make/tasks/shared/lint-fix.sh
shared/lint:
	./make/tasks/shared/lint.sh
shared/lint/lockfiles:
	./make/tasks/shared/lint/lockfiles.sh
shared/generate/cloud-openapi-code:
	./make/tasks/shared/generate/cloud-openapi-code.sh

