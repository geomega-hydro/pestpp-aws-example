# Stage 1: Build
FROM debian:bookworm-slim AS build

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies and clean up
RUN apt-get update && apt-get install -y --no-install-recommends\
    wget \
    tar \
    unzip \
    ca-certificates \
    tzdata \
    htop \
    nano \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Set the timezone
ENV TZ=America/Denver
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Assign the working directory
WORKDIR /build

# Download and extract MODFLOW 6 and PEST++ and move to /usr/local/bin 
RUN wget https://github.com/MODFLOW-USGS/executables/releases/download/22.0/linux.zip -O modflow6.zip \
    && unzip modflow6.zip -d modflow6 \
    && wget https://github.com/usgs/pestpp/releases/download/5.2.22/pestpp-5.2.22-linux.tar.gz -O pestpp.tar.gz \
    && tar -xzf pestpp.tar.gz \
    && mv modflow6/* bin/* /usr/local/bin/ \
    && rm -rf modflow6 modflow6.zip bin pestpp.tar.gz

# Stage 2: Runtime
FROM python:3.13-slim

# Copy timezone data from build stage
COPY --from=build /etc/localtime /etc/localtime
COPY --from=build /etc/timezone /etc/timezone

# Copy htop and nano from build stage
COPY --from=build /usr/bin/htop /usr/bin/htop
COPY --from=build /usr/bin/nano /usr/bin/nano
COPY --from=build /usr/share/nano /usr/share/nano

# Copy the installed binaries from the build stage
COPY --from=build /usr/local/bin/* /usr/local/bin/

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install python requriements and awscli
COPY requirements.txt ./
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt \
    && pip install awscli --no-cache-dir \
    && pip install boto3 --no-cache-dir

# Assign the working directory
ARG WORKSPACE_DIR=/pestpp
WORKDIR $WORKSPACE_DIR

# Create an empty directory called model
RUN mkdir -p $WORKSPACE_DIR/model

# Create geomega user and group with ID 1000 (default wsl user id for testing purposes)
RUN groupadd -g 1000 geomega && \
    useradd -m -u 1000 -g geomega -s /bin/bash geomega

# Copy the entry point script and cleanup non-required files
COPY entrypoint.py ./

RUN chmod +x entrypoint.py \
    && chown -R geomega:geomega $WORKSPACE_DIR \
    && rm -f ./requirements.txt

# Switch to non-root user
USER geomega

# Set the entry point
ENTRYPOINT ["python3", "./entrypoint.py"]