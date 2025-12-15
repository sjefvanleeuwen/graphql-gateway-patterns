#!/bin/bash
# ============================================================================
# Post-Provision Script (Bash)
# Runs after azd provision to compose and publish FGP schema
# ============================================================================

set -e

ENVIRONMENT="${AZURE_ENV_NAME:-dev}"
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-}"
SKIP_FGP_PUBLISH="${SKIP_FGP_PUBLISH:-false}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Post-Provision: GraphQL Gateway                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Get deployment outputs from azd
echo "📋 Reading deployment outputs..."

GATEWAY_URL=$(azd env get-value GATEWAY_URL 2>/dev/null || echo "")
FRONTEND_URL=$(azd env get-value FRONTEND_URL 2>/dev/null || echo "")
NITRO_WS_URL=$(azd env get-value NITRO_WS_URL 2>/dev/null || echo "")
NITRO_FQDN=$(azd env get-value NITRO_INTERNAL_FQDN 2>/dev/null || echo "")

echo ""
echo "🌐 Deployed Endpoints:"
echo "   Gateway:  $GATEWAY_URL"
echo "   Frontend: $FRONTEND_URL"
echo "   Nitro WS: $NITRO_WS_URL"
echo ""

if [ "$SKIP_FGP_PUBLISH" = "true" ]; then
    echo "⏭️  Skipping FGP publish (SKIP_FGP_PUBLISH=true)"
    exit 0
fi

# Check if Nitro is available
if [ -z "$NITRO_FQDN" ]; then
    echo "⚠️  NITRO_INTERNAL_FQDN not set, skipping FGP publish"
    echo "   You can manually publish later with: src/compose-fgp.ps1 -Environment aca"
    exit 0
fi

# Wait for Container Apps to stabilize
echo "⏳ Waiting 45 seconds for Container Apps to stabilize..."
sleep 45

# Navigate to src directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
SRC_DIR="$REPO_ROOT/src"

if [ ! -d "$SRC_DIR" ]; then
    echo "❌ Cannot find src directory at: $SRC_DIR"
    exit 1
fi

cd "$SRC_DIR"

# Check for compose-fgp.ps1
if [ ! -f "compose-fgp.ps1" ]; then
    echo "❌ compose-fgp.ps1 not found"
    exit 1
fi

echo ""
echo "🔧 Composing and publishing FGP schema..."
echo ""

# Run compose-fgp.ps1 via PowerShell
RG_PARAM=""
if [ -n "$RESOURCE_GROUP" ]; then
    RG_PARAM="-ResourceGroup $RESOURCE_GROUP"
fi

pwsh -File compose-fgp.ps1 -Environment aca $RG_PARAM

echo ""
echo "✅ FGP schema published successfully!"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Deployment Complete!                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "🚀 Your GraphQL Gateway is ready at:"
echo "   $GATEWAY_URL"
echo ""
echo "🎨 Frontend available at:"
echo "   $FRONTEND_URL"
echo ""
