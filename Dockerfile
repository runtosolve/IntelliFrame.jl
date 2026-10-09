FROM julia:1.12-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/*

COPY IntelliFrame.jl-main/certs/ /usr/local/share/ca-certificates/
RUN update-ca-certificates

ENV JULIA_PKG_USE_CLI_GIT=true \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    JULIA_SSL_CA_ROOTS_PATH=/etc/ssl/certs/ca-certificates.crt

COPY IntelliFrame.jl-main /src/IntelliFrame.jl-main
COPY PurlinLine /src/PurlinLine
WORKDIR /src/IntelliFrame.jl-main/api

RUN julia --project=. -e 'using Pkg; Pkg.Registry.add("General"); Pkg.resolve(); Pkg.instantiate(); Pkg.precompile()'

EXPOSE 8001

HEALTHCHECK --interval=10s --timeout=5s --start-period=180s --retries=12 \
    CMD curl -fsS http://localhost:8001/ || exit 1

CMD ["julia", "--project=.", "src/server.jl"]
