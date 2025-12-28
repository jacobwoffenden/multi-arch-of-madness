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

### Trigger

Releases are automatically triggered when you push a tag:

```bash
git tag 0.0.1-rc1
git push origin 0.0.1-rc1
```

**Tag Handling:**

- **Prereleases** (tags with `-rc`, `-alpha`, `-beta`, etc.) are tagged with the version only
- **Stable releases** (e.g., `1.0.0`) automatically get the `latest` tag in addition to version tags
- The `docker/metadata-action` automatically detects SemVer prerelease identifiers and only applies `latest` to stable releases

### Jobs

#### 1. Build and Push (Matrix)

Runs in parallel for each architecture:

```yaml
matrix:
  platform:
    - amd64
    - arm64
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

#### 2. Create Multi-Arch Manifest

Runs after both platform builds complete:

**Steps:**

- Download all platform digests
- Generate image tags from Git tag
- Create multi-arch manifest using `docker buildx imagetools create`
- Push manifest with proper tags
- Inspect final multi-arch image

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

### Verifying Attestations

```bash
# View all platforms and attestations
docker buildx imagetools inspect ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc18

# View raw manifest (includes attestations)
docker buildx imagetools inspect --raw ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc18 | jq
```

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

- [`.github/workflows/release.yml`](.github/workflows/release.yml) - Multi-arch release workflow
- [`.github/workflows/build.yml`](.github/workflows/build.yml) - PR build and test workflow

## 📚 Additional Resources

- [Docker Buildx Documentation](https://docs.docker.com/build/buildx/)
- [Multi-platform Images](https://docs.docker.com/build/building/multi-platform/)
- [OCI Image Spec](https://github.com/opencontainers/image-spec)
- [GitHub Actions: Larger Runners](https://docs.github.com/en/actions/using-github-hosted-runners/about-larger-runners)

## 🤝 Contributing

This is an example repository for learning purposes. Feel free to use it as a template for your own multi-arch builds!

## 📄 Licence

MIT
