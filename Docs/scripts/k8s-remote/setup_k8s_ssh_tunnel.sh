#!/bin/bash
# Kubernetes SSH 터널 설정 스크립트

# 설정 변수
REMOTE_HOST="192.168.254.220"
REMOTE_USER="wondermove"
REMOTE_PASSWORD="Wonder9595!!"
LOCAL_PORT="6443"
REMOTE_PORT="6443"

# 색상 코드
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Kubernetes SSH 터널 설정 ===${NC}"

# 1. 원격 서버에서 admin.conf 가져오기
echo -e "${YELLOW}1. 원격 서버에서 kubeconfig 다운로드 중...${NC}"
mkdir -p ~/.kube/remote-clusters

sshpass -p "$REMOTE_PASSWORD" scp ${REMOTE_USER}@${REMOTE_HOST}:/home/${REMOTE_USER}/.kube/config ~/.kube/remote-clusters/master-config

# 2. kubeconfig 수정 (localhost:6443으로 변경)
echo -e "${YELLOW}2. kubeconfig 파일 수정 중...${NC}"
sed -i.bak 's/server: https:\/\/127.0.0.1:6443/server: https:\/\/localhost:6443/g' ~/.kube/remote-clusters/master-config

# 3. SSH 터널 생성 함수
create_tunnel() {
    echo -e "${YELLOW}3. SSH 터널 생성 중...${NC}"
    sshpass -p "$REMOTE_PASSWORD" ssh -N -L ${LOCAL_PORT}:localhost:${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} &
    SSH_PID=$!
    echo $SSH_PID > ~/.kube/remote-clusters/ssh-tunnel.pid
    echo -e "${GREEN}SSH 터널이 생성되었습니다. (PID: $SSH_PID)${NC}"
}

# 4. 터널 상태 확인
check_tunnel() {
    if [ -f ~/.kube/remote-clusters/ssh-tunnel.pid ]; then
        PID=$(cat ~/.kube/remote-clusters/ssh-tunnel.pid)
        if ps -p $PID > /dev/null 2>&1; then
            echo -e "${GREEN}SSH 터널이 활성 상태입니다. (PID: $PID)${NC}"
            return 0
        fi
    fi
    echo -e "${RED}SSH 터널이 비활성 상태입니다.${NC}"
    return 1
}

# 5. 터널 종료 함수
stop_tunnel() {
    if [ -f ~/.kube/remote-clusters/ssh-tunnel.pid ]; then
        PID=$(cat ~/.kube/remote-clusters/ssh-tunnel.pid)
        if ps -p $PID > /dev/null 2>&1; then
            kill $PID
            rm ~/.kube/remote-clusters/ssh-tunnel.pid
            echo -e "${GREEN}SSH 터널이 종료되었습니다.${NC}"
        fi
    fi
}

# 명령어 처리
case "$1" in
    start)
        if check_tunnel; then
            echo -e "${YELLOW}터널이 이미 실행 중입니다.${NC}"
        else
            create_tunnel
            sleep 2
            echo -e "\n${GREEN}사용 방법:${NC}"
            echo "export KUBECONFIG=~/.kube/remote-clusters/master-config"
            echo "kubectl get nodes"
        fi
        ;;
    stop)
        stop_tunnel
        ;;
    status)
        check_tunnel
        ;;
    restart)
        stop_tunnel
        sleep 1
        create_tunnel
        ;;
    *)
        echo "사용법: $0 {start|stop|status|restart}"
        exit 1
        ;;
esac