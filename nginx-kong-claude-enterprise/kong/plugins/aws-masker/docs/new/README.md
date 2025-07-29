# Envoy + Kong 통합 설계 문서

## 📋 문서 개요

이 문서는 Kong API Gateway와 Envoy Proxy를 통합하여 Backend API의 모든 외부 호출을 투명하게 가로채고 보안 마스킹을 강제하는 솔루션의 설계 문서입니다.

## 🎯 핵심 목표

1. **보안 강제**: Backend가 외부 API를 직접 호출하지 못하도록 물리적 차단
2. **투명성**: Backend 코드 변경 없이 모든 외부 트래픽 가로채기
3. **복잡성 최소화**: 실용적이고 운영 가능한 수준의 아키텍처 구현
4. **기존 투자 보호**: 현재 Kong AWS Masker 플러그인 최대 활용

## 📚 문서 구조

### 1. [문제 분석 및 솔루션 개요](01-problem-analysis-and-solution-overview.md)
- 현재 시스템의 문제점 분석
- Envoy + Kong 솔루션의 필요성
- 기대 효과 및 ROI

### 2. [아키텍처 설계](02-architecture-design.md)
- 전체 시스템 아키텍처
- 컴포넌트 간 상호작용
- 데이터 흐름도

### 3. [구현 계획](03-implementation-plan.md)
- Before/After 코드 비교
- 단계별 구현 로드맵
- 주요 변경사항 상세

### 4. [환경 설정 가이드](04-environment-setup-guide.md)
- Envoy 설정 상세
- Kong 설정 변경사항
- 네트워크 설정 (iptables)

### 5. [품질 확보 방안](05-quality-assurance-plan.md)
- 코드 품질 표준
- 리뷰 체크리스트
- 성능 벤치마크

### 6. [테스트 전략](06-testing-strategy.md)
- 단위 테스트 계획
- 통합 테스트 시나리오
- 부하 테스트 및 장애 테스트

### 7. [개발 지침](07-development-guidelines.md)
- 필수 준수사항 (DO's)
- 금지사항 (DON'Ts)
- 베스트 프랙티스

## 🚀 Quick Start

1. **필수 읽기**: [문제 분석 및 솔루션 개요](01-problem-analysis-and-solution-overview.md)
2. **설계 이해**: [아키텍처 설계](02-architecture-design.md)
3. **구현 시작**: [구현 계획](03-implementation-plan.md)

## 📊 프로젝트 현황

- **문서 버전**: 1.0.0
- **작성일**: 2025-07-25
- **대상 시스템**: Kong AWS Masker MVP
- **구현 예상 기간**: 5주

## 🔧 기술 스택

- **Kong Gateway**: 3.9.0.1 (현재 버전 유지)
- **Envoy Proxy**: v1.28+ (신규 도입)
- **Redis**: 7-alpine (현재 버전 유지)
- **Docker**: 현재 환경 유지

## ⚠️ 주의사항

1. 이 설계는 **실용성**을 최우선으로 합니다
2. 오버스펙이나 불필요한 복잡성은 배제되었습니다
3. 기존 Kong 투자를 최대한 보호하는 방향으로 설계되었습니다

## 💬 문의 및 피드백

- 설계 관련 질문은 각 문서의 관련 섹션을 참조하세요
- 구현 중 이슈는 [개발 지침](07-development-guidelines.md)을 확인하세요