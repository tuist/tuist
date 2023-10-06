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
	
# Cloud
cloud/up:
	./make/tasks/cloud/up.sh
cloud/down:
	./make/tasks/cloud/down.sh
# Shared
shared/lint-fix:
	./make/tasks/shared/lint-fix.sh
shared/lint:
	./make/tasks/shared/lint.sh
shared/lint/lockfiles:
	./make/tasks/shared/lint/lockfiles.sh
shared/generate/cloud-openapi-code:
	./make/tasks/shared/generate/cloud-openapi-code.sh

