docs/tuist/preview:
	./make/tasks/docs/tuist/preview.sh
docs/tuist/build:
	./make/tasks/docs/tuist/build.sh
edit:
	./make/tasks/edit.sh
generate:
	./make/tasks/generate.sh $(ARGS)
run:
	./make/tasks/run.sh $(ARGS)
generate/cloud-openapi-code:
	./make/tasks/generate/cloud-openapi-code.sh
lint-fix:
	./make/tasks/lint-fix.sh
lint:
	./make/tasks/lint.sh
lint/lockfiles:
	./make/tasks/lint/lockfiles.sh
tuist/fetch:
	./make/tasks/tuist/fetch.sh
tuist/cloud/cache/warm:
	./make/tasks/tuist/cloud/cache/warm.sh $(ARGS)