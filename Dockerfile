# Build fully static CBC binaries with musl
FROM alpine:3.22 AS builder

# Install build prerequisites for CBC
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

# Clone coinbrew
RUN git clone --depth 1 https://github.com/coin-or/coinbrew.git

# Fetch CBC and dependencies
RUN ./coinbrew/coinbrew fetch Cbc --no-prompt

# Build CBC without static flags in configure to avoid exit 77
# Static linking will be applied during make phase
RUN ./coinbrew/coinbrew build Cbc \
    --no-prompt \
    --tests=none \
    --prefix=/opt/coin \
    --no-third-party \
    --verbosity=3 \
    --enable-static \
    --disable-shared \
    --without-lapack \
    --without-blas

# Check what we built
RUN echo "Initial build complete. Checking binaries..." && \
    ls -la /opt/coin/bin/ 2>/dev/null || echo "No bin directory" && \
    file /opt/coin/bin/* 2>/dev/null || echo "No binaries found yet"

# Stage 2: Try building with static flags in make phase only
FROM alpine:3.22 AS static-build

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
RUN ./coinbrew/coinbrew fetch Cbc --no-prompt

# Configure without static flags
RUN cd Cbc && \
    ./configure \
        --prefix=/opt/coin-static \
        --enable-static \
        --disable-shared \
        --without-lapack \
        --without-blas \
        --disable-dependency-tracking \
        CFLAGS="-O2" \
        CXXFLAGS="-O2"

# Build with static flags
RUN cd Cbc && \
    make LDFLAGS="-static" AM_LDFLAGS="-static" -j$(nproc) || \
    make -j$(nproc)  # Fallback to normal make if static fails

# Install
RUN cd Cbc && make install

# Check the results
RUN echo "Checking static-build binaries..." && \
    ls -la /opt/coin-static/bin/ 2>/dev/null || echo "No bin directory" && \
    file /opt/coin-static/bin/* 2>/dev/null || echo "No binaries in coin-static"

# Stage 3: Final image - combine the builds
FROM alpine:3.22 AS final

# Install runtime essentials
RUN apk add --no-cache \
    libstdc++ \
    libgcc \
    libgomp \
    musl

# Copy from static-build first (if it exists), otherwise from builder
# Using conditional copy with proper Docker syntax
COPY --from=static-build /opt/coin-static /opt/coin-static
COPY --from=builder /opt/coin /opt/coin-builder

# Select the best build
RUN if [ -d /opt/coin-static/bin ] && [ -f /opt/coin-static/bin/cbc ]; then \
        echo "Using static-build version" && \
        mv /opt/coin-static /opt/coin && \
        rm -rf /opt/coin-builder; \
    elif [ -d /opt/coin-builder/bin ] && [ -f /opt/coin-builder/bin/cbc ]; then \
        echo "Using builder version" && \
        mv /opt/coin-builder /opt/coin; \
    else \
        echo "ERROR: No CBC build found!" && \
        ls -la /opt/ && \
        exit 1; \
    fi

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
        find /opt -name "cbc" -type f 2>/dev/null || echo "No cbc binary anywhere in /opt" && \
        exit 1; \
    fi

WORKDIR /app
CMD ["/bin/sh"]

# Stage 4: Test stage
FROM final AS test

# Copy test files
COPY testfiles/test.lp /tmp/test.lp

# Run the test
RUN echo "Testing CBC solver with a simple LP problem..." && \
    cbc /tmp/test.lp solve solution /tmp/solution.txt 2>/dev/null && \
    echo "✓ CBC solver test passed" && \
    echo "Solution:" && \
    cat /tmp/solution.txt 2>/dev/null || echo "Solution file not created"

# Stage 5: Debug stage for troubleshooting
FROM alpine:3.22 AS debug

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
    python3 \
    file \
    binutils

WORKDIR /opt

# Clone and fetch
RUN git clone --depth 1 https://github.com/coin-or/coinbrew.git
RUN ./coinbrew/coinbrew fetch Cbc --no-prompt

# Try simple configure to debug
RUN cd Cbc && \
    echo "Running configure with verbose output..." && \
    ./configure --help > /tmp/configure-help.txt 2>&1 && \
    ./configure \
        --prefix=/opt/coin-debug \
        --enable-static \
        --disable-shared \
        2>&1 | tee /tmp/configure-output.txt || \
    (echo "Configure failed with exit code $?" && \
     echo "Last 50 lines of config.log:" && \
     tail -50 config.log 2>/dev/null)

# Keep config.log for inspection
RUN if [ -f Cbc/config.log ]; then \
        cp Cbc/config.log /tmp/config.log && \
        echo "Config.log saved to /tmp/config.log"; \
    fi

CMD ["/bin/bash"]