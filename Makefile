docs/tuist/preview:
	swift package --disable-sandbox preview-documentation --target tuist --hosting-base-path /
docs/tuist/build:
	swift package --allow-writing-to-directory .build/documentation generate-documentation --target tuist --disable-indexing --output-path .build/documentation --transform-for-static-hosting --hosting-base-path /