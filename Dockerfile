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
    -O /tmp/htslib.tar.bz2 \
    && mkdir /tmp/htslib \
    && tar xjf /tmp/htslib.tar.bz2 -C /tmp/htslib --strip-components=1 \
    && cd /tmp/htslib \
    && ./configure --prefix=/usr --enable-libcurl --enable-gcs --with-libdeflate \
    && make -j2 \
    && make install


FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:slim

LABEL description="TOPMed multi-ancestry single-cell eQTL fine-mapping"

WORKDIR /app

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

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
    r-base \
    wget \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

# Python dependencies
RUN pip3 install --break-system-packages \
    "bgzip>=0.5.0" \
    gcsfs \
    numpy \
    pandas

# R dependencies
RUN Rscript -e "options(repos='https://cloud.r-project.org'); \
    install.packages(c('argparse','data.table','dplyr', \
    'furrr','purrr','R.utils','tidyr','remotes'))"

# SuSiE version used by FinnGen
RUN Rscript -e "remotes::install_github( \
    'stephenslab/susieR', ref='v0.14.2', \
    dependencies=TRUE, upgrade='never')"

# BCOR support
RUN Rscript -e "remotes::install_github( \
    'mkanai/rbcor', \
    ref='d2be97234f633def9dcfe304fc5430e3a8caf160', \
    dependencies=TRUE, upgrade='never')"

# ldcov
RUN pip3 install --break-system-packages \
    git+https://github.com/mkanai/ldcov@v0.5.0

# test ldcov
RUN ldcov --help > /dev/null \
    && Rscript -e "library(susieR); library(rbcor); print(packageVersion('susieR'))" \
    && bgzip --version \
    && tabix --version \
    && command -v run_susieR.R

# FinnGen SuSiE wrapper
COPY R/run_susieR.R /usr/local/bin/run_susieR.R

RUN chmod +x /usr/local/bin/run_susieR.R

# HTSlib binaries
COPY --from=builder /usr/bin/bgzip /usr/bin/bgzip
COPY --from=builder /usr/bin/tabix /usr/bin/tabix

# Verify dependencies
RUN python3 -c "import ldcov; print('ldcov installed')" \
    && Rscript -e "library(susieR); library(rbcor); \
    print(packageVersion('susieR'))" \
    && command -v bgzip \
    && command -v tabix \
    && command -v run_susieR.R
