# multi-arch-of-madness

> **A practical example of building and releasing multi-architecture container images with GitHub Actions**

This repository demonstrates how to build, test, and release multi-architecture (amd64 and arm64) container images using GitHub Actions with native attestation support.

## 🎯 What This Demonstrates

- ✅ Multi-architecture container builds (amd64 + arm64)
- ✅ Matrix-based parallel builds using native runners
- ✅ Multi-arch manifest creation and publishing
- ✅ Native Docker/BuildKit attestations (provenance + SBOM)
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
- The `docker/metadata-action` uses `latest=auto` to intelligently apply the `latest` tag only to stable releases

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
docker buildx imagetools inspect ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc12

# View raw manifest (includes attestations)
docker buildx imagetools inspect --raw ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc12 | jq
```

## 🧪 Testing

### Pull and Run

```bash
# Pull multi-arch image (auto-selects your platform)
docker pull ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc12

# Pull specific architecture
docker pull --platform linux/amd64 ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc12
docker pull --platform linux/arm64 ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc12

# Run the image
docker run --rm ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc12
```

### Verify Architecture

```bash
# Check which architecture was pulled
docker inspect ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc12 | jq '.[0].Architecture'

# View all available platforms
docker manifest inspect ghcr.io/jacobwoffenden/multi-arch-of-madness:0.0.1-rc12
```

## 📋 Key Workflow Features

### Security Hardening

- Uses `step-security/harden-runner` for public repositories
- Pins all actions to specific commit SHAs
- Minimal permissions (principle of least privilege)
- OIDC token authentication for registry login

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
