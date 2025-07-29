FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY . .

# Make scripts executable
RUN chmod +x *.py

# Expose port
EXPOSE 8082

# Run the masking proxy
CMD ["python", "kong-masking-proxy.py"]