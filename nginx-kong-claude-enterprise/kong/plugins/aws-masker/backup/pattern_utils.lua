--
-- AWS Masker Pattern Utility Functions
-- 공통 검증 및 유틸리티 함수들
--

local _M = {}

---
-- 테이블에 특정 값이 포함되어 있는지 확인
-- @param table table 확인할 테이블
-- @param any value 찾을 값
-- @return boolean 포함 여부
--
function _M.contains(table, value)
  if not table or not value then
    return false
  end
  
  for _, v in ipairs(table) do
    if v == value then
      return true
    end
  end
  return false
end

---
-- 주변 텍스트에서 키워드 검색
-- @param string text 전체 텍스트
-- @param table keywords 검색할 키워드 배열
-- @param number range 검색 범위 (기본값: 100)
-- @param number position 현재 위치 (기본값: 텍스트 중앙)
-- @return boolean 키워드 발견 여부
--
function _M.has_nearby_keywords(text, keywords, range, position)
  if not text or not keywords then
    return false
  end
  
  range = range or 100
  position = position or math.floor(#text / 2)
  
  -- 검색 범위 설정
  local start_pos = math.max(1, position - range)
  local end_pos = math.min(#text, position + range)
  local context = string.sub(text, start_pos, end_pos):lower()
  
  -- 키워드 검색
  for _, keyword in ipairs(keywords) do
    if string.match(context, keyword:lower()) then
      return true
    end
  end
  
  return false
end

---
-- AWS S3 버킷 명명 규칙 검증
-- @param string bucket_name 버킷 이름
-- @return boolean 유효성 여부
--
function _M.validate_s3_naming_rules(bucket_name)
  if not bucket_name or type(bucket_name) ~= "string" then
    return false
  end
  
  -- 길이: 3-63자
  if #bucket_name < 3 or #bucket_name > 63 then
    return false
  end
  
  -- 소문자, 숫자, 점, 하이픈만 허용
  if not string.match(bucket_name, "^[a-z0-9.-]+$") then
    return false
  end
  
  -- 첫 글자와 마지막 글자는 소문자 또는 숫자
  if not string.match(bucket_name, "^[a-z0-9].*[a-z0-9]$") then
    return false
  end
  
  -- 점으로 시작하거나 끝나면 안됨
  if string.match(bucket_name, "^%.") or string.match(bucket_name, "%.$") then
    return false
  end
  
  -- 연속된 점 불가
  if string.match(bucket_name, "%.%.") then
    return false
  end
  
  -- IP 주소 형태 불가 (예: 192.168.1.1)
  if string.match(bucket_name, "^%d+%.%d+%.%d+%.%d+$") then
    return false
  end
  
  return true
end

---
-- RDS 인스턴스명 검증
-- @param string rds_name RDS 인스턴스 이름
-- @return boolean 유효성 여부
--
function _M.validate_rds_naming_rules(rds_name)
  if not rds_name or type(rds_name) ~= "string" then
    return false
  end
  
  -- 길이: 1-63자 (AWS 규칙)
  if #rds_name < 1 or #rds_name > 63 then
    return false
  end
  
  -- 소문자, 숫자, 하이픈만 허용
  if not string.match(rds_name, "^[a-z0-9-]+$") then
    return false
  end
  
  -- 첫 글자는 문자여야 함
  if not string.match(rds_name, "^[a-z]") then
    return false
  end
  
  -- 마지막 글자는 하이픈이면 안됨
  if string.match(rds_name, "-$") then
    return false
  end
  
  -- 연속된 하이픈 불가
  if string.match(rds_name, "--") then
    return false
  end
  
  return true
end

---
-- 일반 용어 블랙리스트 정의
--
_M.blacklists = {
  -- RDS 관련 일반 용어
  rds = {
    "db", "database", "sql", "mysql", "postgres", "mongodb", "sqlite",
    "handbook", "feedback", "sidebar", "dashboard", "breadboard", "hardboard"
  },
  
  -- S3 Bucket 관련 일반 용어
  s3_bucket = {
    "bucket", "buckets", "fire-bucket", "ice-bucket", "token-bucket",
    "water-bucket", "paint-bucket", "coal-bucket"
  },
  
  -- S3 Logs 관련 일반 용어
  s3_logs = {
    "logs", "log", "dialogs", "catalogs", "analogs", "weblogs", "changelogs",
    "backlogs", "epilogs", "prologs", "travelogs"
  },
  
  -- Cluster 관련 일반 용어
  cluster = {
    "cluster", "clusters", "k8s-cluster", "docker-cluster", "test-cluster",
    "kafka-cluster", "mysql-cluster", "mongodb-cluster", "elastic-cluster"
  }
}

---
-- 블랙리스트 확인
-- @param string category 카테고리 (rds, s3_bucket, s3_logs, cluster)
-- @param string text 확인할 텍스트
-- @return boolean 블랙리스트 포함 여부
--
function _M.is_blacklisted(category, text)
  if not category or not text then
    return false
  end
  
  local blacklist = _M.blacklists[category]
  if not blacklist then
    return false
  end
  
  return _M.contains(blacklist, text:lower())
end

---
-- AWS 컨텍스트 키워드 분석
-- @param string text 분석할 텍스트
-- @param string service_type 서비스 타입 (rds, s3, redshift 등)
-- @return table 분석 결과 {aws_score, general_score, probability}
--
function _M.analyze_aws_context(text, service_type)
  if not text then
    return {aws_score = 0, general_score = 0, probability = 0}
  end
  
  local aws_keywords = {
    -- 일반 AWS 키워드
    "aws", "amazon", "region", "availability-zone", "az",
    
    -- 서비스별 키워드
    rds = {"rds", "database", "instance", "cluster", "mysql", "postgres", "aurora"},
    s3 = {"s3", "bucket", "storage", "object", "upload", "download"},
    redshift = {"redshift", "warehouse", "analytics", "cluster", "data"},
    redis = {"redis", "cache", "memory", "cluster", "elasticache"}
  }
  
  local general_keywords = {
    "tutorial", "example", "guide", "documentation", "manual",
    "application", "software", "business", "company", "organization",
    "code", "development", "programming", "debugging", "testing"
  }
  
  local text_lower = text:lower()
  local aws_score = 0
  local general_score = 0
  
  -- AWS 키워드 점수 계산
  for _, keyword in ipairs(aws_keywords) do
    if string.match(text_lower, keyword) then
      aws_score = aws_score + 1
    end
  end
  
  -- 서비스별 키워드 추가 점수
  if service_type and aws_keywords[service_type] then
    for _, keyword in ipairs(aws_keywords[service_type]) do
      if string.match(text_lower, keyword) then
        aws_score = aws_score + 2  -- 서비스별 키워드는 가중치 2
      end
    end
  end
  
  -- 일반 키워드 점수 계산
  for _, keyword in ipairs(general_keywords) do
    if string.match(text_lower, keyword) then
      general_score = general_score + 1
    end
  end
  
  -- 확률 계산
  local total_score = aws_score + general_score
  local probability = total_score > 0 and (aws_score / total_score) or 0
  
  return {
    aws_score = aws_score,
    general_score = general_score,
    probability = probability,
    confidence = math.min(total_score / 5, 1.0)  -- 최대 1.0
  }
end

---
-- 복잡도 기반 검증 (하이픈, 점 포함 여부)
-- @param string text 검증할 텍스트
-- @param number min_length 최소 길이
-- @return boolean 복잡도 충족 여부
--
function _M.has_sufficient_complexity(text, min_length)
  if not text then
    return false
  end
  
  min_length = min_length or 5
  
  -- 최소 길이 확인
  if #text < min_length then
    return false
  end
  
  -- 하이픈 또는 점 포함 확인
  if string.match(text, "[.-]") then
    return true
  end
  
  -- 숫자와 문자가 혼합되어 있는지 확인
  if string.match(text, "%d") and string.match(text, "%a") then
    return true
  end
  
  return false
end

---
-- 로깅 유틸리티
-- @param string level 로그 레벨
-- @param string message 로그 메시지
--
function _M.log(level, message)
  if kong and kong.log then
    kong.log[level](message)
  end
end

return _M