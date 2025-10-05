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
    python3 \
    # Ensure we have static libraries
    libstdc++ \
    libgcc

WORKDIR /opt

# Set environment variables to force static linking
ENV LDFLAGS="-static -static-libgcc -static-libstdc++" \
    CXXFLAGS="-O2" \
    CFLAGS="-O2" \
    CC="gcc" \
    CXX="g++"

# Clone and fetch
RUN git clone --depth 1 https://github.com/coin-or/coinbrew.git
RUN ./coinbrew/coinbrew fetch Cbc:${CBC_VERSION} --no-prompt

# Build CBC and all dependencies using coinbrew with true static linking
# We need to ensure libstdc++ and libgcc are also statically linked
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
    LDFLAGS="-static -static-libgcc -static-libstdc++" \
    ADD_CFLAGS="-O2" \
    ADD_CXXFLAGS="-O2" \
    ADD_LDFLAGS="-static -static-libgcc -static-libstdc++" \
    LIBS="-static"

# Alternative: If the above doesn't work, manually relink the binaries
RUN if ldd /opt/coin/bin/cbc 2>/dev/null | grep -q "=>"; then \
        echo "CBC not fully static, attempting to relink..." && \
        cd /opt/coin/bin && \
        for binary in cbc clp; do \
            if [ -f "$binary" ]; then \
                echo "Relinking $binary as fully static..." && \
                g++ -static -static-libgcc -static-libstdc++ \
                    -o "${binary}.static" \
                    -L/opt/coin/lib \
                    -Wl,--whole-archive \
                    /opt/coin/lib/libCbc.a \
                    /opt/coin/lib/libCbcSolver.a \
                    /opt/coin/lib/libClp.a \
                    /opt/coin/lib/libOsiClp.a \
                    /opt/coin/lib/libOsi.a \
                    /opt/coin/lib/libCoinUtils.a \
                    /opt/coin/lib/libCgl.a \
                    -Wl,--no-whole-archive \
                    -lm -lpthread \
                    2>/dev/null && \
                mv "${binary}.static" "$binary" || \
                echo "Manual relinking failed for $binary"; \
            fi \
        done \
    fi

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
        echo "✓ CBC is fully static (no dynamic dependencies)" \
    else \
        echo "✗ CBC has dynamic dependencies:" && \
        ldd /opt/coin/bin/cbc \
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