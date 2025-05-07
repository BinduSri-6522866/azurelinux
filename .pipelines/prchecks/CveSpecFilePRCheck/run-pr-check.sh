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

# 1) Source the config script to login and export OPENAI_* variables
echo "⚙️  Applying OpenAI config…"
# Use path relative to current directory instead of 'scripts/'
source ./apply-security-config.sh --openaiModel=o3-mini

# Map environment variables to the camelCase format expected by the Python script
echo "🔄 Mapping environment variables to expected format..."
export openAiApiVersion="$OPENAI_API_VERSION"
export openAiApiBase="$OPENAI_API_BASE"
export openAiDeploymentName="$OPENAI_DEPLOYMENT_NAME"
export openAiModelName="$OPENAI_MODEL_NAME"

# Verify the environment variables are set
echo "✅ Verifying environment variables:"
echo "  - openAiApiVersion: ${openAiApiVersion:-NOT SET}"
echo "  - openAiApiBase: ${openAiApiBase:-NOT SET}"
echo "  - openAiDeploymentName: ${openAiDeploymentName:-NOT SET}"
echo "  - openAiModelName: ${openAiModelName:-NOT SET}"

# 2) Install Python dependencies into your active environment
echo "📦 Installing Python dependencies…"
pip install --upgrade pip
pip install -r requirements.txt

# 3) Run the PR-check Python script
echo "🔍 Running run_pr_checks.py…"
python OpenAIHelloWorldClass.py
