#!/usr/bin/env python3
"""
Kong Masking Proxy for Claude Code
Intercepts Claude Code requests, masks AWS resources, and forwards to Kong Gateway
"""

from fastapi import FastAPI, Request, Response, HTTPException
from fastapi.responses import StreamingResponse
import uvicorn
import httpx
import json
import logging
import re
from typing import Dict, Any, AsyncGenerator
import os
from datetime import datetime

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI()

# Kong Gateway URL (can be HTTP since it's internal)
KONG_URL = os.environ.get("KONG_URL", "http://kong:8000")
KONG_ROUTE = os.environ.get("KONG_ROUTE", "/claude-proxy/v1/messages")

# AWS Resource Patterns (same as Kong plugin)
AWS_PATTERNS = {
    'ec2_instance': r'\bi-[0-9a-f]{8,17}\b',
    's3_bucket': r'\b[a-z0-9][a-z0-9\-\.]{2,62}(?:-bucket|bucket-)\b',
    'private_ip': r'\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b',
    'rds_instance': r'\b[a-z][a-z0-9\-]{0,62}\.rds\.amazonaws\.com\b',
    'account_id': r'\b\d{12}\b',
    'access_key': r'\bAKIA[A-Z0-9]{16}\b',
    'arn': r'\barn:aws:[a-z0-9\-]+:[a-z0-9\-]*:\d{12}:[a-z0-9\-\/\:\_]+\b'
}

# Masking map to store original values
masking_map = {}
mask_counter = {'ec2': 0, 's3': 0, 'ip': 0, 'rds': 0, 'account': 0, 'key': 0, 'arn': 0}

def mask_aws_resources(text: str) -> str:
    """Mask AWS resources in text"""
    if not isinstance(text, str):
        return text
    
    masked_text = text
    
    # EC2 Instances
    for match in re.finditer(AWS_PATTERNS['ec2_instance'], text):
        original = match.group()
        mask_counter['ec2'] += 1
        masked = f"EC2_INSTANCE_{mask_counter['ec2']:03d}"
        masking_map[masked] = original
        masked_text = masked_text.replace(original, masked)
    
    # S3 Buckets
    for match in re.finditer(AWS_PATTERNS['s3_bucket'], text):
        original = match.group()
        mask_counter['s3'] += 1
        masked = f"S3_BUCKET_{mask_counter['s3']:03d}"
        masking_map[masked] = original
        masked_text = masked_text.replace(original, masked)
    
    # Private IPs
    for match in re.finditer(AWS_PATTERNS['private_ip'], text):
        original = match.group()
        mask_counter['ip'] += 1
        masked = f"PRIVATE_IP_{mask_counter['ip']:03d}"
        masking_map[masked] = original
        masked_text = masked_text.replace(original, masked)
    
    # RDS Instances
    for match in re.finditer(AWS_PATTERNS['rds_instance'], text):
        original = match.group()
        mask_counter['rds'] += 1
        masked = f"RDS_INSTANCE_{mask_counter['rds']:03d}"
        masking_map[masked] = original
        masked_text = masked_text.replace(original, masked)
    
    # AWS Account IDs
    for match in re.finditer(AWS_PATTERNS['account_id'], text):
        original = match.group()
        mask_counter['account'] += 1
        masked = f"AWS_ACCOUNT_{mask_counter['account']:03d}"
        masking_map[masked] = original
        masked_text = masked_text.replace(original, masked)
    
    # Access Keys
    for match in re.finditer(AWS_PATTERNS['access_key'], text):
        original = match.group()
        mask_counter['key'] += 1
        masked = f"ACCESS_KEY_{mask_counter['key']:03d}"
        masking_map[masked] = original
        masked_text = masked_text.replace(original, masked)
    
    # ARNs
    for match in re.finditer(AWS_PATTERNS['arn'], text):
        original = match.group()
        mask_counter['arn'] += 1
        masked = f"AWS_ARN_{mask_counter['arn']:03d}"
        masking_map[masked] = original
        masked_text = masked_text.replace(original, masked)
    
    if masked_text != text:
        logger.info(f"🎭 Masked {len(masking_map)} AWS resources")
    
    return masked_text

def mask_request_body(body: Dict[str, Any]) -> Dict[str, Any]:
    """Recursively mask AWS resources in request body"""
    if isinstance(body, dict):
        masked_body = {}
        for key, value in body.items():
            if isinstance(value, str):
                masked_body[key] = mask_aws_resources(value)
            elif isinstance(value, (dict, list)):
                masked_body[key] = mask_request_body(value)
            else:
                masked_body[key] = value
        return masked_body
    elif isinstance(body, list):
        return [mask_request_body(item) for item in body]
    elif isinstance(body, str):
        return mask_aws_resources(body)
    else:
        return body

@app.post("/v1/messages")
async def proxy_messages(request: Request):
    """Proxy /v1/messages endpoint with masking"""
    
    # Get request body
    body = await request.body()
    try:
        body_json = json.loads(body)
        logger.info(f"📨 Received request from Claude Code")
        
        # Mask AWS resources in the request
        masked_body = mask_request_body(body_json)
        
        # Forward to Kong
        kong_url = f"{KONG_URL}{KONG_ROUTE}"
        logger.info(f"🚀 Forwarding to Kong: {kong_url}")
        
        # Prepare headers (forward most headers, update some)
        headers = dict(request.headers)
        headers['host'] = 'api.anthropic.com'  # Set correct host header
        headers.pop('content-length', None)  # Let httpx calculate
        
        # Check if streaming is requested
        stream = body_json.get('stream', False)
        
        async with httpx.AsyncClient(timeout=60.0) as client:
            if stream:
                # Handle streaming response
                logger.info("📡 Streaming response requested")
                response = await client.post(
                    kong_url,
                    json=masked_body,
                    headers=headers,
                    timeout=60.0
                )
                
                # Stream the response back
                async def generate():
                    async for chunk in response.aiter_bytes():
                        yield chunk
                
                return StreamingResponse(
                    generate(),
                    media_type=response.headers.get('content-type', 'text/event-stream'),
                    status_code=response.status_code,
                    headers=dict(response.headers)
                )
            else:
                # Handle regular response
                response = await client.post(
                    kong_url,
                    json=masked_body,
                    headers=headers
                )
                
                # Note: Response unmasking would be handled by Kong
                # This proxy only masks the request
                
                return Response(
                    content=response.content,
                    status_code=response.status_code,
                    headers=dict(response.headers),
                    media_type=response.headers.get('content-type', 'application/json')
                )
                
    except json.JSONDecodeError:
        logger.error("Failed to parse request body as JSON")
        raise HTTPException(status_code=400, detail="Invalid JSON in request body")
    except Exception as e:
        logger.error(f"Error proxying request: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "kong-masking-proxy",
        "timestamp": datetime.now().isoformat(),
        "masking_stats": {
            "total_masked": len(masking_map),
            "by_type": dict(mask_counter)
        }
    }

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD", "PATCH"])
async def catch_all(request: Request, path: str):
    """Catch all other requests for debugging"""
    logger.warning(f"⚠️  Unhandled request: {request.method} /{path}")
    logger.warning(f"   Headers: {dict(request.headers)}")
    
    # For now, return 404
    raise HTTPException(
        status_code=404, 
        detail=f"Path /{path} not found. This proxy only handles /v1/messages"
    )

if __name__ == "__main__":
    print("🚀 Starting Kong Masking Proxy")
    print(f"📍 Listening on: http://localhost:8082")
    print(f"🔗 Forwarding to: {KONG_URL}{KONG_ROUTE}")
    print("-" * 60)
    print("🧪 Test with: ANTHROPIC_BASE_URL=http://localhost:8082 claude")
    print("-" * 60)
    
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8082,
        log_level="info"
    )