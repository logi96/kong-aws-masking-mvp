#!/bin/bash

# Nginx-Kong-Claude Enterprise Stop Script

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🛑 Stopping Nginx-Kong-Claude Enterprise...${NC}"
echo ""

# Stop all services
echo -e "${YELLOW}📦 Stopping all containers...${NC}"
docker-compose down

echo ""
echo -e "${GREEN}✅ All services stopped${NC}"

# Option to clean data
if [ "$1" == "--clean" ]; then
    echo ""
    echo -e "${YELLOW}🧹 Cleaning data directories...${NC}"
    
    # Remove logs
    rm -rf logs/nginx/*
    rm -rf logs/kong/*
    rm -rf logs/redis/*
    rm -rf logs/claude-client/*
    
    # Remove Redis data
    rm -rf redis/data/*
    
    echo -e "${GREEN}✅ Data cleaned${NC}"
fi

# Option to remove volumes
if [ "$1" == "--volumes" ]; then
    echo ""
    echo -e "${YELLOW}🗑️  Removing Docker volumes...${NC}"
    docker-compose down -v
    echo -e "${GREEN}✅ Volumes removed${NC}"
fi

echo ""
echo -e "${BLUE}💡 Usage:${NC}"
echo "  ./stop.sh          - Stop containers only"
echo "  ./stop.sh --clean  - Stop and clean data"
echo "  ./stop.sh --volumes - Stop and remove volumes"
echo ""