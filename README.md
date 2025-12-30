# multi-arch-of-madness

_:copilot: This documentation was created by GitHub Copilot_

> **A practical example of building and releasing multi-architecture container images with GitHub Actions**

This repository demonstrates how to build, test, and release multi-architecture (amd64 and arm64) container images using GitHub Actions with native attestation support.

## 🎯 What This Demonstrates

- ✅ Multi-architecture container builds (amd64 + arm64)
- ✅ Matrix-based parallel builds using native runners
- ✅ Multi-arch manifest creation and publishing
- ✅ Native Docker/BuildKit attestations (provenance + SBOM)
- ✅ Keyless image signing with Sigstore cosign
- ✅ Automated releases triggered by Git tags
- ✅ **Reusable workflow** - use in other repositories with optional ARM64 builds

## 🏗️ Architecture

### Build Strategy

The workflow uses a **matrix strategy** to build platform-specific images in parallel:

- **amd64**: Builds on `ubuntu-latest` (x86_64)
- **arm64**: Builds on `ubuntu-24.04-arm` (ARM64 native)

Each platform build:

1. Creates a platform-specific Docker Buildx context
2. Builds and pushes the image by digest (not tag)
3. Exports the digest as an artifact

### Manifest Merge

After both platform builds complete, a merge job:

1. Downloads all platform digests
2. Creates a multi-arch manifest combining both images
3. Tags and pushes the unified manifest

Users can then pull the image and Docker automatically selects the correct architecture.

## 📦 Release Workflow

The workflow can be used in two ways:

### 1. Direct Use (This Repository)

Releases are automatically triggered when you push a tag:

```bash
git tag 0.0.1-rc1
git push origin 0.0.1-rc1
```

**Tag Handling:**

- **Prereleases** (tags with `-rc`, `-alpha`, `-beta`, etc.) are tagged with the version only
- **Stable releases** (e.g., `1.0.0`) automatically get the `latest` tag in addition to version tags
- The `docker/metadata-action` automatically detects SemVer prerelease identifiers and only applies `latest` to stable releases

### 2. Reusable Workflow (Other Repositories)

Starting with v2.0.0, the workflow can be called from other repositories:

```yaml
# .github/workflows/release.yml in your repository
name: Release

on:
  push:
    tags:
      - "v*"

jobs:
  build:
    uses: jacobwoffenden/multi-arch-of-madness/.github/workflows/release.yml@v2
    permissions:
      contents: read
      id-token: write
      packages: write
    # Optional: customize behavior
    # with:
    #   enable-arm64: false  # Set to false for AMD64-only builds (default: true)
    #   image-name: ghcr.io/myorg/myimage  # Override image name (default: ghcr.io/<repo>)
```

**Reusable Workflow Features:**

- **Optional ARM64**: Toggle ARM64 builds with `enable-arm64` input (defaults to `true`)
- **Customisable image name**: Override with `image-name` input (defaults to caller's repository)
- **Dynamic matrix**: Automatically adjusts build matrix based on enabled architectures
- **Unified finalisation**: Single job handles both single-arch and multi-arch builds efficiently

### Jobs

#### 1. Setup Build Matrix

Generates the build matrix dynamically based on inputs (for reusable workflow) or defaults to both architectures:

**Steps:**

- Determines which platforms to build (amd64 always, arm64 optional)
- Outputs matrix configuration for parallel builds
- Sets `multi-arch` flag for downstream jobs

#### 2. Build and Push (Matrix)

Runs in parallel for each enabled architecture:

```yaml
matrix:
  platform:
    - amd64
    - arm64 # (if enabled)
```

**Steps:**

- Checkout code
- Generate Docker metadata (labels, annotations)
- Create platform-specific Buildx context
- Login to GitHub Container Registry
- Build and push image by digest
- Export and upload digest artifact

**Key Configuration:**

- Uses `push-by-digest=true` to push without tags initially
- Enables OCI media types for attestations
- Runs on native architecture runners for optimal performance

#### 3. Finalise (Create Manifest and Sign)

Runs after all platform builds complete. Handles both single-arch and multi-arch builds:

**Steps:**

- Download all platform digests
- Generate image tags from Git tag
- Create manifest using `docker buildx imagetools create` (works for one or multiple digests)
- Push manifest with proper tags
- Inspect final image
- Sign image with Cosign (recursively for multi-arch)
- Verify signature using digest reference

## 🔐 Attestations

This workflow includes **native Docker/BuildKit attestations** automatically:

### What's Included

- **Provenance**: SLSA build provenance showing:
  - GitHub Actions workflow that built the image
  - Exact commit SHA and build environment
  - Build parameters and configuration
- **SBOM**: Software Bill of Materials containing:
  - All packages and dependencies in the image
  - Version information
  - Licence data

### Per-Platform Attestations

Each architecture gets its own attestation, stored as "unknown" platform entries in the manifest. This ensures accurate SBOM data for each architecture's specific packages.

### Viewing Attestations

```bash
# View all platforms and attestations
docker buildx imagetools inspect ghcr.io/jacobwoffenden/multi-arch-of-madness:1.1.0-rc3

# View raw manifest (includes attestations)
docker buildx imagetools inspect --raw ghcr.io/jacobwoffenden/multi-arch-of-madness:1.1.0-rc3 | jq
```

### Downloading and Inspecting Attestations

Each image includes two types of attestations that are automatically generated and signed:

#### Finding Attestation Digests

To get the digests for SBOM and provenance attestations:

```bash
# List all attestation manifests
docker buildx imagetools inspect ghcr.io/jacobwoffenden/multi-arch-of-madness:1.1.0-rc3 --raw \
  | jq -r '.manifests[] | select(.annotations["vnd.docker.reference.type"] == "attestation-manifest") | .digest'

# View attestation types in a specific attestation manifest
docker run --rm gcr.io/go-containerregistry/crane:latest \
  manifest ghcr.io/jacobwoffenden/multi-arch-of-madness@sha256:ATTESTATION_MANIFEST_DIGEST \
  | jq -r '.layers[] | "\(.annotations["in-toto.io/predicate-type"]): \(.digest)"'
```

#### SBOM (Software Bill of Materials)

The SBOM uses **SPDX 2.3** format and contains a complete inventory of all packages:

```bash
# Download SBOM using Docker (requires crane)
docker run --rm gcr.io/go-containerregistry/crane:latest \
  blob ghcr.io/jacobwoffenden/multi-arch-of-madness@sha256:SBOM_DIGEST | jq

# View package summary
docker run --rm gcr.io/go-containerregistry/crane:latest \
  blob ghcr.io/jacobwoffenden/multi-arch-of-madness@sha256:SBOM_DIGEST \
  | jq -r '.predicate.packages[] | "• \(.name) \(.versionInfo)"'

# Search for a specific package (e.g., openssl)
docker run --rm gcr.io/go-containerregistry/crane:latest \
  blob ghcr.io/jacobwoffenden/multi-arch-of-madness@sha256:SBOM_DIGEST \
  | jq '.predicate.packages[] | select(.name == "openssl")'
```

**SBOM includes for each package:**

- Package name and version
- SPDX identifier
- CPE (Common Platform Enumeration) for vulnerability scanning
- PURL (Package URL) for package management
- License information
- Copyright details

**Example package entry:**

```json
{
  "name": "openssl",
  "versionInfo": "3.0.13-0ubuntu3.6",
  "SPDXID": "SPDXRef-Package-deb-openssl-72ce342c53b6cc41",
  "externalRefs": [
    {
      "referenceCategory": "SECURITY",
      "referenceType": "cpe23Type",
      "referenceLocator": "cpe:2.3:a:openssl:openssl:3.0.13-0ubuntu3.6:*:*:*:*:*:*:*"
    },
    {
      "referenceCategory": "PACKAGE-MANAGER",
      "referenceType": "purl",
      "referenceLocator": "pkg:deb/ubuntu/openssl@3.0.13-0ubuntu3.6?arch=amd64&distro=ubuntu-24.04"
    }
  ]
}
```

#### Provenance (Build Attestation)

The provenance uses **SLSA v0.2** format and proves how the image was built:

```bash
# Download provenance
docker run --rm gcr.io/go-containerregistry/crane:latest \
  blob ghcr.io/jacobwoffenden/multi-arch-of-madness@sha256:PROVENANCE_DIGEST | jq

# View build details
docker run --rm gcr.io/go-containerregistry/crane:latest \
  blob ghcr.io/jacobwoffenden/multi-arch-of-madness@sha256:PROVENANCE_DIGEST \
  | jq '.predicate | {builder, buildType, buildStarted: .metadata.buildStartedOn, buildFinished: .metadata.buildFinishedOn}'
```

**Provenance includes:**

- **Builder ID**: Exact GitHub Actions workflow run URL
- **Build Type**: Moby BuildKit v1
- **Build Timestamps**: Start and finish times
- **Materials**: Base images and build tools used (with digests)

**Example provenance:**

```json
{
  "builder": {
    "id": "https://github.com/jacobwoffenden/multi-arch-of-madness/actions/runs/20558044805/attempts/1"
  },
  "buildType": "https://mobyproject.org/buildkit@v1",
  "metadata": {
    "buildStartedOn": "2025-12-28T18:47:39.863895944Z",
    "buildFinishedOn": "2025-12-28T18:47:49.007939784Z"
  },
  "materials": [
    {
      "uri": "pkg:docker/ubuntu@24.04",
      "digest": {
        "sha256": "c35e29c9450151419d9448b0fd75374fec4fff364a27f176fb458d472dfc9e54"
      }
    }
  ]
}
```

#### Using Attestations with Security Tools

**Grype (Vulnerability Scanning):**

```bash
grype ghcr.io/jacobwoffenden/multi-arch-of-madness:1.1.0-rc3 --use-embedded-attestation
```

**Syft (SBOM Analysis):**

```bash
syft ghcr.io/jacobwoffenden/multi-arch-of-madness:1.1.0-rc3 --source-version attestation
```

**Docker Scout:**

```bash
docker scout cves ghcr.io/jacobwoffenden/multi-arch-of-madness:1.1.0-rc3
```

All attestations are cryptographically signed with cosign and can be verified using the same process as image signatures.

## 🔏 Image Signing with Cosign

All released container images are signed using [Sigstore cosign](https://docs.sigstore.dev/cosign/overview/) with **keyless signing**. This provides cryptographic verification that images were built by this repository's GitHub Actions workflow.

### What's Signed

- **Multi-architecture manifest** (the top-level "manifest of manifests")
- **Individual platform manifests** (amd64 and arm64 specific manifests)
- Signed recursively using `--recursive` flag for compatibility with tools that pull specific architectures
- Signed using GitHub's OIDC identity (no key management required)
- Signatures stored in the public [Sigstore Rekor transparency log](https://rekor.sigstore.dev/)

### Why This Matters

Image signing provides:

- **Authenticity**: Cryptographically proves the image came from this repository
- **Integrity**: Ensures the image hasn't been tampered with
- **Transparency**: All signatures are publicly auditable via Rekor
- **Trust**: Verifies the exact GitHub Actions workflow that built the image
- **Architecture-specific verification**: Recursive signing ensures individual architecture manifests can be verified independently (critical for internal registries that pull specific architectures)

### Verifying Signatures

#### Quick Verification

Use the provided verification script:

```bash
# Clone the repository
git clone https://github.com/jacobwoffenden/multi-arch-of-madness.git
cd multi-arch-of-madness

# Verify a specific tag
./verify-signature.sh 0.0.1-rc18

# Verify latest tag
./verify-signature.sh latest
```

#### Manual Verification

Install cosign:

```bash
# macOS
brew install sigstore/tap/cosign

# Linux (Debian/Ubuntu)
wget "https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64"
sudo mv cosign-linux-amd64 /usr/local/bin/cosign
sudo chmod +x /usr/local/bin/cosign

# Windows
# See: https://docs.sigstore.dev/cosign/system_config/installation/
```

Verify the signature:

```bash
# Verify the multi-arch manifest (recommended)
cosign verify \
  --certificate-identity-regexp "^https://github.com/jacobwoffenden/multi-arch-of-madness/.github/workflows/release.yml@refs/tags/.*" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc18 | jq

# Verify a specific architecture by digest (also works thanks to --recursive signing)
cosign verify \
  --certificate-identity-regexp "^https://github.com/jacobwoffenden/multi-arch-of-madness/.github/workflows/release.yml@refs/tags/.*" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/jacobwoffenden/multi-arch-of-madness@sha256:DIGEST_OF_SPECIFIC_ARCH | jq
```

**Expected output:**

```json
[
  {
    "critical": {
      "identity": {
        "docker-reference": "ghcr.io/jacobwoffenden/multi-arch-of-madness"
      },
      "image": {
        "docker-manifest-digest": "sha256:..."
      },
      "type": "cosign container image signature"
    },
    "optional": {
      "githubWorkflowRef": "refs/tags/0.0.1-rc18",
      "githubWorkflowRepository": "jacobwoffenden/multi-arch-of-madness",
      ...
    }
  }
]
```

### Integration with Container Runtimes

You can enforce signature verification at runtime using policy engines:

**Kubernetes with Kyverno:**

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-multi-arch-images
spec:
  validationFailureAction: enforce
  rules:
    - name: verify-signature
      match:
        any:
          - resources:
              kinds:
                - Pod
      verifyImages:
        - imageReferences:
            - "ghcr.io/jacobwoffenden/multi-arch-of-madness:*"
          attestors:
            - entries:
                - keyless:
                    subject: "https://github.com/jacobwoffenden/multi-arch-of-madness/.github/workflows/release.yml@refs/tags/*"
                    issuer: "https://token.actions.githubusercontent.com"
```

**Docker with Cosign:**

```bash
# Set environment variable to enforce verification
export COSIGN_REPOSITORY=ghcr.io/jacobwoffenden/multi-arch-of-madness

# Docker will verify before running
cosign verify --certificate-identity-regexp "^https://github.com/jacobwoffenden/multi-arch-of-madness/.*" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/jacobwoffenden/multi-arch-of-madness:latest && \
docker run --rm ghcr.io/jacobwoffenden/multi-arch-of-madness:latest
```

### Important Notes

**Why `--recursive` signing?**

When using `--recursive`, cosign signs both the multi-arch manifest AND each individual platform manifest. This is critical for:

- **Internal registries/mirrors** that pull specific architectures (not the full multi-arch manifest)
- **CI/CD pipelines** that verify specific platform images
- **Security scanners** that need to verify per-architecture images

Without `--recursive`, verification would fail when checking platform-specific manifests by digest, even though the top-level manifest is signed. This is a common pitfall in enterprise environments where "MirrorBot" systems pull only the architectures they need.

**Reference:** [Signing and verifying multi-architecture containers with Sigstore](https://some-natalie.dev/blog/sigstore-multiarch/) by Natalie Somersall

## 🧪 Testing

### Pull and Run

```bash
# Pull multi-arch image (auto-selects your platform)
docker pull ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc18

# Pull specific architecture
docker pull --platform linux/amd64 ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc18
docker pull --platform linux/arm64 ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc18

# Run the image
docker run --rm ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc18
```

### Verify Architecture

```bash
# Check which architecture was pulled
docker inspect ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc18 | jq '.[0].Architecture'

# View all available platforms
docker manifest inspect ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc18
```

## 📋 Key Workflow Features

### Security Hardening

- Uses `step-security/harden-runner` for public repositories
- Pins all actions to specific commit SHAs
- Minimal permissions (principle of least privilege)
- OIDC token authentication for registry login
- Keyless image signing with cosign (Sigstore)
- Public transparency log via Rekor

### Optimisation

- Parallel matrix builds for faster execution
- Native architecture runners (no emulation overhead)
- Artifact-based digest passing between jobs
- Short artifact retention (1 day)

### Best Practices

- Immutable action versions (SHA pinning)
- Proper permission scoping per job
- OCI-compliant image formats
- Comprehensive metadata (labels, annotations)
- Shellcheck compliant shell scripts with documented exceptions

## 🔄 Workflow Files

- [`.github/workflows/release.yml`](.github/workflows/release.yml) - Multi-arch release workflow (reusable)
- [`.github/workflows/_release.yml`](.github/workflows/_release.yml) - Example usage of reusable workflow
- [`.github/workflows/build.yml`](.github/workflows/build.yml) - PR build and test workflow
- [`.github/workflows/archive/release.yml`](.github/workflows/archive/release.yml) - Original v1.x workflow (archived)

## 🔧 Reusable Workflow API

### Inputs

| Input          | Type      | Required | Default          | Description                              |
| -------------- | --------- | -------- | ---------------- | ---------------------------------------- |
| `enable-arm64` | `boolean` | No       | `true`           | Build ARM64 image in addition to AMD64   |
| `image-name`   | `string`  | No       | `ghcr.io/<repo>` | Container image name (overrides default) |

### Required Permissions

When calling the reusable workflow, you must grant these permissions:

```yaml
permissions:
  contents: read # Read repository contents
  id-token: write # Generate OIDC tokens for signing
  packages: write # Push to GitHub Container Registry
```

### Use Cases

**Default (Multi-arch):**

```yaml
uses: jacobwoffenden/multi-arch-of-madness/.github/workflows/release.yml@v2
```

**AMD64 only:**

```yaml
uses: jacobwoffenden/multi-arch-of-madness/.github/workflows/release.yml@v2
with:
  enable-arm64: false
```

**Custom image name:**

```yaml
uses: jacobwoffenden/multi-arch-of-madness/.github/workflows/release.yml@v2
with:
  image-name: ghcr.io/myorg/custom-image
```

## 📚 Additional Resources

- [Docker Buildx Documentation](https://docs.docker.com/build/buildx/)
- [Multi-platform Images](https://docs.docker.com/build/building/multi-platform/)
- [OCI Image Spec](https://github.com/opencontainers/image-spec)
- [GitHub Actions: Larger Runners](https://docs.github.com/en/actions/using-github-hosted-runners/about-larger-runners)

## 🤝 Contributing

This is an example repository for learning purposes. Feel free to use it as a template for your own multi-arch builds!

## 📄 Licence

MIT
