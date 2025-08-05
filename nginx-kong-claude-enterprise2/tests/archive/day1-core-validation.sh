#!/bin/bash

#
# Day 1: 핵심 기능 완전 검증 - Kong AWS Masking MVP 빠른 배포 준비
# 
# 목표: 46개 AWS 패턴 검증, 프록시 체인 안정성, Redis 매핑 정확성 테스트
# 성공 기준: 최소 37개 패턴 (80%) 성공, 프록시 체인 100% 안정, Redis 95% 정확성
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_NAME="day1-core-validation"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_DIR="tests/test-report"
REPORT_FILE="$REPORT_DIR/${SCRIPT_NAME}-${TIMESTAMP}.md"

# Test endpoints
NGINX_ENDPOINT="http://localhost:8085"
KONG_DIRECT_ENDPOINT="http://localhost:8000"  # Note: Changed from 8010 to 8000 (Kong proxy port)
KONG_ADMIN_ENDPOINT="http://localhost:8001"
REDIS_HOST="localhost"
REDIS_PORT="6379"
REDIS_PASSWORD="CsJ9Thv39NOOzbVzx4bOwJCz75EyJsKlmB45HGQCrVMBj0nssGZGeOXvbnZAL"

# Statistics (compatible with bash 3.2)
PATTERN_RESULTS=""
PATTERN_DETAILS=""
TOTAL_PATTERNS=0
SUCCESSFUL_PATTERNS=0
FAILED_PATTERNS=0
PROXY_CHAIN_SUCCESS=false
REDIS_ACCURACY=0

# Create report directory
mkdir -p "$REPORT_DIR"

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$REPORT_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}" | tee -a "$REPORT_FILE"
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$REPORT_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}" | tee -a "$REPORT_FILE"
}

# Initialize report
init_report() {
    cat > "$REPORT_FILE" << EOF
# Day 1: 핵심 기능 완전 검증 리포트

**테스트 실행 시간**: $(date '+%Y-%m-%d %H:%M:%S')  
**목표**: Kong AWS Masking MVP 빠른 배포 준비  
**성공 기준**: 46개 패턴 중 37개 (80%) 성공, 프록시 체인 100% 안정성, Redis 95% 정확성

## 테스트 환경

- Kong Proxy: http://localhost:8000
- Kong Admin: http://localhost:8001  
- Nginx Proxy: http://localhost:8085
- Redis: localhost:6379
- API Key: sk-ant-api03-...

---

## 테스트 결과

EOF
}

# Test basic connectivity
test_connectivity() {
    log "=== 1. 기본 연결성 테스트 ==="
    
    # Test Kong Admin
    if curl -s "$KONG_ADMIN_ENDPOINT/status" > /dev/null; then
        log_success "Kong Admin API 연결 성공"
    else
        log_error "Kong Admin API 연결 실패"
        return 1
    fi
    
    # Test Redis
    if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" ping > /dev/null 2>&1; then
        log_success "Redis 연결 성공"
    else
        log_error "Redis 연결 실패"
        return 1
    fi
    
    # Test Nginx
    if curl -s "$NGINX_ENDPOINT/health" > /dev/null 2>&1; then
        log_success "Nginx 프록시 연결 성공"
    else
        log_warning "Nginx 연결 확인 필요"
    fi
    
    return 0
}

# Test individual AWS pattern
test_aws_pattern() {
    local pattern_name="$1"
    local sample_value="$2"
    local expected_mask="$3"
    
    TOTAL_PATTERNS=$((TOTAL_PATTERNS + 1))
    
    # Create test payload
    local test_payload=$(cat << EOF
{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 100,
    "messages": [
        {
            "role": "user", 
            "content": "Analyze this AWS resource: $sample_value"
        }
    ]
}
EOF
)
    
    # Test direct Kong access first
    local response=$(curl -s -X POST "$KONG_DIRECT_ENDPOINT/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: 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" \
        -d "$test_payload" \
        -w "\nHTTP_CODE:%{http_code}\n" 2>/dev/null || echo "CURL_ERROR")
    
    local http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d':' -f2)
    local body=$(echo "$response" | sed '/HTTP_CODE:/d')
    
    if [[ "$http_code" == "200" ]]; then
        # Check if masking occurred by looking for the pattern in logs
        local masked_found=$(docker logs claude-kong 2>&1 | tail -20 | grep -o "$expected_mask" | head -1 || echo "")
        
        if [[ -n "$masked_found" ]]; then
            log_success "패턴 '$pattern_name': 마스킹 성공 ($sample_value → $masked_found)"
            PATTERN_RESULTS="$PATTERN_RESULTS$pattern_name:SUCCESS|"
            PATTERN_DETAILS="$PATTERN_DETAILS$pattern_name:$sample_value → $masked_found|"
            SUCCESSFUL_PATTERNS=$((SUCCESSFUL_PATTERNS + 1))
        else
            log_warning "패턴 '$pattern_name': 응답 성공하지만 마스킹 미확인"
            PATTERN_RESULTS="$PATTERN_RESULTS$pattern_name:PARTIAL|"
            PATTERN_DETAILS="$PATTERN_DETAILS$pattern_name:$sample_value → 마스킹 미확인|"
        fi
    else
        log_error "패턴 '$pattern_name': HTTP $http_code 오류"
        PATTERN_RESULTS="$PATTERN_RESULTS$pattern_name:FAILED|"
        PATTERN_DETAILS="$PATTERN_DETAILS$pattern_name:HTTP $http_code: $(echo "$body" | head -1)|"
        FAILED_PATTERNS=$((FAILED_PATTERNS + 1))
    fi
    
    # Small delay to avoid overwhelming the system
    sleep 0.5
}

# Test all AWS patterns
test_all_aws_patterns() {
    log "=== 2. 46개 AWS 패턴 검증 ==="
    
    # High priority patterns (must work for deployment)
    test_aws_pattern "ec2_instance" "i-1234567890abcdef0" "AWS_EC2_001"
    test_aws_pattern "vpc" "vpc-12345678" "AWS_VPC_001" 
    test_aws_pattern "subnet" "subnet-1234567890abcdef0" "AWS_SUBNET_001"
    test_aws_pattern "security_group" "sg-12345678" "AWS_SECURITY_GROUP_001"
    test_aws_pattern "s3_bucket" "my-test-bucket" "AWS_S3_BUCKET_001"
    test_aws_pattern "rds_instance" "my-test-db" "AWS_RDS_001"
    test_aws_pattern "ami" "ami-12345678" "AWS_AMI_001"
    test_aws_pattern "ebs_volume" "vol-1234567890abcdef0" "AWS_EBS_VOL_001"
    test_aws_pattern "lambda_arn" "arn:aws:lambda:us-east-1:123456789012:function:my-function" "AWS_LAMBDA_ARN_001"
    test_aws_pattern "iam_role" "arn:aws:iam::123456789012:role/MyRole" "AWS_IAM_ROLE_001"
    
    # Medium priority patterns  
    test_aws_pattern "efs_id" "fs-12345678" "AWS_EFS_001"
    test_aws_pattern "igw" "igw-12345678" "AWS_IGW_001"
    test_aws_pattern "nat_gateway" "nat-1234567890abcdef0" "AWS_NAT_GW_001"
    test_aws_pattern "snapshot" "snap-1234567890abcdef0" "AWS_SNAPSHOT_001"
    test_aws_pattern "kms_key" "12345678-1234-1234-1234-123456789012" "AWS_KMS_KEY_001"
    test_aws_pattern "access_key" "AKIAIOSFODNN7EXAMPLE" "AWS_ACCESS_KEY_001"
    test_aws_pattern "route53_zone" "Z23ABC4XYZL05B" "AWS_ROUTE53_ZONE_001"
    test_aws_pattern "cloudfront" "E74FTE3AEXAMPLE" "AWS_CLOUDFRONT_001"
    test_aws_pattern "account_id" "123456789012" "AWS_ACCOUNT_001"
    test_aws_pattern "public_ip" "203.0.113.1" "AWS_PUBLIC_IP_001"
    
    # Lower priority patterns
    test_aws_pattern "elb_arn" "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-load-balancer/50dc6c495c0c9188" "AWS_ELB_ARN_001"
    test_aws_pattern "sns_topic" "arn:aws:sns:us-east-1:123456789012:my-topic" "AWS_SNS_TOPIC_001"
    test_aws_pattern "sqs_queue" "https://sqs.us-east-1.amazonaws.com/123456789012/my-queue" "AWS_SQS_QUEUE_001"
    test_aws_pattern "dynamodb_table" "arn:aws:dynamodb:us-east-1:123456789012:table/my-table" "AWS_DYNAMODB_TABLE_001"
    test_aws_pattern "ecs_task" "arn:aws:ecs:us-east-1:123456789012:task/a1b2c3d4-5678-90ab-cdef-EXAMPLE11111" "AWS_ECS_TASK_001"
    test_aws_pattern "stack_id" "arn:aws:cloudformation:us-east-1:123456789012:stack/my-stack/12345678-1234-1234-1234-123456789012" "AWS_CLOUDFORMATION_STACK_001"
    test_aws_pattern "cert_arn" "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012" "AWS_CERT_ARN_001"
    test_aws_pattern "secret_arn" "arn:aws:secretsmanager:us-east-1:123456789012:secret:my-secret-AbCdEf" "AWS_SECRET_ARN_001"
    test_aws_pattern "parameter_arn" "arn:aws:ssm:us-east-1:123456789012:parameter/my-parameter" "AWS_PARAM_ARN_001"
    test_aws_pattern "log_group" "/aws/lambda/my-function" "AWS_LOG_GROUP_001"
    
    # Remaining patterns for completeness
    test_aws_pattern "iam_user" "arn:aws:iam::123456789012:user/MyUser" "AWS_IAM_USER_001"
    test_aws_pattern "kinesis" "arn:aws:kinesis:us-east-1:123456789012:stream/my-stream" "AWS_KINESIS_001"
    test_aws_pattern "elasticsearch" "arn:aws:es:us-east-1:123456789012:domain/my-domain" "AWS_ES_DOMAIN_001"
    test_aws_pattern "stepfunctions" "arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine" "AWS_STEP_FN_001"
    test_aws_pattern "batch_queue" "arn:aws:batch:us-east-1:123456789012:job-queue/my-queue" "AWS_BATCH_QUEUE_001"
    test_aws_pattern "athena" "arn:aws:athena:us-east-1:123456789012:workgroup/my-workgroup" "AWS_ATHENA_001"
    test_aws_pattern "codecommit" "arn:aws:codecommit:us-east-1:123456789012:my-repo" "AWS_CODECOMMIT_001"
    test_aws_pattern "ecr_uri" "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-repo" "AWS_ECR_URI_001"
    test_aws_pattern "eks_cluster" "arn:aws:eks:us-east-1:123456789012:cluster/my-cluster" "AWS_EKS_CLUSTER_001"
    test_aws_pattern "sagemaker" "arn:aws:sagemaker:us-east-1:123456789012:endpoint/my-endpoint" "AWS_SAGEMAKER_001"
    test_aws_pattern "glue_job" "glue-job-my-etl-job" "AWS_GLUE_JOB_001"
    test_aws_pattern "redshift" "my-cluster-cluster" "AWS_REDSHIFT_001"
    test_aws_pattern "elasticache" "my-cache-12345-abc" "AWS_ELASTICACHE_001"
    test_aws_pattern "vpn" "vpn-12345678" "AWS_VPN_001"
    test_aws_pattern "tgw" "tgw-1234567890abcdef0" "AWS_TGW_001"
    test_aws_pattern "api_gateway" "1234567890.execute-api.us-east-1.amazonaws.com" "AWS_API_GW_001.execute-api."
    test_aws_pattern "s3_logs_bucket" "my-app-logs-bucket" "AWS_S3_LOGS_BUCKET_001"
    test_aws_pattern "ipv6" "2001:db8::1" "AWS_IPV6_001"
    
    log "AWS 패턴 검증 완료: $SUCCESSFUL_PATTERNS/$TOTAL_PATTERNS 성공"
}

# Test proxy chain
test_proxy_chain() {
    log "=== 3. 프록시 체인 안정성 검증 ==="
    
    local test_payload=$(cat << EOF
{
    "model": "claude-3-5-sonnet-20241022", 
    "max_tokens": 50,
    "messages": [
        {
            "role": "user",
            "content": "Test proxy chain with EC2 instance i-1234567890abcdef0"
        }
    ]
}
EOF
)
    
    # Test Nginx → Kong → Claude API chain
    local response=$(curl -s -X POST "$NGINX_ENDPOINT/v1/messages" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer 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" \
        -d "$test_payload" \
        -w "\nHTTP_CODE:%{http_code}\n" 2>/dev/null || echo "CURL_ERROR")
    
    local http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d':' -f2)
    
    if [[ "$http_code" == "200" ]]; then
        log_success "프록시 체인 테스트 성공 (Nginx → Kong → Claude)"
        PROXY_CHAIN_SUCCESS=true
        
        # Test header transformation (Authorization Bearer → x-api-key)
        local nginx_logs=$(docker logs claude-nginx 2>&1 | tail -10)
        local kong_logs=$(docker logs claude-kong 2>&1 | tail -10)
        
        if echo "$kong_logs" | grep -q "x-api-key"; then
            log_success "헤더 변환 확인됨 (Authorization Bearer → x-api-key)"
        else
            log_warning "헤더 변환 로그 확인 필요"
        fi
    else
        log_error "프록시 체인 테스트 실패: HTTP $http_code"
        PROXY_CHAIN_SUCCESS=false
    fi
}

# Test Redis mapping accuracy
test_redis_mapping() {
    log "=== 4. Redis 매핑 정확성 검증 ===" 
    
    local test_values=(
        "i-1234567890abcdef0"
        "vpc-12345678"
        "subnet-1234567890abcdef0"
        "sg-12345678"
        "ami-12345678"
    )
    
    local mapped_count=0
    local total_tests=${#test_values[@]}
    
    for value in "${test_values[@]}"; do
        # Send request to trigger masking
        local test_payload=$(cat << EOF
{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 50, 
    "messages": [
        {
            "role": "user",
            "content": "Analyze: $value"
        }
    ]
}
EOF
)
        
        curl -s -X POST "$KONG_DIRECT_ENDPOINT/v1/messages" \
            -H "Content-Type: application/json" \
            -H "x-api-key: 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" \
            -d "$test_payload" > /dev/null 2>&1
        
        sleep 1
        
        # Check if mapping exists in Redis
        local encoded_value=$(echo -n "$value" | base64)
        local redis_key="aws_masker:rev:$encoded_value"
        
        local mapped_value=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" get "$redis_key" 2>/dev/null || echo "")
        
        if [[ -n "$mapped_value" && "$mapped_value" != "(nil)" ]]; then
            mapped_count=$((mapped_count + 1))
            log_success "Redis 매핑 확인: $value → $mapped_value"
        else
            log_warning "Redis 매핑 없음: $value"
        fi
    done
    
    REDIS_ACCURACY=$((mapped_count * 100 / total_tests))
    log "Redis 매핑 정확성: $mapped_count/$total_tests ($REDIS_ACCURACY%)"
}

# Test basic error handling
test_error_handling() {
    log "=== 5. 기본 에러 처리 검증 ==="
    
    # Test with invalid API key
    local response=$(curl -s -X POST "$KONG_DIRECT_ENDPOINT/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: invalid-key" \
        -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":50,"messages":[{"role":"user","content":"test"}]}' \
        -w "HTTP_CODE:%{http_code}" 2>/dev/null)
    
    local http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d':' -f2)
    
    if [[ "$http_code" == "401" ]]; then
        log_success "잘못된 API 키 에러 처리 정상 (HTTP 401)"
    else
        log_warning "API 키 에러 처리 확인 필요 (HTTP $http_code)"
    fi
    
    # Test Redis connection (already tested in connectivity)
    log "Redis 연결 에러 처리는 연결성 테스트에서 확인됨"
}

# Generate final report
generate_report() {
    log "=== 6. 최종 보고서 생성 ==="
    
    local success_rate=$((SUCCESSFUL_PATTERNS * 100 / TOTAL_PATTERNS))
    local deployment_ready=false
    
    # Check deployment readiness criteria
    if [[ $success_rate -ge 80 && $PROXY_CHAIN_SUCCESS == true && $REDIS_ACCURACY -ge 95 ]]; then
        deployment_ready=true
    fi
    
    cat >> "$REPORT_FILE" << EOF

## 📊 최종 결과 요약

### 성공 기준 달성 여부

| 기준 | 목표 | 실제 결과 | 상태 |
|------|------|-----------|------|
| AWS 패턴 성공률 | 80% (37/46) | $success_rate% ($SUCCESSFUL_PATTERNS/$TOTAL_PATTERNS) | $([ $success_rate -ge 80 ] && echo "✅ 달성" || echo "❌ 미달성") |
| 프록시 체인 안정성 | 100% | $([ $PROXY_CHAIN_SUCCESS == true ] && echo "100% ✅ 달성" || echo "0% ❌ 실패") |
| Redis 매핑 정확성 | 95% | $REDIS_ACCURACY% | $([ $REDIS_ACCURACY -ge 95 ] && echo "✅ 달성" || echo "❌ 미달성") |

### 🎯 배포 준비 상태

**$([ $deployment_ready == true ] && echo "✅ 배포 준비 완료" || echo "❌ 추가 작업 필요")**

### 📈 패턴별 상세 결과

EOF
    
    # Add pattern details
    IFS='|' read -ra RESULTS <<< "$PATTERN_RESULTS"
    IFS='|' read -ra DETAILS <<< "$PATTERN_DETAILS"
    
    for i in "${!RESULTS[@]}"; do
        if [[ -n "${RESULTS[i]}" ]]; then
            local pattern_status="${RESULTS[i]}"
            local pattern_name="${pattern_status%%:*}"
            local status="${pattern_status##*:}"
            local detail="${DETAILS[i]##*:}"
            local icon="❌"
            
            case $status in
                "SUCCESS") icon="✅" ;;
                "PARTIAL") icon="⚠️" ;;
                "FAILED") icon="❌" ;;
            esac
            
            echo "- $icon **$pattern_name**: $detail" >> "$REPORT_FILE"
        fi
    done
    
    cat >> "$REPORT_FILE" << EOF

### 💡 권장사항

EOF
    
    if [[ $success_rate -lt 80 ]]; then
        echo "- 🔧 **패턴 성공률 향상 필요**: 실패한 패턴들의 정규식 및 로직 검토" >> "$REPORT_FILE"
    fi
    
    if [[ $PROXY_CHAIN_SUCCESS != true ]]; then
        echo "- 🔧 **프록시 체인 수정 필요**: Nginx-Kong 연결 및 헤더 변환 로직 점검" >> "$REPORT_FILE"
    fi
    
    if [[ $REDIS_ACCURACY -lt 95 ]]; then
        echo "- 🔧 **Redis 매핑 개선 필요**: Redis 연결 안정성 및 매핑 로직 검토" >> "$REPORT_FILE"
    fi
    
    if [[ $deployment_ready == true ]]; then
        echo "- 🚀 **배포 가능**: 모든 핵심 기능이 정상 동작하여 3-5일 내 배포 가능" >> "$REPORT_FILE"
    else
        echo "- ⏳ **추가 개발 필요**: 핵심 기능 안정화 후 배포 진행 권장" >> "$REPORT_FILE"
    fi
    
    cat >> "$REPORT_FILE" << EOF

---

**리포트 생성 시간**: $(date '+%Y-%m-%d %H:%M:%S')  
**리포트 파일**: $REPORT_FILE

EOF
    
    log_success "상세 리포트가 생성되었습니다: $REPORT_FILE"
    
    if [[ $deployment_ready == true ]]; then
        log_success "🎉 배포 준비 완료! 모든 핵심 기능이 성공 기준을 달성했습니다."
    else
        log_error "❌ 추가 작업 필요. 성공 기준 미달성으로 배포 전 개선이 필요합니다."
    fi
}

# Main execution
main() {
    log "Day 1 핵심 기능 완전 검증 시작..."
    init_report
    
    test_connectivity || exit 1
    test_all_aws_patterns
    test_proxy_chain  
    test_redis_mapping
    test_error_handling
    generate_report
    
    log "검증 완료. 상세 결과는 $REPORT_FILE 을 확인하세요."
}

# Run main function
main "$@"