#!/usr/bin/env bash
# Plans (pull requests) or applies (main) infra/cache-dns/zone.yaml through a
# CloudFormation change set. Planning never executes: the plan role cannot.
set -euo pipefail

mode="${1:?usage: cache-dns-change-set.sh plan|deploy}"
: "${STACK_NAME:?}" "${TEMPLATE:?}" "${EXECUTION_ROLE_ARN:?}" "${GITHUB_RUN_ID:?}"
summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
change_set="${mode}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT:-1}"

cleanup() {
  if [ "$mode" = plan ]; then
    aws cloudformation delete-change-set --stack-name "$STACK_NAME" --change-set-name "$change_set" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

aws cloudformation create-change-set \
  --stack-name "$STACK_NAME" \
  --change-set-name "$change_set" \
  --template-body "file://$TEMPLATE" \
  --capabilities CAPABILITY_IAM \
  --role-arn "$EXECUTION_ROLE_ARN" \
  --description "${GITHUB_REPOSITORY:-}@${GITHUB_SHA:-}" >/dev/null

if ! aws cloudformation wait change-set-create-complete --stack-name "$STACK_NAME" --change-set-name "$change_set" 2>/dev/null; then
  reason="$(aws cloudformation describe-change-set --stack-name "$STACK_NAME" --change-set-name "$change_set" --query StatusReason --output text)"
  case "$reason" in
    *"didn't contain changes"* | *"No updates are to be performed"*)
      echo "### Cache DNS: no changes to \`$STACK_NAME\`" >>"$summary"
      [ "$mode" = deploy ] && aws cloudformation delete-change-set --stack-name "$STACK_NAME" --change-set-name "$change_set" >/dev/null
      exit 0
      ;;
    *)
      echo "Change set creation failed: $reason" >&2
      exit 1
      ;;
  esac
fi

changes="$(aws cloudformation describe-change-set --stack-name "$STACK_NAME" --change-set-name "$change_set" --query 'Changes[].ResourceChange' --output json)"

{
  echo "### Cache DNS ${mode}: \`$STACK_NAME\`"
  echo
  echo "| Action | Resource | Type | Replacement | Changed |"
  echo "| --- | --- | --- | --- | --- |"
  jq -r '.[] | "| \(.Action) | `\(.LogicalResourceId)` | \(.ResourceType) | \(.Replacement // "-") | \((.Scope // []) | join(", ")) |"' <<<"$changes"
} >>"$summary"

# The zone carries every account's cache records and its delegation's name
# servers. Replacing it would change those name servers; removing it from the
# stack would orphan it. Either needs an operator, not a merge.
unsafe="$(jq -r '[.[] | select(.ResourceType == "AWS::Route53::HostedZone" and (.Action == "Remove" or .Replacement == "True" or .Replacement == "Conditional")) | .LogicalResourceId] | join(", ")' <<<"$changes")"
if [ -n "$unsafe" ]; then
  echo "Refusing: the change set would replace or remove the hosted zone ($unsafe)." | tee -a "$summary" >&2
  exit 1
fi

if [ "$mode" = deploy ]; then
  aws cloudformation execute-change-set --stack-name "$STACK_NAME" --change-set-name "$change_set"
  if ! aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME"; then
    aws cloudformation describe-stack-events --stack-name "$STACK_NAME" --max-items 20 \
      --query 'StackEvents[].[Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason]' --output table >&2
    exit 1
  fi
  echo >>"$summary"
  echo "Applied." >>"$summary"
fi
