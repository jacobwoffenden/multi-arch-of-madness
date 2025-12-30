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
if ! command -v cosign &>/dev/null; then
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
	"${IMAGE_NAME}" >/dev/null 2>&1; then
	echo "✅ Signature verification PASSED"
	echo ""
	echo "📜 Signature details:"
	cosign verify \
		--certificate-identity-regexp "^https://github.com/${REPO}/.github/workflows/release.yml@refs/tags/.*" \
		--certificate-oidc-issuer https://token.actions.githubusercontent.com \
		"${IMAGE_NAME}" | jq -r '.[] | "  Digest: \(.critical.image."docker-manifest-digest")"'
	echo ""
else
	echo "❌ Signature verification FAILED"
	exit 1
fi

# Check for attestations
echo "🔍 Checking for attestations..."
echo ""

# Check for attestation manifests using docker buildx
ATTESTATION_DIGESTS=$(docker buildx imagetools inspect "${IMAGE_NAME}" --raw 2>/dev/null | jq -r '.manifests[]? | select(.annotations["vnd.docker.reference.type"] == "attestation-manifest") | .digest' 2>/dev/null)

if [[ -n "${ATTESTATION_DIGESTS}" ]]; then
	ATTESTATION_COUNT=$(echo "${ATTESTATION_DIGESTS}" | wc -l)
	echo "✅ Found ${ATTESTATION_COUNT} attestation manifest(s)"
	echo ""

	# Get platform information for each attestation
	declare -A ATTESTATION_PLATFORMS
	MAIN_MANIFEST=$(docker buildx imagetools inspect "${IMAGE_NAME}" --raw 2>/dev/null)

	for ATT_DIGEST in ${ATTESTATION_DIGESTS}; do
		# Attestation manifests have vnd.docker.reference.digest annotation pointing to the actual image
		IMAGE_DIGEST=$(echo "${MAIN_MANIFEST}" | jq -r --arg digest "${ATT_DIGEST}" '.manifests[] | select(.digest == $digest) | .annotations["vnd.docker.reference.digest"]' 2>/dev/null)

		if [[ -n "${IMAGE_DIGEST}" && "${IMAGE_DIGEST}" != "null" ]]; then
			# Find the platform of the referenced image in the main manifest
			PLATFORM=$(echo "${MAIN_MANIFEST}" | jq -r --arg digest "${IMAGE_DIGEST}" '.manifests[] | select(.digest == $digest) | .platform | "\(.os)/\(.architecture)"' 2>/dev/null)
		fi

		# Default to "unknown" if we still can't determine the platform
		if [[ -z "${PLATFORM}" || "${PLATFORM}" == "null" || "${PLATFORM}" == "/" ]]; then
			PLATFORM="unknown/unknown"
		fi

		ATTESTATION_PLATFORMS["${ATT_DIGEST}"]="${PLATFORM}"
	done

	# Check each attestation manifest for predicate types
	for DIGEST in ${ATTESTATION_DIGESTS}; do
		PLATFORM="${ATTESTATION_PLATFORMS[${DIGEST}]}"
		PREDICATES=$(docker buildx imagetools inspect "ghcr.io/${REPO}@${DIGEST}" --raw 2>/dev/null | jq -r '.layers[]?.annotations."in-toto.io/predicate-type"' 2>/dev/null | sort -u)

		while IFS= read -r PREDICATE; do
			case "${PREDICATE}" in
			"https://spdx.dev/Document")
				echo "📦 SBOM (Software Bill of Materials) [${PLATFORM}]:"
				echo "  ✅ SBOM attestation found (SPDX format)"
				echo "  Type: ${PREDICATE}"

				# Get and display SBOM details
				SBOM_DIGEST=$(docker buildx imagetools inspect "ghcr.io/${REPO}@${DIGEST}" --raw 2>/dev/null | jq -r '.layers[] | select(.annotations."in-toto.io/predicate-type" == "https://spdx.dev/Document") | .digest' 2>/dev/null | head -1)
				if [[ -n "${SBOM_DIGEST}" ]]; then
					# Download the SBOM blob using crane
					SBOM_DATA=$(docker run --rm gcr.io/go-containerregistry/crane:latest blob "ghcr.io/${REPO}@${SBOM_DIGEST}" 2>/dev/null)

					if [[ -n "${SBOM_DATA}" ]]; then
						PACKAGE_COUNT=$(echo "${SBOM_DATA}" | jq -r '.predicate.packages | length' 2>/dev/null || echo "unknown")
						SPDX_VERSION=$(echo "${SBOM_DATA}" | jq -r '.predicate.spdxVersion' 2>/dev/null || echo "unknown")

						if [[ "${PACKAGE_COUNT}" != "unknown" ]]; then
							echo "  Format: ${SPDX_VERSION}"
							echo "  Total packages: ${PACKAGE_COUNT}"

							# Show some key packages
							echo "  Sample packages:"
							echo "${SBOM_DATA}" | jq -r '.predicate.packages[] | select(.name != null) | "    • \(.name) \(.versionInfo // "unknown")"' 2>/dev/null | head -5
						fi
					fi
				fi
				echo ""
				;;
			"https://slsa.dev/provenance/v0.2")
				echo "🏗️  Provenance (Build Information) [${PLATFORM}]:"
				echo "  ✅ Provenance attestation found (SLSA v0.2)"
				echo "  Type: ${PREDICATE}"

				# Get and display provenance details
				PROV_DIGEST=$(docker buildx imagetools inspect "ghcr.io/${REPO}@${DIGEST}" --raw 2>/dev/null | jq -r '.layers[] | select(.annotations."in-toto.io/predicate-type" == "https://slsa.dev/provenance/v0.2") | .digest' 2>/dev/null | head -1)
				if [[ -n "${PROV_DIGEST}" ]]; then
					# Download the provenance blob using crane
					PROV_DATA=$(docker run --rm gcr.io/go-containerregistry/crane:latest blob "ghcr.io/${REPO}@${PROV_DIGEST}" 2>/dev/null)

					if [[ -n "${PROV_DATA}" ]]; then
						BUILDER=$(echo "${PROV_DATA}" | jq -r '.predicate.builder.id' 2>/dev/null || echo "unknown")
						BUILD_TYPE=$(echo "${PROV_DATA}" | jq -r '.predicate.buildType' 2>/dev/null || echo "unknown")
						BUILD_STARTED=$(echo "${PROV_DATA}" | jq -r '.predicate.metadata.buildStartedOn' 2>/dev/null || echo "unknown")
						BUILD_FINISHED=$(echo "${PROV_DATA}" | jq -r '.predicate.metadata.buildFinishedOn' 2>/dev/null || echo "unknown")

						if [[ "${BUILDER}" != "unknown" && "${BUILDER}" != "null" ]]; then
							echo "  Builder: ${BUILDER}"
							echo "  Build type: ${BUILD_TYPE}"
							echo "  Build started: ${BUILD_STARTED}"
							echo "  Build finished: ${BUILD_FINISHED}"

							# Show base image materials
							MATERIALS=$(echo "${PROV_DATA}" | jq -r '.predicate.materials[]?.uri' 2>/dev/null | head -3)
							if [[ -n "${MATERIALS}" ]]; then
								echo "  Base images:"
								echo "${MATERIALS}" | while read -r MATERIAL; do
									echo "    • ${MATERIAL}"
								done
							fi
						fi
					fi
				fi
				echo ""
				;;
			esac
		done <<<"${PREDICATES}"
	done

	echo "ℹ️  Note: Attestations are native BuildKit attestations (not cosign-signed)"
else
	echo "⚠️  No attestation manifests found"
fi

echo ""
echo "✨ Verification complete!"
exit 0
