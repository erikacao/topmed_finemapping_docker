# ============================================================
# Stage 1: Build HTSlib
# ============================================================

FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:slim AS builder

RUN apt-get update && apt-get install -y \
    build-essential \
    libbz2-dev \
    libcurl4-openssl-dev \
    libdeflate-dev \
    liblzma-dev \
    libssl-dev \
    zlib1g-dev \
    wget \
    && rm -rf /var/lib/apt/lists/*

ENV HTSLIB_VERSION=1.22

RUN wget -q \
    https://github.com/samtools/htslib/releases/download/${HTSLIB_VERSION}/htslib-${HTSLIB_VERSION}.tar.bz2 \
    -O /tmp/htslib.tar.bz2 && \
    mkdir /tmp/htslib && \
    tar xjf /tmp/htslib.tar.bz2 -C /tmp/htslib --strip-components=1 && \
    cd /tmp/htslib && \
    ./configure \
        --prefix=/usr \
        --enable-libcurl \
        --enable-gcs \
        --with-libdeflate && \
    make -j2 && \
    make install


# ============================================================
# Stage 2: Runtime
# ============================================================

FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:slim

WORKDIR /app

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# System dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libbz2-1.0 \
    libcurl4-openssl-dev \
    libdeflate0 \
    libgsl-dev \
    liblapack3 \
    liblzma5 \
    libopenblas-dev \
    libsqlite3-dev \
    libssl-dev \
    parallel \
    pigz \
    python3-pip \
    r-base-core \
    wget \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*


# ============================================================
# Python dependencies
# ============================================================

RUN pip3 install --break-system-packages \
    "bgzip>=0.5.0" \
    gcsfs \
    numpy \
    pandas


# ============================================================
# R dependencies
# ============================================================

RUN echo "options(repos = 'https://cloud.r-project.org')" \
    > $(Rscript -e "cat(Sys.getenv('R_HOME'))")/etc/Rprofile.site

RUN Rscript -e "install.packages(c('remotes', 'Rcpp', 'RcppArmadillo'))"


# ============================================================
# Pin older Rcpp and RcppArmadillo
#
# Compatibility candidates:
# Rcpp 1.0.14
# RcppArmadillo 0.12.8.4.0
#
# These avoid newer Armadillo's C++14 requirement.
# ============================================================
RUN Rscript -e " \
    remotes::install_version( \
        'Rcpp', \
        version='1.0.14', \
        repos='https://cloud.r-project.org', \
        upgrade='never' \
    ); \
    remotes::install_version( \
        'RcppArmadillo', \
        version='0.12.8.4.0', \
        repos='https://cloud.r-project.org', \
        upgrade='never' \
    ); \
    stopifnot( \
        as.character(packageVersion('Rcpp')) == '1.0.14', \
        as.character(packageVersion('RcppArmadillo')) == '0.12.8.4.0' \
    ) \
"


# ============================================================
# Other required R packages
# ============================================================

RUN Rscript -e " \
    install.packages(c( \
        'argparse', \
        'data.table', \
        'dplyr', \
        'furrr', \
        'purrr', \
        'R.utils', \
        'tidyr' \
    )) \
"


# ============================================================
# Install SuSiE
# ============================================================

RUN Rscript -e " \
    remotes::install_github( \
        'stephenslab/susieR', \
        ref='v0.14.2', \
        dependencies=NA, \
        upgrade='never' \
    ); \
    stopifnot(requireNamespace('susieR', quietly=TRUE)) \
"


# ============================================================
# Install rbcor
# ============================================================
RUN Rscript -e " \
    cat('Rcpp:', as.character(packageVersion('Rcpp')), '\n'); \
    cat('RcppArmadillo:', as.character(packageVersion('RcppArmadillo')), '\n'); \
    cat('RcppArmadillo Rcpp requirement:', \
        packageDescription('RcppArmadillo')\$Imports, '\n') \
"


RUN Rscript -e " \
    stopifnot( \
        as.character(packageVersion('Rcpp')) == '1.0.14', \
        as.character(packageVersion('RcppArmadillo')) == '0.12.8.4.0' \
    ); \
    cat('Rcpp versions verified\n') \
"



RUN Rscript -e " \
    remotes::install_github( \
        'mkanai/rbcor', \
        ref='d2be97234f633def9dcfe304fc5430e3a8caf160', \
        dependencies=NA, \
        upgrade='never' \
    ); \
    stopifnot(requireNamespace('rbcor', quietly=TRUE)) \
"


# ============================================================
# Install ldcov
# ============================================================

RUN pip3 install --break-system-packages \
    git+https://github.com/mkanai/ldcov@v0.5.0


# ============================================================
# Copy HTSlib tools
# ============================================================

COPY --from=builder /usr/bin/bgzip /usr/bin/bgzip
COPY --from=builder /usr/bin/tabix /usr/bin/tabix
COPY --from=builder /usr/lib/libhts.so* /usr/lib/

RUN ldconfig


# ============================================================
# Verify installation
# ============================================================

RUN Rscript -e " \
    library(susieR); \
    library(rbcor); \
    cat('susieR:', as.character(packageVersion('susieR')), '\n'); \
    cat('rbcor:', as.character(packageVersion('rbcor')), '\n'); \
    cat('Rcpp:', as.character(packageVersion('Rcpp')), '\n'); \
    cat('RcppArmadillo:', as.character(packageVersion('RcppArmadillo')), '\n') \
" && \
    ldcov --help > /dev/null && \
    bgzip --version && \
    tabix --version

CMD ["/bin/bash"]
