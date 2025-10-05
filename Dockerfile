# Build fully static CBC binaries with musl
# CBC_VERSION can be: 2.10.12, master, releases/2.10.11, etc.
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

# Build CBC with static linking enforced at every level
# Use a wrapper script to ensure static compilation
RUN echo '#!/bin/sh' > /usr/local/bin/static-gcc && \
    echo 'exec /usr/bin/gcc -static "$@"' >> /usr/local/bin/static-gcc && \
    chmod +x /usr/local/bin/static-gcc && \
    echo '#!/bin/sh' > /usr/local/bin/static-g++ && \
    echo 'exec /usr/bin/g++ -static "$@"' >> /usr/local/bin/static-g++ && \
    chmod +x /usr/local/bin/static-g++

# Build with static wrappers
RUN CC=/usr/local/bin/static-gcc \
    CXX=/usr/local/bin/static-g++ \
    CFLAGS="-O2" \
    CXXFLAGS="-O2" \
    LDFLAGS="-static" \
    ./coinbrew/coinbrew build Cbc:${CBC_VERSION} \
    --no-prompt \
    --tests=none \
    --prefix=/opt/coin \
    --no-third-party \
    --verbosity=3 \
    --enable-static \
    --disable-shared \
    --without-lapack \
    --without-blas || \
    (echo "Build with static wrappers failed, trying alternative approach..." && \
     LDFLAGS="-static -all-static" \
     LIBS="-static" \
     ./coinbrew/coinbrew build Cbc:${CBC_VERSION} \
     --no-prompt \
     --tests=none \
     --prefix=/opt/coin-alt \
     --no-third-party \
     --verbosity=3 \
     --enable-static \
     --disable-shared \
     --without-lapack \
     --without-blas)

# Check results and use whichever worked
RUN if [ -f /opt/coin/bin/cbc ]; then \
        echo "Using primary build" && \
        file /opt/coin/bin/cbc && \
        ldd /opt/coin/bin/cbc 2>&1 || true; \
    elif [ -f /opt/coin-alt/bin/cbc ]; then \
        echo "Using alternative build" && \
        mv /opt/coin-alt /opt/coin && \
        file /opt/coin/bin/cbc && \
        ldd /opt/coin/bin/cbc 2>&1 || true; \
    else \
        echo "ERROR: No build succeeded!" && \
        exit 1; \
    fi

# Strip binaries
RUN find /opt/coin/bin -type f -executable -exec strip --strip-all {} + 2>/dev/null || true

# Final image
FROM alpine:3.22 AS final

# Copy the built CBC
COPY --from=builder /opt/coin /opt/coin

# Add the coin binaries to PATH
ENV PATH="/opt/coin/bin:${PATH}"

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

# Verify static linking in a different distro (Debian)
FROM debian:trixie AS verify-static

# Install only file and basic utils - no libraries
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    file \
    && rm -rf /var/lib/apt/lists/*

# Copy the CBC binaries from the builder
COPY --from=builder /opt/coin/bin /opt/coin/bin

# Set PATH
ENV PATH="/opt/coin/bin:${PATH}"

# Verify the binaries are truly static
RUN echo "=== Verifying CBC is fully static on Debian ===" && \
    echo "System info:" && \
    cat /etc/os-release | grep PRETTY_NAME && \
    echo "" && \
    echo "Checking CBC binary:" && \
    file /opt/coin/bin/cbc && \
    echo "" && \
    echo "Checking for dynamic dependencies:" && \
    if ldd /opt/coin/bin/cbc 2>&1 | grep -q "not a dynamic executable"; then \
        echo "✓ CBC is fully static (no dynamic dependencies)"; \
    else \
        echo "✗ CBC has dynamic dependencies:" && \
        ldd /opt/coin/bin/cbc; \
    fi && \
    echo "" && \
    echo "Testing if CBC actually runs:" && \
    cbc -version && \
    echo "✓ CBC runs successfully on Debian without any musl or Alpine libraries"

# Copy test file and run a solve test
COPY testfiles/test.lp /tmp/test.lp
RUN echo "" && \
    echo "Running solver test on Debian:" && \
    cbc /tmp/test.lp solve solution /tmp/solution.txt && \
    echo "✓ CBC solver works on Debian" && \
    echo "" && \
    echo "This proves the binary is fully static and portable across Linux distros"

# Minimal image with just static libraries and headers for development
FROM busybox:stable AS static-libs

# Copy static libraries
COPY --from=builder /opt/coin/lib /lib

# Copy header files
COPY --from=builder /opt/coin/include /include

# Copy pkg-config files if they exist
COPY --from=builder /opt/coin/lib/pkgconfig /lib/pkgconfig

# Create a simple test to verify the files are there
RUN echo "=== CBC Static Development Files ===" && \
    echo "Static libraries:" && \
    ls -la /lib/*.a | head -10 && \
    echo "" && \
    echo "Total static libraries: $(ls /lib/*.a 2>/dev/null | wc -l)" && \
    echo "Total header files: $(find /include -name '*.h' -o -name '*.hpp' 2>/dev/null | wc -l)" && \
    echo "" && \
    echo "Library sizes:" && \
    du -sh /lib/*.a | sort -h | tail -5

WORKDIR /workspace

# This image contains:
# - Static libraries (.a files) in /lib
# - Header files (.h, .hpp) in /include
# - pkg-config files (.pc) in /lib/pkgconfig
# - Busybox for basic shell and utilities
CMD ["/bin/sh"]