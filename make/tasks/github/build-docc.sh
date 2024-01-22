#!/bin/bash

set -euo pipefail

echo "⏳ Generating documentation for the latest release.";
cd tuist
mkdir .build
mise run docs:build
cd ..
cp tuist/assets/favicon.ico .build/documentation/favicon.ico
cp tuist/assets/favicon.svg .build/documentation/favicon.svg

for tag in $(git tag | tail -n +20);
do
echo "⏳ Generating documentation for "$tag" release.";

if [ -d "docs-out/$tag" ] 
then 
    echo "✅ Documentation for "$tag" already exists.";
else 
    git checkout -f "$tag";
    
    swift package \
    --disable-sandbox \
    --package-path tuist/docs \
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