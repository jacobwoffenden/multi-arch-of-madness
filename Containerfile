FROM docker.io/ubuntu:24.04@sha256:c35e29c9450151419d9448b0fd75374fec4fff364a27f176fb458d472dfc9e54

RUN <<EOF
apt-get update --yes

apt-get install --yes --no-install-recommends \
    ca-certificates

apt-get clean --yes

rm --force --recursive /var/lib/apt/lists/*
EOF
