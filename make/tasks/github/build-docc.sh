#!/bin/bash

set -euo pipefail

echo "⏳ Generating documentation for the latest release.";
mise run docs:build

for tag in $(git tag -C tuist-archive -l --sort=v:refname | tail -n 30);
do
echo "⏳ Generating documentation for "$tag" release.";

if [ -d ".build/documentation/$tag" ] 
then
    echo "✅ Documentation for "$tag" already exists.";
else
    git checkout -C tuist-archive -f "$tag";

    rm docs/Sources/tuist/ProjectDescription
    ln -s ../tuist-archive/Sources/tuist/ProjectDescription docs/Sources/tuist/ProjectDescription
    
    swift package \
    --disable-sandbox \
    --package-path docs \
    --allow-writing-to-directory .build/documentation/"$tag" \
    generate-documentation \
    --target tuist \
    --output-path .build/documentation/"$tag" \
    --transform-for-static-hosting \
    --hosting-base-path /tuist/"$tag" \
        && echo "✅ Documentation generated for "$tag" release." \
        || echo "⚠️ Documentation skipped for "$tag".";
fi;
done