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

# Shared
workspace/lint:
	./make/tasks/workspace/lint.sh $(ARGS)
workspace/lint-fix:
	./make/tasks/workspace/lint-fix.sh $(ARGS)
workspace/up:
	./make/tasks/workspace/up.sh