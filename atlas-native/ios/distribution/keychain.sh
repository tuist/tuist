#!/usr/bin/env bash

# codesign still uses the user search list when resolving an identity's chain.
signing_keychain_search_list=()
signing_keychain_search_list_saved=false
signing_keychain_created=false

create_signing_keychain() {
    local keychain=$1 password=$2 entry search_list
    search_list=$(security list-keychains -d user) || return
    while IFS= read -r entry; do
        if [[ $entry =~ \"(.*)\" ]]; then
            signing_keychain_search_list+=("${BASH_REMATCH[1]}")
        elif [[ -n $entry ]]; then
            echo "Unexpected keychain search-list entry: $entry" >&2
            return 1
        fi
    done <<< "$search_list"
    signing_keychain_search_list_saved=true

    security create-keychain -p "$password" "$keychain" || return
    signing_keychain_created=true
    security set-keychain-settings -lut 3600 "$keychain" || return
    security unlock-keychain -p "$password" "$keychain" || return
    security list-keychains -d user -s "$keychain" ${signing_keychain_search_list[@]+"${signing_keychain_search_list[@]}"}
}

delete_signing_keychain() {
    local keychain=$1
    if [[ $signing_keychain_search_list_saved = true ]]; then
        security list-keychains -d user -s ${signing_keychain_search_list[@]+"${signing_keychain_search_list[@]}"} || return
    fi
    if [[ $signing_keychain_created = true ]]; then
        security delete-keychain "$keychain"
    fi
}
