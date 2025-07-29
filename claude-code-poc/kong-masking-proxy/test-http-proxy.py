#!/usr/bin/env python3
"""
Test proxy to verify if Claude Code accepts HTTP BASE_URL
This will help us understand the HTTPS issue
"""

from fastapi import FastAPI, Request, Response
import uvicorn
import httpx
import json
import logging
from datetime import datetime

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI()

# Test if we receive any requests
@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD", "PATCH", "TRACE"])
async def catch_all(request: Request, path: str):
    """Catch all requests to see what Claude Code sends"""
    
    # Log request details
    logger.info(f"🔍 Received request:")
    logger.info(f"  Method: {request.method}")
    logger.info(f"  Path: /{path}")
    logger.info(f"  Headers: {dict(request.headers)}")
    
    # Get body if present
    body = None
    if request.method in ["POST", "PUT", "PATCH"]:
        body_bytes = await request.body()
        if body_bytes:
            try:
                body = json.loads(body_bytes)
                logger.info(f"  Body: {json.dumps(body, indent=2)}")
            except:
                logger.info(f"  Body (raw): {body_bytes[:200]}...")
    
    # Check if this is from Claude Code
    user_agent = request.headers.get("user-agent", "")
    logger.info(f"  User-Agent: {user_agent}")
    
    # For now, return a simple response
    return {
        "message": "Test proxy received your request",
        "path": path,
        "method": request.method,
        "timestamp": datetime.now().isoformat(),
        "note": "This is a test proxy to verify HTTP connectivity"
    }

if __name__ == "__main__":
    print("🚀 Starting HTTP test proxy on http://localhost:8082")
    print("📋 Test with: ANTHROPIC_BASE_URL=http://localhost:8082 claude")
    print("-" * 60)
    
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8082,
        log_level="warning"  # Reduce uvicorn noise
    )