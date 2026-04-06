#!/bin/bash
# Bootstrap script for Proof Capture — sets up local config files needed to build.
# Run once after cloning: ./scripts/bootstrap.sh
#
# The build works on clean checkout without running this script (BuildConfig.xcconfig
# provides placeholder values). Run bootstrap only when you need real Supabase credentials.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

XCCONFIG="$PROJECT_DIR/Supabase.xcconfig"
TEMPLATE="$PROJECT_DIR/Supabase.xcconfig.example"

if [ -f "$XCCONFIG" ]; then
    echo "Supabase.xcconfig already exists — validating..."
else
    if [ ! -f "$TEMPLATE" ]; then
        echo "ERROR: Supabase.xcconfig.example not found at $TEMPLATE"
        exit 1
    fi
    cp "$TEMPLATE" "$XCCONFIG"
    echo "Created Supabase.xcconfig from template."
    echo "Fill in real values to connect to Supabase."
fi

# Validate xcconfig: warn if any value contains bare // (xcconfig treats it as a comment)
if grep -v '^\s*//' "$XCCONFIG" | grep -q '[^$]//'; then
    echo ""
    echo "WARNING: Supabase.xcconfig contains bare '//' in a value."
    echo "xcconfig treats // as a comment delimiter — everything after it is stripped."
    echo "Use /\$()/ instead of // in URL values."
    echo ""
    echo "Example:"
    echo "  BAD:  SUPABASE_URL = https://example.supabase.co"
    echo "  GOOD: SUPABASE_URL = https:/\$()/example.supabase.co"
    echo ""
    exit 1
fi

echo ""
echo "Build with:"
echo "  xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO"
