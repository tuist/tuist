#!/bin/bash
echo "Running SwiftFormat..."
bin/swiftformat . --quiet
if [ $? -ne 0 ] 
then
    echo "Swiftformat detected issues, please add changes and commit again"
    exit 1
else
    echo "Running Swiftlint...";
    bin/swiftlint lint --quiet
    if [ $? -ne 0 ]
    then
        bin/swiftlint autocorrect --quiet
        echo "Swiftlint detected issues, please add changes and commit again"
    else
        echo "Code is formatted and linted correctly. Proceeding with commit..."
        exit 0
    fi
fi
