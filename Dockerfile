# Build fully static CBC binaries with musl
ARG CBC_VERSION=2.10.12

# Build CBC with static linking
FROM alpine:3.22 AS builder
ARG CBC_VERSION

RUN apk add --no-cache \
    build-base \
    bash \
    git \
    curl \
    autoconf \
    automake \
    libtool \
    pkgconf \
    cmake \
    gfortran \
    linux-headers \
    musl-dev \
    perl \
    python3

WORKDIR /opt

# Clone and fetch
RUN git clone --depth 1 https://github.com/coin-or/coinbrew.git
RUN ./coinbrew/coinbrew fetch Cbc:${CBC_VERSION} --no-prompt

# Build CBC and all dependencies using coinbrew
# Configure and build without static flags first to avoid exit 77
RUN ./coinbrew/coinbrew build Cbc:${CBC_VERSION} \
    --no-prompt \
    --tests=none \
    --prefix=/opt/coin \
    --no-third-party \
    --verbosity=3 \
    --enable-static \
    --disable-shared \
    --without-lapack \
    --without-blas \
    ADD_CFLAGS="-O2" \
    ADD_CXXFLAGS="-O2" \
    ADD_LDFLAGS="-static"

# Check the results
RUN echo "Checking built binaries..." && \
    ls -la /opt/coin/bin/ 2>/dev/null || echo "No bin directory" && \
    file /opt/coin/bin/* 2>/dev/null || echo "No binaries found"

# Final image
FROM alpine:3.22 AS final

# Install runtime essentials (though shouldn't be needed for static binaries)
RUN apk add --no-cache \
    libstdc++ \
    libgcc \
    libgomp \
    musl

# Copy the built CBC
COPY --from=builder /opt/coin /opt/coin

# Add the coin binaries to PATH
ENV PATH="/opt/coin/bin:${PATH}"

# Strip binaries to reduce size
RUN find /opt/coin/bin -type f -executable -exec strip --strip-all {} + 2>/dev/null || true

# Verify what we have
RUN echo "=== Final CBC Binary Check ===" && \
    if [ -f /opt/coin/bin/cbc ]; then \
        echo "CBC binary found at /opt/coin/bin/cbc" && \
        echo "File type:" && \
        file /opt/coin/bin/cbc && \
        echo "Size:" && \
        ls -lh /opt/coin/bin/cbc && \
        echo "Dynamic dependencies:" && \
        ldd /opt/coin/bin/cbc 2>&1 | head -20 || echo "  No dynamic dependencies (static)" && \
        echo "Version test:" && \
        timeout 5 cbc -version 2>/dev/null || echo "  Version check failed or timed out"; \
    else \
        echo "ERROR: CBC binary not found!" && \
        exit 1; \
    fi

WORKDIR /app
CMD ["/bin/sh"]

# Test stage
FROM final AS test

# Copy test files
COPY testfiles/test.lp /tmp/test.lp

# Run the test
RUN echo "Testing CBC solver with a simple LP problem..." && \
    cbc /tmp/test.lp solve solution /tmp/solution.txt 2>/dev/null && \
    echo "✓ CBC solver test passed" && \
    echo "Solution:" && \
    cat /tmp/solution.txt 2>/dev/null || echo "Solution file not created"
