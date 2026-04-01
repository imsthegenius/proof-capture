#!/bin/bash
# Pre-commit security scan — blocks secrets, hardcoded paths, and .env files
# Inspired by software-forge's pre-commit-scan.sh

# Only run on git commit commands
if ! echo "$TOOL_INPUT" | grep -q "git commit"; then
  exit 0
fi

ISSUES=""

# Check staged files for secrets
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)

if [ -z "$STAGED_FILES" ]; then
  exit 0
fi

for file in $STAGED_FILES; do
  # Skip binary files
  if file "$file" 2>/dev/null | grep -q "binary"; then
    continue
  fi

  # Skip xcuserstate and other binary-like files
  case "$file" in
    *.xcuserstate|*.pbxproj) continue ;;
  esac

  if [ ! -f "$file" ]; then
    continue
  fi

  # Check for API keys and tokens
  if grep -nE '(sk-[a-zA-Z0-9_-]{20,}|pk-[a-zA-Z0-9_-]{20,}|ghp_|gho_|xoxb-|xoxp-|eyJhbGciOi)' "$file" 2>/dev/null; then
    ISSUES="$ISSUES\nSECRET DETECTED in $file"
  fi

  # Check for Supabase service role key (anon key in xcconfig is OK)
  if grep -nE 'SUPABASE_SERVICE_ROLE_KEY|service_role' "$file" 2>/dev/null; then
    ISSUES="$ISSUES\nSERVICE ROLE KEY reference in $file — use anon key only in client code"
  fi

  # Check for hardcoded user paths
  if grep -nE '/Users/[a-zA-Z]+/|/home/[a-zA-Z]+/' "$file" 2>/dev/null; then
    ISSUES="$ISSUES\nHARDCODED PATH in $file"
  fi
done

# Check for .env files being committed
for file in $STAGED_FILES; do
  case "$file" in
    .env|.env.*|*.env)
      ISSUES="$ISSUES\nENV FILE staged: $file — remove from commit"
      ;;
  esac
done

# Check for xcconfig with real keys
for file in $STAGED_FILES; do
  case "$file" in
    *.xcconfig)
      if grep -E 'eyJ[a-zA-Z0-9]' "$file" 2>/dev/null; then
        ISSUES="$ISSUES\nXCCONFIG with real key staged: $file — add to .gitignore"
      fi
      ;;
  esac
done

if [ -n "$ISSUES" ]; then
  echo "PRE-COMMIT SECURITY SCAN FAILED:"
  echo -e "$ISSUES"
  exit 2
fi

exit 0
