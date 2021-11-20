#!/bin/bash
# mise description="Generates the version for release"

# Get current date components
year=$(date +%Y)
month=$(date +%m)
day=$(date +%d)

# Define major version
MAJOR="1"

# Create version string
version="${MAJOR}.$((year % 100)).${month}.${day}"

# Print version
echo $version
