# Documentation
docs/preview:
	./make/tasks/docs/preview.sh
docs/build:
	./make/tasks/docs/build.sh

# Tuist
tuist/edit:
	./make/tasks/tuist/edit.sh
tuist/generate:
	./make/tasks/tuist/generate.sh $(ARGS)
tuist/build:
	./make/tasks/tuist/build.sh $(ARGS)
tuist/test:
	./make/tasks/tuist/test.sh $(ARGS)
tuist/run:
	./make/tasks/tuist/run.sh $(ARGS)
tuist/acceptance-test:
	./make/tasks/tuist/acceptance-test.sh
	
# Shared
workspace/lint:
	./make/tasks/workspace/lint.sh $(ARGS)
workspace/lint-fix:
	./make/tasks/workspace/lint-fix.sh $(ARGS)
