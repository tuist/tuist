OWNER := tuist
REPO := tuist
TOKEN := $(or $(GITHUB_TOKEN),$(shell echo "url=https://github.com" | git credential fill | grep password | cut -d '=' -f 2))

docs/tuist/preview:
	./make/tasks/docs/tuist/preview.sh
docs/tuist/build:
	./make/tasks/docs/tuist/build.sh
edit:
	swift build
	.build/debug/tuist edit --only-current-directory
generate:
	swift build
	.build/debug/tuist fetch
	.build/debug/tuist cache warm --dependencies-only --xcframeworks
	.build/debug/tuist generate --xcframeworks $(ARGS)
run:
	swift build
	.build/debug/tuist $(ARGS)
generate/cloud-openapi-code:
	swift run swift-openapi-generator generate --mode types --mode client --output-directory Sources/TuistCloud/OpenAPI Sources/TuistCloud/OpenAPI/cloud.yml
github/cancel-workflows:
	@echo "Fetching queued workflow runs..."
	@workflow_ids=$$(curl -s -H "Authorization: token $(TOKEN)" \
      -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/$(OWNER)/$(REPO)/actions/runs \
      | jq '.workflow_runs[] | select(.status == "queued") | .id'); \
    for id in $$workflow_ids; do \
        echo "Canceling workflow run with ID $$id"; \
        curl -s -X POST -H "Authorization: token $(TOKEN)" \
          -H "Accept: application/vnd.github.v3+json" \
          https://api.github.com/repos/$(OWNER)/$(REPO)/actions/runs/$$id/cancel; \
    done