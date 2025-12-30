FROM docker.io/ubuntu:24.04@sha256:c35e29c9450151419d9448b0fd75374fec4fff364a27f176fb458d472dfc9e54

ARG TARGETARCH \
    UV_VERSION="0.9.21"

SHELL ["/bin/bash", "-e", "-u", "-o", "pipefail", "-c"]

RUN <<EOF
apt-get update --yes

apt-get install --yes --no-install-recommends \
    ca-certificates \
    curl

apt-get clean --yes

rm --force --recursive /var/lib/apt/lists/*
EOF

# Install uv
RUN <<EOF
case "${TARGETARCH}" in \
    "amd64") UV_ARCH="x86_64" ;; \
    "arm64") UV_ARCH="aarch64" ;; \
    *) echo "Unsupported architecture: ${TARGETARCH}" >&2 ; exit 1 ;; \
esac

UV_ARCHIVE="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${UV_ARCH}-unknown-linux-gnu.tar.gz"
UV_CHECKSUM="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${UV_ARCH}-unknown-linux-gnu.tar.gz.sha256"

curl --proto '=https' --tlsv1.2 --location --silent --show-error --fail --output "uv-${UV_ARCH}-unknown-linux-gnu.tar.gz" "${UV_ARCHIVE}"
curl --proto '=https' --tlsv1.2 --location --silent --show-error --fail --output "uv-${UV_ARCH}-unknown-linux-gnu.tar.gz.sha256" "${UV_CHECKSUM}"

sha256sum --check "uv-${UV_ARCH}-unknown-linux-gnu.tar.gz.sha256"

tar --extract --gzip --file "uv-${UV_ARCH}-unknown-linux-gnu.tar.gz" --directory /usr/local/bin/ --strip-components 1 "uv-${UV_ARCH}-unknown-linux-gnu/uv" "uv-${UV_ARCH}-unknown-linux-gnu/uvx"

rm --force "uv-${UV_ARCH}-unknown-linux-gnu.tar.gz" "uv-${UV_ARCH}-unknown-linux-gnu.tar.gz.sha256"
EOF