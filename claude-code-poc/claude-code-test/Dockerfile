FROM node:20-alpine

# Install required packages
RUN apk add --no-cache \
    bash \
    curl \
    python3 \
    py3-pip \
    git

# Create test user
RUN adduser -D testuser

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Create workspace
WORKDIR /workspace
RUN mkdir -p /workspace/test-files

# Create test files with AWS resources
RUN echo "EC2 instance i-1234567890abcdef0 is running" > /workspace/test-files/ec2.txt
RUN echo "S3 bucket my-sensitive-data-bucket contains logs" > /workspace/test-files/s3.txt
RUN echo "RDS instance prod-database.rds.amazonaws.com is accessible" > /workspace/test-files/rds.txt
RUN echo "Private IP 10.0.1.50 is assigned to the instance" > /workspace/test-files/network.txt
RUN echo "AWS Account ID 123456789012 owns these resources" > /workspace/test-files/account.txt

# Create test script
COPY test-claude-code.sh /workspace/
RUN chmod +x /workspace/test-claude-code.sh

# Switch to test user
USER testuser

# Set working directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]