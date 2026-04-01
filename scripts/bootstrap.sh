#!/bin/bash
# Bootstrap script for Proof Capture — sets up local config files needed to build.
# Run once after cloning: ./scripts/bootstrap.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Create Supabase.xcconfig from template if it doesn't exist
XCCONFIG="$PROJECT_DIR/Supabase.xcconfig"
TEMPLATE="$PROJECT_DIR/Supabase.xcconfig.example"

if [ -f "$XCCONFIG" ]; then
    echo "Supabase.xcconfig already exists — skipping."
else
    if [ ! -f "$TEMPLATE" ]; then
        echo "ERROR: Supabase.xcconfig.example not found at $TEMPLATE"
        exit 1
    fi
    cp "$TEMPLATE" "$XCCONFIG"
    echo "Created Supabase.xcconfig from template."
    echo "Fill in real values before running the app with Supabase."
fi

echo "Bootstrap complete. Build with:"
echo "  xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO"
