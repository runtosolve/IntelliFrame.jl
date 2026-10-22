FROM julia:1.12-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Typst CLI for the PDF reports (POST /intelliframe/export-pdf). Pinned to the version the
# templates in generate_report/ are written against.
ARG TYPST_VERSION=0.14.2
RUN curl -fsSL https://github.com/typst/typst/releases/download/v${TYPST_VERSION}/typst-x86_64-unknown-linux-musl.tar.xz \
    | tar -xJf - --strip-components=1 -C /usr/local/bin/ typst-x86_64-unknown-linux-musl/typst \
    && typst --version

COPY IntelliFrame.jl-main/certs/ /usr/local/share/ca-certificates/
RUN update-ca-certificates

# generic keeps precompile caches valid across Docker Desktop, ECS, and different CPUs.
# native (the default) rebuilds everything at container start when the CPU differs.
ENV JULIA_CPU_TARGET=generic \
    JULIA_PKG_USE_CLI_GIT=true \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    JULIA_SSL_CA_ROOTS_PATH=/etc/ssl/certs/ca-certificates.crt \
    GKSwstype=nul

COPY IntelliFrame.jl-main /src/IntelliFrame.jl-main
COPY PurlinLine /src/PurlinLine
WORKDIR /src/IntelliFrame.jl-main/api

RUN julia --project=. -e 'using Pkg; Pkg.Registry.add("General"); Pkg.resolve(); Pkg.instantiate()'

# Fresh Julia process so instantiate's updated stdlibs are the ones that get cached.
# Loading IntelliFrameAPI here writes the same caches the container uses at start.
RUN julia --project=. -e 'using Pkg; Pkg.precompile(); using HTTP, JSON3, IntelliFrameAPI'

# Two threads: the report warm-up at start (and a running report) must not block the HTTP server,
# or the health check fails while the report pipeline compiles.
ENV JULIA_PKG_PRECOMPILE_AUTO=0 \
    JULIA_NUM_THREADS=2

EXPOSE 8001

HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=12 \
    CMD curl -fsS http://localhost:8001/ || exit 1

CMD ["julia", "--project=.", "src/server.jl"]
