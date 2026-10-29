#!/bin/sh
set -eu
mkdir /tmp/resume-ci
cd /tmp/resume-ci
git init -q
git remote add origin https://github.com/tuist/XcodeProj.git
git fetch -q --depth 1 origin 5d313c99fbb3871a6faeeca97ed13ee6f832ad06
git checkout -q --detach FETCH_HEAD
swift package resolve
