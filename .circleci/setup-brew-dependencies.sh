#!/bin/bash

function version {
    echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

if [ $(version $(swiftformat --version)) -lt $(version $(cat ../.swiftformat-version)) ]; then
    brew upgrade swiftformat
fi