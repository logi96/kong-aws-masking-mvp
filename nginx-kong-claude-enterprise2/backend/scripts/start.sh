#!/bin/bash

# Backend startup script for nginx-kong-claude-enterprise2

set -e

echo "Starting nginx-kong-claude-enterprise2 backend service..."

# Check if .env file exists
if [ ! -f .env ]; then
    echo "Creating .env file from .env.example..."
    cp .env.example .env
    echo "Please update .env file with your actual configuration values"
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    npm install
fi

# Create logs directory
mkdir -p logs

# Check environment
echo "Environment: ${NODE_ENV:-development}"
echo "Port: ${PORT:-3000}"

# Start the service
if [ "$1" == "dev" ]; then
    echo "Starting in development mode with nodemon..."
    npm run dev
elif [ "$1" == "prod" ]; then
    echo "Starting in production mode..."
    npm run start:prod
else
    echo "Starting in default mode..."
    npm start
fi