docs/tuist/preview:
	./make/tasks/docs/tuist/preview.sh
docs/tuist/build:
	./make/tasks/docs/tuist/build.sh
edit:
	./make/tasks/edit.sh
generate:
	./make/tasks/generate.sh $(ARGS)
run:
	./make/tasks/run.sh
generate/cloud-openapi-code:
	./make/tasks/generate/cloud-openapi-code.sh	