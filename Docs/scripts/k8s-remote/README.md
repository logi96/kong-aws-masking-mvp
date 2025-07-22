# Kubernetes 원격 접속 설정 파일

이 디렉토리에는 SSH 터널을 통한 Kubernetes 클러스터 원격 접속을 위한 모든 파일이 포함되어 있습니다.

## 파일 목록

1. **kubernetes_remote_access_guide.md**
   - 상세한 설정 가이드 (단계별 설명)
   - 문제 해결 방법
   - 고급 설정 옵션

2. **k8s_remote_quick_reference.md**
   - 빠른 참조 가이드
   - 주요 명령어 모음
   - 5분 안에 설정 완료

3. **install_k8s_remote_access.sh**
   - 자동 설치 스크립트
   - 모든 설정을 자동으로 수행
   - 대화형 설치 지원

4. **setup_k8s_ssh_tunnel.sh**
   - SSH 터널 관리 스크립트
   - start/stop/status/restart 명령 지원
   - 자동으로 설치됨

5. **kubectl-remote**
   - kubectl 래퍼 스크립트
   - 자동 터널 관리
   - 표준 kubectl 명령어 지원

## 빠른 시작

```bash
# 1. 설치 스크립트 실행
./install_k8s_remote_access.sh

# 2. 사용 시작
kubectl-remote get nodes
```

## 연결 정보

- **원격 서버**: 192.168.254.220
- **사용자**: wondermove
- **패스워드**: Wonder9595!!
- **로컬 포트**: 6443

## 자세한 내용

전체 설정 가이드는 `kubernetes_remote_access_guide.md`를 참조하세요.