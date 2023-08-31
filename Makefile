docs/tuist/preview:
	swift package --disable-sandbox preview-documentation --target tuist
docs/tuist/build:
	swift package --allow-writing-to-directory .build/documentation generate-documentation --target tuist --disable-indexing --output-path .build/documentation --hosting-base-path /