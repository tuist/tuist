docs/tuist/preview:
	./make/tasks/docs/tuist/preview.sh
docs/tuist/build:
	./make/tasks/docs/tuist/build.sh
edit:
	./make/tasks/edit.sh
fetch:
	./make/tasks/fetch.sh $(ARGS)
generate:
	./make/tasks/generate.sh $(ARGS)
generate/with-cloud:
	TUIST_INCLUDE_TUIST_CLOUD=1 ./make/tasks/generate.sh $(ARGS)
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
pull/cloud:
	git submodule update --init submodules/TuistCloud