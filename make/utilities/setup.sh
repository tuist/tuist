#!/bin/bash

format_section() {
    echo -e "\033[1;36m=== ${1} ===\033[0m"
}

format_subsection() {
    echo -e "\033[1;32m${1}\033[0m"
}

format_success() {
    echo -e "\033[1;32m${1}\033[0m"
}

format_error() {
    echo -e "\033[1;31m${1}\033[0m"
}