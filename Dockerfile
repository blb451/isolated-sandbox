FROM ubuntu:22.04

# Install ClamAV and essential tools
RUN apt-get update && apt-get install -y \
    clamav \
    clamav-daemon \
    clamav-freshclam \
    curl \
    wget \
    git \
    unzip \
    build-essential \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (multiple versions via n)
RUN curl -L https://raw.githubusercontent.com/tj/n/master/bin/n -o /usr/local/bin/n \
    && chmod +x /usr/local/bin/n \
    && n lts \
    && n 18 \
    && n 20

# Install Ruby via rbenv
RUN git clone https://github.com/rbenv/rbenv.git /root/.rbenv \
    && git clone https://github.com/rbenv/ruby-build.git /root/.rbenv/plugins/ruby-build \
    && echo 'export PATH="/root/.rbenv/bin:$PATH"' >> /root/.bashrc \
    && echo 'eval "$(rbenv init -)"' >> /root/.bashrc \
    && /root/.rbenv/bin/rbenv install 3.2.2 \
    && /root/.rbenv/bin/rbenv global 3.2.2

# Install Python
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI (for Docker-in-Docker support)
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce-cli \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Update ClamAV database
RUN freshclam

# Create working directory
WORKDIR /sandbox

# Set PATH for Ruby
ENV PATH="/root/.rbenv/bin:/root/.rbenv/shims:${PATH}"

CMD ["/bin/bash"]