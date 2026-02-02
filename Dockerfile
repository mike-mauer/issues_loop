# GitHub Issue Loop Workflow - Development Container
# Provides a consistent environment for the Ralph Pattern workflow
#
# Build: docker build -t issueloop .
# Run:   docker run -it -v $(pwd):/workspace issueloop

FROM ubuntu:22.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies
RUN apt-get update && apt-get install -y \
    git \
    jq \
    curl \
    ca-certificates \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Set up working directory
WORKDIR /workspace

# Create non-root user for better security
RUN useradd -m -s /bin/bash developer
USER developer

# Set git config defaults (user should override with their own)
RUN git config --global init.defaultBranch main \
    && git config --global user.name "Developer" \
    && git config --global user.email "developer@example.com"

# Verify installations
RUN echo "Verifying installations:" \
    && git --version \
    && gh --version \
    && jq --version \
    && echo "All dependencies installed successfully!"

# Default command
CMD ["/bin/bash"]
