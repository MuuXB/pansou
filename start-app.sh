#!/bin/bash
# start-app.sh - Docker Compose 应用启动脚本
# Cloud Studio 预览功能专用

set -e  # 遇到错误立即退出

# 配置变量
APP_NAME="盘搜应用"
APP_PORT=8080
APP_DIR="/workspace/pansou"
LOG_FILE="/tmp/docker-app.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  start    启动应用 (默认)"
    echo "  stop     停止应用"
    echo "  restart  重启应用"
    echo "  status   查看状态"
    echo "  logs     查看日志"
    echo "  help     显示此帮助"
}

# 检查依赖
check_dependencies() {
    log_info "检查系统依赖..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi
    
    log_info "Docker 版本: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
    log_info "Docker Compose 版本: $(docker-compose --version | cut -d' ' -f3 | cut -d',' -f1)"
}

# 启动应用
start_application() {
    log_info "正在启动 ${APP_NAME}..."
    
    # 切换到应用目录
    cd "$APP_DIR" || {
        log_error "无法切换到目录: $APP_DIR"
        exit 1
    }
    
    # 检查 docker-compose.yml 文件
    if [ ! -f "docker-compose.yml" ] && [ ! -f "docker-compose.yaml" ]; then
        log_error "在 $APP_DIR 中未找到 docker-compose.yml 文件"
        exit 1
    fi
    
    # 停止已运行的容器
    log_info "检查并停止已运行的容器..."
    docker-compose down 2>/dev/null || true
    
    # 启动容器
    log_info "启动 Docker Compose 服务..."
    if docker-compose up -d --build; then
        log_info "✅ Docker Compose 启动成功"
    else
        log_error "❌ Docker Compose 启动失败"
        exit 1
    fi
    
    # 等待服务启动
    wait_for_services
    
    # 显示状态
    show_status
}

# 等待服务就绪
wait_for_services() {
    log_info "等待服务就绪..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # 检查容器是否运行
        local running_count=$(docker-compose ps --services --filter "status=running" | wc -l)
        local total_count=$(docker-compose ps --services | wc -l)
        
        if [ $running_count -eq $total_count ] && [ $total_count -gt 0 ]; then
            log_info "✅ 所有 $running_count 个容器都在运行"
            
            # 检查端口是否可访问
            if check_port_accessibility; then
                log_info "✅ 应用端口 $APP_PORT 可访问"
                return 0
            fi
        fi
        
        log_info "⏳ 等待中... ($attempt/$max_attempts) - $running_count/$total_count 个容器运行"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log_warn "⚠️  应用启动较慢，但将继续监控..."
    return 0
}

# 检查端口可访问性
check_port_accessibility() {
    # 检查端口是否在监听
    if command -v nc &> /dev/null; then
        if nc -z localhost $APP_PORT 2>/dev/null; then
            return 0
        fi
    fi
    
    # 尝试 curl 访问
    if command -v curl &> /dev/null; then
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$APP_PORT" | grep -q "200\|301\|302"; then
            return 0
        fi
    fi
    
    return 1
}

# 停止应用
stop_application() {
    log_info "正在停止 ${APP_NAME}..."
    
    cd "$APP_DIR" 2>/dev/null || {
        log_warn "未找到应用目录，尝试停止所有相关容器..."
        docker-compose down 2>/dev/null || true
        return
    }
    
    docker-compose down
    log_info "✅ 应用已停止"
}

# 重启应用
restart_application() {
    log_info "重启 ${APP_NAME}..."
    stop_application
    sleep 2
    start_application
}

# 查看状态
show_status() {
    log_info "=== ${APP_NAME} 状态 ==="
    
    cd "$APP_DIR" 2>/dev/null || {
        log_error "未找到应用目录"
        return
    }
    
    echo ""
    echo "📊 容器状态:"
    docker-compose ps
    
    echo ""
    echo "📈 资源使用:"
    docker stats --no-stream 2>/dev/null || echo "无法获取资源统计"
    
    echo ""
    echo "🌐 访问信息:"
    if [ -n "$CODESPACE_NAME" ]; then
        echo "- Cloud Studio 预览: https://${CODESPACE_NAME}-${APP_PORT}.app.github.dev"
    fi
    echo "- 本地地址: http://localhost:${APP_PORT}"
    
    echo ""
    echo "📋 可用命令:"
    echo "- 查看日志: docker-compose logs -f"
    echo "- 停止应用: docker-compose down"
    echo "- 重启服务: docker-compose restart"
}

# 查看日志
show_logs() {
    log_info "显示 ${APP_NAME} 日志 (Ctrl+C 退出)..."
    
    cd "$APP_DIR" 2>/dev/null || {
        log_error "未找到应用目录"
        return
    }
    
    docker-compose logs -f
}

# 清理函数
cleanup() {
    echo ""
    log_warn "收到停止信号，正在清理..."
    
    # 停止容器
    stop_application
    
    # 清理临时文件
    rm -f "$LOG_FILE" 2>/dev/null || true
    
    log_info "✅ 清理完成"
    exit 0
}

# 主函数
main() {
    # 设置信号捕获
    trap cleanup SIGTERM SIGINT SIGQUIT
    
    # 检查依赖
    check_dependencies
    
    # 解析参数
    local action="start"
    if [ $# -gt 0 ]; then
        action="$1"
    fi
    
    case "$action" in
        "start")
            start_application
            
            # 进入监控模式
            log_info "进入监控模式，按 Ctrl+C 停止应用..."
            monitor_application
            ;;
        "stop")
            stop_application
            ;;
        "restart")
            restart_application
            
            # 进入监控模式
            log_info "进入监控模式，按 Ctrl+C 停止应用..."
            monitor_application
            ;;
        "status")
            show_status
            ;;
        "logs")
            show_logs
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "未知操作: $action"
            show_help
            exit 1
            ;;
    esac
}

# 监控应用
monitor_application() {
    while true; do
        # 检查容器状态
        cd "$APP_DIR" 2>/dev/null
        if ! docker-compose ps | grep -q "Up"; then
            log_error "检测到容器异常停止"
            exit 1
        fi
        
        # 每10秒检查一次
        sleep 10
    done
}

# 执行主函数
main "$@"