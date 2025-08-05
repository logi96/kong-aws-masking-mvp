# Performance Benchmark Report

**Date**: 2025-07-30 17:05:17
**Test Type**: System Performance and Reliability Analysis
**Environment**: Production-like Configuration
**Target**: < 5 seconds response time, 1000 RPS capability

## Executive Summary

This report analyzes the performance characteristics and reliability of the Kong AWS Masking MVP system.


## Container Health Status

- **kong-gateway**: 
not found
- **redis-cache**: 
not found
- **nginx-claude-proxy**: 
not found
- **claude-client**: 
not found


## Response Time Analysis


### Response Time
**Value**: 1ms average
**Status**: ✅ PASSED
| Metric | Value (ms) | Target | Status |
|--------|-----------|--------|--------|
| Average | 1 | < 5000 | ✅ PASSED |
| Minimum | 1 | - | - |
| Maximum | 1 | - | - |
| Samples | 10 | - | - |

**Response Times Distribution**:
```
1 1 1 1 1 1 1 1 1 1
```


## Resource Usage Analysis

| Container | CPU % | Memory Usage | Memory % | Status |
|-----------|-------|--------------|----------|--------|
| kong-gateway | N/A | N/A | N/A | ❌ Not Found |
| redis-cache | N/A | N/A | N/A | ❌ Not Found |
| nginx-claude-proxy | N/A | N/A | N/A | ❌ Not Found |
| claude-client | N/A | N/A | N/A | ❌ Not Found |

## Load Testing Analysis

