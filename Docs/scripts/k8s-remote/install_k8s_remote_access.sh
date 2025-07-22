#!/bin/bash
# Kubernetes Remote Access Installation Script
# This script sets up everything needed for remote Kubernetes cluster access

# Configuration
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.kube/remote-clusters"
REMOTE_HOST="192.168.254.220"
REMOTE_USER="wondermove"
REMOTE_PASSWORD="Wonder9595!!"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Kubernetes Remote Access 설치 스크립트 ===${NC}"
echo

# Check prerequisites
echo -e "${YELLOW}1. 필수 패키지 확인 중...${NC}"
MISSING_DEPS=""

if ! command -v sshpass &> /dev/null; then
    MISSING_DEPS="$MISSING_DEPS sshpass"
fi

if ! command -v kubectl &> /dev/null; then
    MISSING_DEPS="$MISSING_DEPS kubectl"
fi

if [ -n "$MISSING_DEPS" ]; then
    echo -e "${RED}다음 패키지들이 필요합니다:$MISSING_DEPS${NC}"
    echo -e "${YELLOW}설치 방법:${NC}"
    echo "  macOS: brew install$MISSING_DEPS"
    echo "  Linux: sudo apt-get install$MISSING_DEPS"
    exit 1
fi

echo -e "${GREEN}✓ 모든 필수 패키지가 설치되어 있습니다.${NC}"

# Create directories
echo -e "${YELLOW}2. 디렉토리 생성 중...${NC}"
mkdir -p "$CONFIG_DIR"
mkdir -p "$HOME/.ssh/sockets"
echo -e "${GREEN}✓ 디렉토리가 생성되었습니다.${NC}"

# Copy scripts
echo -e "${YELLOW}3. 스크립트 설치 중...${NC}"

# Create setup_k8s_ssh_tunnel.sh
cat > "$CONFIG_DIR/setup_k8s_ssh_tunnel.sh" << 'EOF'
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

# SSH 터널 생성 함수
create_tunnel() {
    echo -e "${YELLOW}SSH 터널 생성 중...${NC}"
    sshpass -p "$REMOTE_PASSWORD" ssh -N -L ${LOCAL_PORT}:localhost:${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} &
    SSH_PID=$!
    echo $SSH_PID > ~/.kube/remote-clusters/ssh-tunnel.pid
    echo -e "${GREEN}SSH 터널이 생성되었습니다. (PID: $SSH_PID)${NC}"
}

# 터널 상태 확인
check_tunnel() {
    if [ -f ~/.kube/remote-clusters/ssh-tunnel.pid ]; then
        PID=$(cat ~/.kube/remote-clusters/ssh-tunnel.pid)
        if ps -p $PID > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# 터널 종료 함수
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
        fi
        ;;
    stop)
        stop_tunnel
        ;;
    status)
        if check_tunnel; then
            PID=$(cat ~/.kube/remote-clusters/ssh-tunnel.pid)
            echo -e "${GREEN}SSH 터널이 활성 상태입니다. (PID: $PID)${NC}"
        else
            echo -e "${RED}SSH 터널이 비활성 상태입니다.${NC}"
        fi
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
EOF

chmod +x "$CONFIG_DIR/setup_k8s_ssh_tunnel.sh"

# Download kubeconfig
echo -e "${YELLOW}4. Kubernetes 설정 파일 다운로드 중...${NC}"
sshpass -p "$REMOTE_PASSWORD" scp ${REMOTE_USER}@${REMOTE_HOST}:/home/${REMOTE_USER}/.kube/config "$CONFIG_DIR/master-config"

# Modify kubeconfig
sed -i.bak 's/server: https:\/\/127.0.0.1:6443/server: https:\/\/localhost:6443/g' "$CONFIG_DIR/master-config"
echo -e "${GREEN}✓ Kubernetes 설정 파일이 준비되었습니다.${NC}"

# Create kubectl wrapper
echo -e "${YELLOW}5. kubectl wrapper 생성 중...${NC}"
cat > "$CONFIG_DIR/kubectl-remote" << 'EOF'
#!/bin/bash
# kubectl wrapper for remote Kubernetes cluster access

TUNNEL_SCRIPT="$HOME/.kube/remote-clusters/setup_k8s_ssh_tunnel.sh"
KUBECONFIG_PATH="$HOME/.kube/remote-clusters/master-config"
PID_FILE="$HOME/.kube/remote-clusters/ssh-tunnel.pid"

# Check if tunnel is active
check_tunnel() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p $PID > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Start tunnel if not running
ensure_tunnel() {
    if ! check_tunnel; then
        $TUNNEL_SCRIPT start >/dev/null 2>&1
        sleep 2
    fi
}

# Handle tunnel commands
if [ "$1" == "tunnel" ]; then
    case "$2" in
        status|stop|restart)
            $TUNNEL_SCRIPT "$2"
            ;;
        *)
            echo "사용법: $0 tunnel {status|stop|restart}"
            ;;
    esac
else
    ensure_tunnel
    export KUBECONFIG="$KUBECONFIG_PATH"
    kubectl "$@"
fi
EOF

chmod +x "$CONFIG_DIR/kubectl-remote"

# Install to system path (optional)
echo
echo -e "${YELLOW}6. 시스템 경로에 설치하시겠습니까? (sudo 권한 필요) [y/N]${NC}"
read -r INSTALL_SYSTEM

if [[ "$INSTALL_SYSTEM" =~ ^[Yy]$ ]]; then
    sudo cp "$CONFIG_DIR/kubectl-remote" "$INSTALL_DIR/kubectl-remote"
    echo -e "${GREEN}✓ kubectl-remote가 $INSTALL_DIR에 설치되었습니다.${NC}"
    KUBECTL_CMD="kubectl-remote"
else
    echo -e "${YELLOW}시스템 설치를 건너뛰었습니다.${NC}"
    KUBECTL_CMD="$CONFIG_DIR/kubectl-remote"
fi

# Test installation
echo
echo -e "${YELLOW}7. 설치 테스트 중...${NC}"
$CONFIG_DIR/setup_k8s_ssh_tunnel.sh start
sleep 2

if $KUBECTL_CMD get nodes &> /dev/null; then
    echo -e "${GREEN}✓ 설치가 성공적으로 완료되었습니다!${NC}"
    echo
    echo -e "${BLUE}=== 사용 방법 ===${NC}"
    echo -e "${GREEN}기본 사용:${NC}"
    echo "  $KUBECTL_CMD get nodes"
    echo "  $KUBECTL_CMD get pods -A"
    echo "  $KUBECTL_CMD logs <pod-name>"
    echo
    echo -e "${GREEN}터널 관리:${NC}"
    echo "  $KUBECTL_CMD tunnel status  # 터널 상태 확인"
    echo "  $KUBECTL_CMD tunnel stop    # 터널 종료"
    echo "  $KUBECTL_CMD tunnel restart # 터널 재시작"
    echo
    echo -e "${GREEN}직접 kubeconfig 사용:${NC}"
    echo "  export KUBECONFIG=$CONFIG_DIR/master-config"
    echo "  kubectl get nodes"
else
    echo -e "${RED}✗ 연결 테스트에 실패했습니다.${NC}"
    echo "터널 상태를 확인하세요: $CONFIG_DIR/setup_k8s_ssh_tunnel.sh status"
fi