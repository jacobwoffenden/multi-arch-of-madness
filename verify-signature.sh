#!/bin/bash
set -euo pipefail

# Verify cosign signature for multi-arch-of-madness container images
# Usage: ./verify-signature.sh [IMAGE_TAG]
# Example: ./verify-signature.sh 0.0.1-rc1

REPO="jacobwoffenden/multi-arch-of-madness"
IMAGE_TAG="${1:-latest}"
IMAGE_NAME="ghcr.io/${REPO}:${IMAGE_TAG}"

echo "🔐 Verifying cosign signature for: ${IMAGE_NAME}"
echo ""

# Check if cosign is installed
if ! command -v cosign &> /dev/null; then
    echo "❌ Error: cosign is not installed"
    echo ""
    echo "Install cosign:"
    echo "  macOS:   brew install sigstore/tap/cosign"
    echo "  Linux:   See https://docs.sigstore.dev/cosign/system_config/installation/"
    echo "  Windows: See https://docs.sigstore.dev/cosign/system_config/installation/"
    exit 1
fi

echo "📋 Verification criteria:"
echo "  - Certificate identity: https://github.com/${REPO}/.github/workflows/release.yml@refs/tags/*"
echo "  - OIDC issuer: https://token.actions.githubusercontent.com"
echo ""

# Verify the signature
if cosign verify \
    --certificate-identity-regexp "^https://github.com/${REPO}/.github/workflows/release.yml@refs/tags/.*" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    "${IMAGE_NAME}" > /dev/null 2>&1; then
    echo "✅ Signature verification PASSED"
    echo ""
    echo "📜 Signature details:"
    cosign verify \
        --certificate-identity-regexp "^https://github.com/${REPO}/.github/workflows/release.yml@refs/tags/.*" \
        --certificate-oidc-issuer https://token.actions.githubusercontent.com \
        "${IMAGE_NAME}" | jq -r '.[] | "  Digest: \(.critical.image."docker-manifest-digest")"'
    exit 0
else
    echo "❌ Signature verification FAILED"
    exit 1
fi
