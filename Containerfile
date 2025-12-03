ARG BASE

FROM ${BASE}

RUN <<EOF
apt-get update --yes

apt-get install --yes --no-install-recommends \
    ca-certificates

apt-get clean --yes

rm --force --recursive /var/lib/apt/lists/*
EOF
