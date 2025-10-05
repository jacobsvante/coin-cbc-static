# Build stage - Using Debian for building static COIN-CBC
FROM debian:bookworm-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    git \
    pkg-config \
    libbz2-dev \
    zlib1g-dev \
    liblapack-dev \
    libblas-dev \
    gfortran \
    ca-certificates \
    subversion \
    file \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Download coinbrew build script
RUN wget https://raw.githubusercontent.com/coin-or/coinbrew/master/coinbrew \
    && chmod +x coinbrew

# Fetch and build CBC with all dependencies statically
ARG CBC_VERSION=2.10.12
RUN ./coinbrew fetch Cbc@${CBC_VERSION} --no-prompt \
    && ./coinbrew build Cbc \
        --prefix=/usr/local \
        --enable-static \
        --disable-shared \
        --tests none \
        --verbosity 2 \
        ADD_CFLAGS="-O3 -fPIC" \
        ADD_CXXFLAGS="-O3 -fPIC" \
        --no-prompt \
    && ./coinbrew install Cbc --no-prompt

# Create a directory for the static library and headers
RUN mkdir -p /opt/coin/lib /opt/coin/include \
    && cp /usr/local/lib/libCbc.a /opt/coin/lib/ \
    && cp /usr/local/lib/libCbcSolver.a /opt/coin/lib/ \
    && cp /usr/local/lib/libClp.a /opt/coin/lib/ \
    && cp /usr/local/lib/libCoinUtils.a /opt/coin/lib/ \
    && cp /usr/local/lib/libOsi.a /opt/coin/lib/ \
    && cp /usr/local/lib/libOsiClp.a /opt/coin/lib/ \
    && cp /usr/local/lib/libCgl.a /opt/coin/lib/ \
    && cp -r /usr/local/include/coin /opt/coin/include/

# Verify libraries are static (not dynamic)
RUN for lib in /opt/coin/lib/*.a; do \
        if file "$lib" | grep -q "ar archive"; then \
            echo "✓ $lib is static" ; \
        else \
            echo "✗ $lib is NOT static!" && exit 1; \
        fi \
    done

# Create build info
RUN echo "COIN-CBC Static Build Information" > /opt/coin/build_info.txt \
    && echo "=================================" >> /opt/coin/build_info.txt \
    && echo "CBC Version: ${CBC_VERSION}" >> /opt/coin/build_info.txt \
    && echo "Build Date: $(date)" >> /opt/coin/build_info.txt \
    && echo "Compiler: $(gcc --version | head -1)" >> /opt/coin/build_info.txt \
    && echo "Architecture: $(uname -m)" >> /opt/coin/build_info.txt \
    && echo "" >> /opt/coin/build_info.txt \
    && echo "Libraries:" >> /opt/coin/build_info.txt \
    && ls -lh /opt/coin/lib/*.a >> /opt/coin/build_info.txt \
    && echo "" >> /opt/coin/build_info.txt \
    && echo "Static verification:" >> /opt/coin/build_info.txt \
    && for lib in /opt/coin/lib/*.a; do file "$lib" >> /opt/coin/build_info.txt; done \
    && echo "" >> /opt/coin/build_info.txt \
    && echo "Headers:" >> /opt/coin/build_info.txt \
    && find /opt/coin/include -type f -name "*.h" -o -name "*.hpp" >> /opt/coin/build_info.txt

# Final stage - minimal image with just the libraries and headers
FROM debian:bookworm-slim AS final

# Copy static libraries and headers from builder
COPY --from=builder /opt/coin /opt/coin

WORKDIR /opt/coin

# Default command to show build info
CMD ["cat", "/opt/coin/build_info.txt"]
