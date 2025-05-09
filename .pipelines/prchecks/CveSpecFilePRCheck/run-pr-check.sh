# scripts/run-pr-check.sh
#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# run-pr-check.sh
#   Entry point for PR checks:
#   1) Sources apply-security-config.sh to login and export vars
#   2) Installs Python dependencies
#   3) Runs the Python PR-checker
# -----------------------------------------------------------------------------

# Define exit code meanings
EXIT_SUCCESS=0
EXIT_CRITICAL=1
EXIT_ERROR=2
EXIT_WARNING=3
EXIT_FATAL=10

# Flag to control whether warnings should fail the pipeline
FAIL_ON_WARNINGS=${FAIL_ON_WARNINGS:-false}

# Flag to control whether to use different exit codes for different severities
USE_EXIT_CODE_SEVERITY=${USE_EXIT_CODE_SEVERITY:-false}

# GitHub integration options
POST_GITHUB_COMMENTS=${POST_GITHUB_COMMENTS:-false}
USE_GITHUB_CHECKS=${USE_GITHUB_CHECKS:-false}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --fail-on-warnings)
      FAIL_ON_WARNINGS=true
      shift
      ;;
    --exit-code-severity)
      USE_EXIT_CODE_SEVERITY=true
      shift
      ;;
    --post-github-comments)
      POST_GITHUB_COMMENTS=true
      shift
      ;;
    --use-github-checks)
      USE_GITHUB_CHECKS=true
      shift
      ;;
    *)
      echo "⚠️ Unknown parameter: $1"
      shift
      ;;
  esac
done

# 1) Source the config script to login and export OPENAI_* variables
echo "⚙️  Applying OpenAI config…"
# Use path relative to current directory instead of 'scripts/'
source ./apply-security-config.sh --openaiModel=o3-mini

# Map environment variables for Azure OpenAI client
echo "🔄 Mapping environment variables to expected format..."
export AZURE_OPENAI_ENDPOINT="$OPENAI_API_BASE"
export AZURE_OPENAI_DEPLOYMENT_NAME="$OPENAI_DEPLOYMENT_NAME"
export AZURE_OPENAI_MODEL_NAME="$OPENAI_MODEL_NAME"
export AZURE_OPENAI_API_VERSION="$OPENAI_API_VERSION"

# Set BUILD_SOURCESDIRECTORY if not already set
if [ -z "${BUILD_SOURCESDIRECTORY:-}" ]; then
  export BUILD_SOURCESDIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
  echo "📂 Setting BUILD_SOURCESDIRECTORY to $BUILD_SOURCESDIRECTORY"
fi

# Verify the environment variables are set
echo "✅ Verifying environment variables:"
echo "  - AZURE_OPENAI_ENDPOINT: ${AZURE_OPENAI_ENDPOINT:-NOT SET}"
echo "  - AZURE_OPENAI_DEPLOYMENT_NAME: ${AZURE_OPENAI_DEPLOYMENT_NAME:-NOT SET}"
echo "  - AZURE_OPENAI_MODEL_NAME: ${AZURE_OPENAI_MODEL_NAME:-NOT SET}"
echo "  - AZURE_OPENAI_API_VERSION: ${AZURE_OPENAI_API_VERSION:-NOT SET}"
echo "  - BUILD_SOURCESDIRECTORY: ${BUILD_SOURCESDIRECTORY:-NOT SET}"
echo "  - FAIL_ON_WARNINGS: ${FAIL_ON_WARNINGS}"
echo "  - USE_EXIT_CODE_SEVERITY: ${USE_EXIT_CODE_SEVERITY}"
echo "  - POST_GITHUB_COMMENTS: ${POST_GITHUB_COMMENTS}"
echo "  - USE_GITHUB_CHECKS: ${USE_GITHUB_CHECKS}"

# For local testing - if PR commit IDs are not set, use HEAD and HEAD~1
if [ -z "${SYSTEM_PULLREQUEST_SOURCECOMMITID:-}" ] || [ -z "${SYSTEM_PULLREQUEST_TARGETCOMMITID:-}" ]; then
  echo "⚠️ PR commit IDs not found, trying to determine from git..."
  export SYSTEM_PULLREQUEST_SOURCECOMMITID=$(git rev-parse HEAD)
  
  # Try to find the target branch more robustly
  if [ -n "${SYSTEM_PULLREQUEST_TARGETBRANCH:-}" ]; then
    # Try to fetch the target branch if it exists - quote branch name to handle slashes properly
    echo "🔄 Trying to fetch target branch: ${SYSTEM_PULLREQUEST_TARGETBRANCH}"
    git fetch --depth=1 origin "${SYSTEM_PULLREQUEST_TARGETBRANCH}" || true
    
    # Double-quote branch names to handle branches with slashes
    if git rev-parse "origin/${SYSTEM_PULLREQUEST_TARGETBRANCH}" >/dev/null 2>&1; then
      export SYSTEM_PULLREQUEST_TARGETCOMMITID=$(git rev-parse "origin/${SYSTEM_PULLREQUEST_TARGETBRANCH}")
      echo "✅ Found target commit from branch: ${SYSTEM_PULLREQUEST_TARGETBRANCH}"
    else
      # If we can't find the branch, use HEAD~1 as fallback
      export SYSTEM_PULLREQUEST_TARGETCOMMITID=$(git rev-parse HEAD~1)
      echo "⚠️ Could not find target branch, using previous commit as fallback"
    fi
  else
    # No target branch info, use HEAD~1
    export SYSTEM_PULLREQUEST_TARGETCOMMITID=$(git rev-parse HEAD~1)
    echo "⚠️ No target branch specified, using previous commit as fallback"
  fi
fi

# Enhanced GitHub integration settings
echo "🔍 Setting up GitHub API access..."

# For GitHub integration - This is a critical part that needs to be fixed!
if [ -z "${GITHUB_REPOSITORY:-}" ] || [ -z "${GITHUB_PR_NUMBER:-}" ]; then
  # Extract from ADO variables if possible
  if [ -n "${SYSTEM_PULLREQUEST_SOURCEREPOSITORYURI:-}" ]; then
    # Extract repo from URI (e.g. https://github.com/owner/repo.git -> owner/repo)
    export GITHUB_REPOSITORY=$(echo $SYSTEM_PULLREQUEST_SOURCEREPOSITORYURI | sed -E 's/.*github.com\/([^.]+)(\.git)?/\1/')
    echo "📂 Setting GITHUB_REPOSITORY to $GITHUB_REPOSITORY"
  else
    # For local testing or missing URI, set to repo where code actually lives
    export GITHUB_REPOSITORY="microsoft/azurelinux"
    echo "📂 Setting default GITHUB_REPOSITORY to $GITHUB_REPOSITORY"
  fi
  
  if [ -n "${SYSTEM_PULLREQUEST_PULLREQUESTID:-}" ]; then
    export GITHUB_PR_NUMBER=$SYSTEM_PULLREQUEST_PULLREQUESTID
    echo "📊 Setting GITHUB_PR_NUMBER to $GITHUB_PR_NUMBER"
  else
    # For local testing - this won't work but at least code won't crash
    export GITHUB_PR_NUMBER="1"
    echo "📊 Setting placeholder GITHUB_PR_NUMBER to $GITHUB_PR_NUMBER (for testing)"
  fi
fi

# CRITICAL FIX: Manually setting GitHub access token if not already set
# This allows using the GITHUB_TOKEN or AZDO_GITHUB_TOKEN which are common environment variables
if [ -z "${GITHUB_ACCESS_TOKEN:-}" ]; then
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    export GITHUB_ACCESS_TOKEN="$GITHUB_TOKEN"
    echo "🔑 Using GITHUB_TOKEN as GITHUB_ACCESS_TOKEN"
  elif [ -n "${AZDO_GITHUB_TOKEN:-}" ]; then
    export GITHUB_ACCESS_TOKEN="$AZDO_GITHUB_TOKEN"
    echo "🔑 Using AZDO_GITHUB_TOKEN as GITHUB_ACCESS_TOKEN"
  elif [ -n "${SYSTEM_ACCESSTOKEN:-}" ]; then
    # In Azure DevOps, we can use the system access token if available and configured with GitHub access
    export GITHUB_ACCESS_TOKEN="$SYSTEM_ACCESSTOKEN"
    echo "🔑 Using SYSTEM_ACCESSTOKEN as GITHUB_ACCESS_TOKEN"
  fi
fi

# Check if GitHub PAT is available - needed for posting comments
if [ "$POST_GITHUB_COMMENTS" = "true" ] || [ "$USE_GITHUB_CHECKS" = "true" ]; then
  echo "🔍 GitHub Integration Details:"
  echo "  - Repository: ${GITHUB_REPOSITORY:-NOT SET}"
  echo "  - PR Number: ${GITHUB_PR_NUMBER:-NOT SET}"
  
  # Mask token output but show if it's set
  if [ -n "${GITHUB_ACCESS_TOKEN:-}" ]; then
    echo "  - GitHub Token: SET"
    # Test the token using a simple API call
    echo "  - Testing GitHub API access..."
    # Make a request to verify the token works (only showing HTTP status, not content)
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token ${GITHUB_ACCESS_TOKEN}" https://api.github.com/repos/${GITHUB_REPOSITORY} 2>/dev/null || echo "failed")
    if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "304" ]; then
      echo "  ✅ GitHub API access successful (HTTP status: $HTTP_STATUS)"
      echo "  ✅ GitHub comments will be posted"
    else
      echo "  ❌ GitHub API access failed (HTTP status: $HTTP_STATUS)"
      echo "⚠️ GitHub token validation failed, GitHub integration will be disabled"
      POST_GITHUB_COMMENTS=false
      USE_GITHUB_CHECKS=false
    fi
  else
    echo "  - GitHub Token: NOT SET"
    echo "⚠️ GITHUB_ACCESS_TOKEN not set, GitHub integration will be disabled"
    POST_GITHUB_COMMENTS=false
    USE_GITHUB_CHECKS=false
  fi
fi

echo "🔍 Using commits for diff:"
echo "  - Source: ${SYSTEM_PULLREQUEST_SOURCECOMMITID}"
echo "  - Target: ${SYSTEM_PULLREQUEST_TARGETCOMMITID}"

# 2) Install Python dependencies into your active environment
echo "📦 Installing Python dependencies…"
pip install --upgrade pip

# Install all dependencies from requirements.txt (including azure-identity and azure-ai-openai)
echo "📦 Installing dependencies from requirements.txt..."
pip install -r requirements.txt

# 3) Run the CVE spec file checker
echo "🔍 Running CveSpecFilePRCheck.py…"

# Build command with arguments
CMD="python CveSpecFilePRCheck.py"
if [[ "$FAIL_ON_WARNINGS" =~ ^[Tt][Rr][Uu][Ee]$ ]]; then
  CMD="$CMD --fail-on-warnings"
fi
if [[ "$USE_EXIT_CODE_SEVERITY" =~ ^[Tt][Rr][Uu][Ee]$ ]]; then
  CMD="$CMD --exit-code-severity" 
fi
if [[ "$POST_GITHUB_COMMENTS" =~ ^[Tt][Rr][Uu][Ee]$ ]]; then
  echo "📝 GitHub comments enabled, adding flag..."
  CMD="$CMD --post-github-comments"
fi
if [[ "$USE_GITHUB_CHECKS" =~ ^[Tt][Rr][Uu][Ee]$ ]]; then
  CMD="$CMD --use-github-checks"
fi

# Run the command and capture exit code
echo "🚀 Running command: $CMD"
eval $CMD
PR_CHECK_EXIT_CODE=$?

# Process the exit code appropriately 
if [ $PR_CHECK_EXIT_CODE -eq $EXIT_SUCCESS ]; then
  echo "✅ PR check completed successfully"
  echo "=================================================="
  echo "No critical issues found in spec files"
  echo "=================================================="
elif [ $PR_CHECK_EXIT_CODE -eq $EXIT_WARNING ]; then
  if [ "$FAIL_ON_WARNINGS" = "true" ]; then
    echo "❌ PR check failed with warnings (exit code $PR_CHECK_EXIT_CODE)"
    echo "=================================================="
    echo "⚠️  WARNINGS DETECTED - PLEASE REVIEW THE ISSUES"
    echo "=================================================="
    # Only propagate failure if FAIL_ON_WARNINGS is true
    exit $EXIT_CRITICAL
  else
    echo "⚠️ PR check completed with warnings (exit code $PR_CHECK_EXIT_CODE)"
    echo "=================================================="
    echo "⚠️  WARNINGS DETECTED BUT PIPELINE CONTINUES"
    echo "=================================================="
    # Don't fail the pipeline for warnings by default
    exit $EXIT_SUCCESS
  fi
elif [ $PR_CHECK_EXIT_CODE -eq $EXIT_ERROR ]; then
  echo "❌ PR check failed with errors (exit code $PR_CHECK_EXIT_CODE)"
  echo "=================================================="
  echo "❌  ERRORS DETECTED - PLEASE FIX THE ISSUES"
  echo "=================================================="
  # Propagate the exit code to fail the pipeline
  exit $EXIT_CRITICAL
elif [ $PR_CHECK_EXIT_CODE -eq $EXIT_CRITICAL ]; then
  echo "❌ PR check failed with critical issues (exit code $PR_CHECK_EXIT_CODE)"
  echo "=================================================="
  echo "🚨  CRITICAL ISSUES DETECTED - PLEASE FIX IMMEDIATELY"
  echo "=================================================="
  # Propagate the exit code to fail the pipeline
  exit $EXIT_CRITICAL
else
  echo "❌ PR check encountered an unexpected error (exit code $PR_CHECK_EXIT_CODE)"
  echo "=================================================="
  echo "⚠️  UNEXPECTED ERROR - CHECK THE LOGS"
  echo "=================================================="
  # Propagate the exit code to fail the pipeline
  exit $PR_CHECK_EXIT_CODE
fi
