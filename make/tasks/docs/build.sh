#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../utilities/root_dir.sh)

if [ ! -d $ROOT_DIR/.build/documentation ]; then
  mkdir -p $ROOT_DIR/.build/documentation
fi

swift package --package-path $ROOT_DIR/docs --allow-writing-to-directory .build/documentation generate-documentation --target tuist --disable-indexing --output-path .build/documentation --transform-for-static-hosting

# Copy favicon
cp $ROOT_DIR/assets/favicon.ico .build/documentation/favicon.ico
cp $ROOT_DIR/assets/favicon.svg .build/documentation/favicon.svg

# Add Posthog snippet
INDEX_HTML=$ROOT_DIR/.build/documentation/index.html
POSTHOG_SCRIPT='<script>!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.async=!0,p.src=s.api_host+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+".people (stub)"},o="capture identify alias people.set people.set_once set_config register register_once unregister opt_out_capturing has_opted_out_capturing opt_in_capturing reset isFeatureEnabled onFeatureFlags getFeatureFlag getFeatureFlagPayload reloadFeatureFlags group updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures getActiveMatchingSurveys getSurveys onSessionId".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);posthog.init("phc_grD1cAayH9j8KSMb5DjhVI9B91GtXYXhBArKRv8HbYk",{api_host:"https://eu.posthog.com"})</script>'
sed -i.bak "s#</head>#$POSTHOG_SCRIPT</head>#" $INDEX_HTML
