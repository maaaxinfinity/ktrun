#!/bin/bash

# 安装前创建必要的临时目录和文件
TMP_DIR="/tmp/ktransformers_tmp_$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

# 处理sudo环境下的PATH保留问题
if [ "$(id -u)" -eq 0 ]; then
    # 如果是sudo执行，尝试获取原始用户
    if [ -n "$SUDO_USER" ]; then
        # 获取原始用户的HOME目录
        REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        REAL_USER="$SUDO_USER"
        
        # 尝试合并原用户的PATH
        if [ -f "$REAL_HOME/.bashrc" ]; then
            echo "检测到sudo环境，尝试保留原用户环境变量..."
            # 获取原用户的PATH（不执行.bashrc中的其他命令）
            ORIGINAL_PATH=$(sudo -u "$SUDO_USER" bash -c 'echo $PATH')
            if [ -n "$ORIGINAL_PATH" ]; then
                export PATH="$ORIGINAL_PATH:$PATH"
                echo "已合并原用户PATH: $ORIGINAL_PATH"
            fi
        fi
        
        # 检查常见的CUDA路径
        CUDA_PATHS=(
            "/usr/local/cuda/bin"
            "$REAL_HOME/.local/cuda/bin"
            "$REAL_HOME/cuda/bin"
        )
        
        for cuda_path in "${CUDA_PATHS[@]}"; do
            if [ -d "$cuda_path" ]; then
                export PATH="$cuda_path:$PATH"
                echo "已添加CUDA路径: $cuda_path"
            fi
        done
        
        # 直接检查nvcc的位置
        NVCC_PATH=$(sudo -u "$SUDO_USER" which nvcc 2>/dev/null)
        if [ -n "$NVCC_PATH" ]; then
            NVCC_DIR=$(dirname "$NVCC_PATH")
            export PATH="$NVCC_DIR:$PATH"
            echo "已添加nvcc路径: $NVCC_DIR"
        fi
    fi
else
    # 普通用户执行
    REAL_HOME="$HOME"
    REAL_USER="$(whoami)"
fi

# 颜色设置
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

# 全局变量
BEST_GITHUB_SITE=""
REPO_URL=""
INSTALL_DIR=""
ENV_NAME=""
DEBUG_MODE=0
LOG_FILE=""

# 日志记录函数
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[信息] ${message}${NC}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}✓ ${message}${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠ ${message}${NC}"
            ;;
        "ERROR")
            echo -e "${RED}× ${message}${NC}"
            ;;
        *)
            echo -e "${message}"
            ;;
    esac
    
    if [ -n "$LOG_FILE" ]; then
        echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
    fi
}

# 日志记录函数 - 同时在屏幕显示并记录到日志文件
log_debug() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${CYAN}[DEBUG] ${message}${NC}"
    fi
    echo "[${timestamp}] [DEBUG] ${message}" >> "$LOG_FILE"
}

# 函数：询问是否启用调试模式
prompt_debug_mode() {
    echo -e "\n${YELLOW}**************** 调试模式 ****************${NC}"
    echo -e "${YELLOW}在5秒内按下回车键开启调试模式...${NC}"
    echo -e "${YELLOW}调试模式将记录详细日志并提供额外信息${NC}"
    echo -e "${YELLOW}***************************************${NC}\n"
    
    read -t 5 -n 1 -s -r -p ""
    
    if [ $? -eq 0 ]; then
        DEBUG_MODE=1
        echo -e "${GREEN}✓ 已启用调试模式！${NC}"
        echo -e "${CYAN}● 将记录详细的安装过程日志${NC}"
        echo -e "${CYAN}● 收集系统硬件和软件环境信息${NC}"
        echo -e "${CYAN}● 捕获并记录所有命令执行情况${NC}"
    else
        echo -e "${YELLOW}继续常规安装流程（未启用调试模式）${NC}"
    fi
}

# 函数：初始化日志文件
setup_log_file() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    LOG_FILE="ktransformers_install_${timestamp}.log"
    
    # 创建日志文件并写入头部信息
    echo "===== KTransformers 安装日志 - $(date) =====" > "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    # 记录调试模式状态
    if [ $DEBUG_MODE -eq 1 ]; then
        echo "调试模式: 启用" >> "$LOG_FILE"
        echo -e "${CYAN}日志文件: ${LOG_FILE}${NC}"
    else
        echo "调试模式: 禁用" >> "$LOG_FILE"
    fi
    echo "" >> "$LOG_FILE"
}

# 函数：收集系统信息
collect_system_info() {
    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${CYAN}[调试] 正在收集系统信息...${NC}"
    fi
    
    echo "===== 系统信息 =====" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    # CPU信息
    echo "--- CPU信息 ---" >> "$LOG_FILE"
    if command -v lscpu &> /dev/null; then
        lscpu >> "$LOG_FILE"
    else
        echo "CPU型号: $(grep "model name" /proc/cpuinfo | head -n 1 | cut -d":" -f2 | sed 's/^[ \t]*//')" >> "$LOG_FILE"
        echo "CPU核心数: $(grep -c "processor" /proc/cpuinfo)" >> "$LOG_FILE"
    fi
    echo "" >> "$LOG_FILE"
    
    # 内存信息
    echo "--- 内存信息 ---" >> "$LOG_FILE"
    if command -v free &> /dev/null; then
        free -h >> "$LOG_FILE"
    fi
    echo "" >> "$LOG_FILE"
    
    # 显卡信息
    echo "--- 显卡信息 ---" >> "$LOG_FILE"
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi >> "$LOG_FILE"
        if [ $DEBUG_MODE -eq 1 ]; then
            echo -e "${CYAN}[调试] 检测到NVIDIA显卡:${NC}"
            nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
        fi
    else
        echo "未找到NVIDIA显卡或nvidia-smi工具" >> "$LOG_FILE"
        if [ $DEBUG_MODE -eq 1 ]; then
            echo -e "${YELLOW}[调试] 未检测到NVIDIA显卡或nvidia-smi工具${NC}"
        fi
    fi
    echo "" >> "$LOG_FILE"
    
    # 系统信息
    echo "--- 系统信息 ---" >> "$LOG_FILE"
    if command -v lsb_release &> /dev/null; then
        lsb_release -a >> "$LOG_FILE" 2>&1
    elif [ -f /etc/os-release ]; then
        cat /etc/os-release >> "$LOG_FILE"
    fi
    echo "" >> "$LOG_FILE"
    
    # 内核信息
    echo "--- 内核信息 ---" >> "$LOG_FILE"
    uname -a >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    # 软件环境
    echo "--- 软件环境 ---" >> "$LOG_FILE"
    echo "Python版本: $(command -v python && python --version 2>&1 || echo "未安装")" >> "$LOG_FILE"
    echo "GCC版本: $(command -v gcc && gcc --version 2>&1 | head -n 1 || echo "未安装")" >> "$LOG_FILE"
    echo "Git版本: $(command -v git && git --version 2>&1 || echo "未安装")" >> "$LOG_FILE"
    echo "Conda版本: $(command -v conda && conda --version 2>&1 || echo "未安装")" >> "$LOG_FILE"
    
    if command -v nvcc &> /dev/null; then
        echo "CUDA版本: $(nvcc --version | grep "release" | awk '{print $6}' | sed 's/,//')" >> "$LOG_FILE"
    else
        echo "CUDA版本: 未安装" >> "$LOG_FILE"
    fi
    echo "" >> "$LOG_FILE"
    
    echo "===== 安装开始 =====" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${GREEN}✓ 系统信息收集完成${NC}"
    fi
}

# 检查命令是否存在
command_exists() {
    command -v "$1" &> /dev/null
}

# 扩展原有的重试命令，以支持调试和日志
retry_command_with_logging() {
    local command="$1"
    local max_attempts=3
    local attempt=1
    local timeout_duration="${2:-300}"  # 默认超时时间，以秒为单位
    
    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${CYAN}[调试] 命令: $command${NC}"
        echo -e "${CYAN}[调试] 最大尝试次数: $max_attempts, 超时: ${timeout_duration}秒${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] 执行命令: $command (最大尝试次数: $max_attempts, 超时: ${timeout_duration}秒)" >> "$LOG_FILE"
    fi
    
    while [ $attempt -le $max_attempts ]; do
        echo -e "${BLUE}尝试执行命令 (尝试 $attempt/$max_attempts): ${NC}$command"
        
        # 如果在调试模式下，记录命令开始执行的时间
        if [ $DEBUG_MODE -eq 1 ]; then
            local start_time=$(date +%s)
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] 开始尝试 #$attempt: $command" >> "$LOG_FILE"
        fi
        
        # 使用timeout执行命令并捕获输出和退出码
        local output
        output=$(timeout $timeout_duration bash -c "$command" 2>&1)
        local exit_code=$?
        
        # 记录命令输出到日志
        if [ -n "$output" ]; then
            echo "--- 命令输出开始 ---" >> "$LOG_FILE"
            echo "$output" >> "$LOG_FILE"
            echo "--- 命令输出结束 ---" >> "$LOG_FILE"
        fi
        
        if [ $exit_code -eq 0 ]; then
            if [ $DEBUG_MODE -eq 1 ]; then
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                echo -e "${CYAN}[调试] 命令成功执行，耗时: ${duration}秒${NC}"
                echo "[$(date +"%Y-%m-%d %H:%M:%S")] 命令成功执行，耗时: ${duration}秒" >> "$LOG_FILE"
            fi
            return 0
        fi
        
        if [ $exit_code -eq 124 ]; then
            echo -e "${YELLOW}命令执行超时${NC}"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] 命令执行超时" >> "$LOG_FILE"
        else
            echo -e "${YELLOW}命令执行失败 (错误码: $exit_code)${NC}"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] 命令执行失败 (错误码: $exit_code)" >> "$LOG_FILE"
            
            # 在调试模式下显示更多错误信息
            if [ $DEBUG_MODE -eq 1 ] && [ -n "$output" ]; then
                echo -e "${YELLOW}错误输出:${NC}"
                echo "$output" | tail -n 5
                echo -e "${YELLOW}(完整输出已记录到日志)${NC}"
            fi
        fi
        
        echo -e "${YELLOW}等待 5 秒后重试...${NC}"
        sleep 5
        ((attempt++))
    done
    
    echo -e "${RED}命令执行失败，已达到最大重试次数${NC}"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] 命令执行失败，已达到最大重试次数" >> "$LOG_FILE"
    
    return 1
}

# 进度条函数，添加调试日志记录
show_progress_with_logging() {
    local duration=$1
    local sleep_interval=1
    local progress=0
    local bar_size=40
    
    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${CYAN}[调试] 启动进度条，持续时间: $duration 秒${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] 启动进度条，持续时间: $duration 秒" >> "$LOG_FILE"
    fi
    
    echo -ne "${YELLOW}进度: [${NC}"
    
    for ((i=0; i<bar_size; i++)); do
        echo -ne " "
    done
    
    echo -ne "${YELLOW}] 0%${NC}\r"
    
    for ((i=0; i<=duration; i++)); do
        progress=$((i * 100 / duration))
        filled_size=$((i * bar_size / duration))
        
        echo -ne "${YELLOW}进度: [${NC}"
        
        for ((j=0; j<filled_size; j++)); do
            echo -ne "#"
        done
        
        for ((j=filled_size; j<bar_size; j++)); do
            echo -ne " "
        done
        
        echo -ne "${YELLOW}] ${progress}%${NC}\r"
        
        # 每10%记录一次进度到日志，只在DEBUG模式下
        if [ $DEBUG_MODE -eq 1 ] && [ $((i % (duration / 10))) -eq 0 ]; then
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] 进度: $progress%" >> "$LOG_FILE"
        fi
        
        if [ $i -lt $duration ]; then
            sleep $sleep_interval
        fi
    done
    
    echo -e "${YELLOW}进度: [${NC}$( printf '%-'${bar_size}'s' | tr ' ' '#' )${YELLOW}] 100%${NC}"
    
    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${CYAN}[调试] 进度条完成${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] 进度条完成" >> "$LOG_FILE"
    fi
}

# 检测是否为超级用户 - 添加调试信息
check_root() {
    echo -e "${BLUE}[步骤 0] 检测是否为超级用户${NC}"
    
    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${CYAN}[调试] 当前用户ID: $(id -u)${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] 检查超级用户权限，当前用户ID: $(id -u)" >> "$LOG_FILE"
    fi
    
    if [ "$(id -u)" -eq 0 ]; then
        echo -e "${GREEN}✓ 当前为超级用户${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] 当前为超级用户" >> "$LOG_FILE"
        return 0
    else
        echo -e "${RED}× 当前不是超级用户，请使用sudo运行此脚本${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] 当前不是超级用户，请使用sudo运行此脚本" >> "$LOG_FILE"
        return 1
    fi
}

# 检查并安装必要的工具 - 添加调试信息
check_required_tools() {
    echo -e "${BLUE}[准备工作] 检查必要工具${NC}"
    
    local missing_tools=()
    local essential_tools=("git" "bc" "wget" "timeout" "sed" "awk" "mktemp")
    
    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${CYAN}[调试] 检查以下必要工具: ${essential_tools[*]}${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] 检查必要工具: ${essential_tools[*]}" >> "$LOG_FILE"
    fi
    
    for tool in "${essential_tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
            echo -e "${YELLOW}缺少必要工具: $tool${NC}"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] 缺少必要工具: $tool" >> "$LOG_FILE"
        elif [ $DEBUG_MODE -eq 1 ]; then
            # 在调试模式下显示已安装工具的位置
            echo -e "${CYAN}[调试] $tool 已安装: $(which $tool)${NC}"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] $tool 已安装: $(which $tool)" >> "$LOG_FILE"
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${YELLOW}正在安装缺少的工具...${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] 正在安装缺少的工具: ${missing_tools[*]}" >> "$LOG_FILE"
        
        # 更新包管理器并设置非交互模式
        if [ $DEBUG_MODE -eq 1 ]; then
            echo -e "${CYAN}[调试] 更新软件包列表${NC}"
        fi
        
        if ! DEBIAN_FRONTEND=noninteractive apt-get update -y; then
            echo -e "${RED}更新包管理器失败${NC}"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] 更新包管理器失败" >> "$LOG_FILE"
            return 1
        fi
        
        # 安装缺失的工具
        for tool in "${missing_tools[@]}"; do
            echo -e "${YELLOW}正在安装: $tool${NC}"
            
            if [ $DEBUG_MODE -eq 1 ]; then
                echo -e "${CYAN}[调试] 开始安装 $tool${NC}"
                echo "[$(date +"%Y-%m-%d %H:%M:%S")] 开始安装 $tool" >> "$LOG_FILE"
            fi
            
            case "$tool" in
                "bc")
                    DEBIAN_FRONTEND=noninteractive apt-get install -y bc
                    ;;
                "git")
                    DEBIAN_FRONTEND=noninteractive apt-get install -y git
                    ;;
                "wget")
                    DEBIAN_FRONTEND=noninteractive apt-get install -y wget
                    ;;
                "timeout")
                    DEBIAN_FRONTEND=noninteractive apt-get install -y coreutils
                    ;;
                "sed"|"awk"|"mktemp")
                    DEBIAN_FRONTEND=noninteractive apt-get install -y coreutils
                    ;;
                *)
                    DEBIAN_FRONTEND=noninteractive apt-get install -y "$tool"
                    ;;
            esac
            
            if command_exists "$tool"; then
                echo -e "${GREEN}✓ 已安装: $tool${NC}"
                if [ $DEBUG_MODE -eq 1 ]; then
                    echo -e "${CYAN}[调试] $tool 安装成功: $(which $tool)${NC}"
                    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $tool 安装成功: $(which $tool)" >> "$LOG_FILE"
                    
                    # 显示版本信息（如果可用）
                    if $tool --version &>/dev/null; then
                        echo -e "${CYAN}[调试] $tool 版本: $($tool --version | head -n 1)${NC}"
                        echo "[$(date +"%Y-%m-%d %H:%M:%S")] $tool 版本: $($tool --version | head -n 1)" >> "$LOG_FILE"
                    fi
                fi
            else
                echo -e "${RED}× 安装失败: $tool${NC}"
                echo -e "${RED}请手动安装必要工具后再运行脚本${NC}"
                echo "[$(date +"%Y-%m-%d %H:%M:%S")] 安装失败: $tool" >> "$LOG_FILE"
                echo "[$(date +"%Y-%m-%d %H:%M:%S")] 请手动安装必要工具后再运行脚本" >> "$LOG_FILE"
                return 1
            fi
        done
        
        echo -e "${GREEN}✓ 所有必要工具安装完成${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] 所有必要工具安装完成" >> "$LOG_FILE"
    else
        echo -e "${GREEN}✓ 所有必要工具已安装${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] 所有必要工具已安装" >> "$LOG_FILE"
    fi
    
    return 0
}

# 检查必要的构建工具
check_build_tools() {
    log "INFO" "[准备工作] 检查构建工具"
    
    local build_tools=("make" "cmake" "gcc" "g++" "add-apt-repository")
    local missing_tools=()
    
    for tool in "${build_tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
            log "WARNING" "缺少构建工具: $tool"
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log "INFO" "正在安装缺少的构建工具..."
        
        # 更新包管理器并设置非交互模式
        if ! DEBIAN_FRONTEND=noninteractive apt-get update -y; then
            log "ERROR" "更新包管理器失败"
            return 1
        fi
        
        # 安装软件属性工具
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common; then
            log "ERROR" "安装software-properties-common失败"
            log "WARNING" "继续尝试安装其他工具"
        fi
        
        # 安装构建基础工具
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential cmake; then
            log "ERROR" "安装build-essential和cmake失败"
            log "WARNING" "继续尝试安装其他工具"
        fi
        
        # 再次检查工具安装情况
        local still_missing=()
        for tool in "${missing_tools[@]}"; do
            if ! command_exists "$tool"; then
                still_missing+=("$tool")
                log "ERROR" "工具 $tool 安装失败"
            else
                log "SUCCESS" "已安装: $tool"
            fi
        done
        
        if [ ${#still_missing[@]} -gt 0 ]; then
            log "WARNING" "部分构建工具安装失败，可能影响后续步骤"
            # 这里不返回错误，允许继续
        else
            log "SUCCESS" "所有构建工具安装完成"
        fi
    else
        log "SUCCESS" "所有构建工具已安装"
    fi
    
    return 0
}

# 1. 检测git，如果未安装则安装
install_git() {
    log "INFO" "[步骤 1] 检测git"
    
    if command_exists git; then
        log "SUCCESS" "git已安装"
    else
        log "WARNING" "git未安装，正在安装..."
        
        if retry_command_with_logging "apt-get update && apt-get install -y git" 300; then
            if command_exists git; then
                log "SUCCESS" "git安装成功"
            else
                log "ERROR" "git安装失败，虽然命令执行成功但找不到git命令"
                return 1
            fi
        else
            log "ERROR" "git安装失败"
            return 1
        fi
    fi
    
    return 0
}

# 1.5 测试GitHub连通性并选择最佳站点 - 并行方式
test_github_connectivity() {
    log "INFO" "[步骤 1.5] 测试GitHub连通性"
    
    # 定义要测试的站点
    local sites=(
        "github.com"
        "bgithub.xyz"
        "ggithub.xyz"
    )
    
    # 定义多个测试仓库（小型测试仓库，按优先级排序）
    local test_repos=(
        "hello-world:octocat"
        "github-docs:github"
        "gitignore:github"
    )
    
    # 创建临时目录
    local temp_dir
    temp_dir=$(mktemp -d)
    if ! pushd "$temp_dir" > /dev/null; then
        log "ERROR" "无法创建或进入临时目录"
        return 1
    fi
    
    # 并行测试函数
    test_site() {
        local site=$1
        local result_file=$2
        
        log "INFO" "测试站点 $site 的连通性..."
        
        # 多种测试方法标志
        local site_accessible=false
        local delay=999999
        
        # 1. 首先尝试通过克隆小型仓库测试
        for repo_info in "${test_repos[@]}"; do
            # 如果站点已检测成功，跳出循环
            if [ "$site_accessible" = true ]; then
                break
            fi
            
            # 解析仓库名称和所有者
            local test_repo="${repo_info%%:*}"
            local test_user="${repo_info#*:}"
            
            # 构建URL
            local url="https://$site/$test_user/$test_repo.git"
            log "INFO" "尝试克隆 $test_user/$test_repo..."
            
            # 测量克隆时间
            local start_time
            local end_time
            
            start_time=$(date +%s)
            
            # 尝试克隆（使用depth=1和quiet来减少网络流量和输出）
            if timeout 15 git clone --depth 1 --quiet "$url" "${site}_${test_repo}_test" 2>/dev/null; then
                end_time=$(date +%s)
                delay=$((end_time - start_time))
                
                log "SUCCESS" "站点 $site 可通过仓库 $test_user/$test_repo 访问，延迟: ${delay}秒"
                site_accessible=true
                
                # 清理克隆的仓库
                rm -rf "${site}_${test_repo}_test"
                # 写入结果文件
                echo "$site:accessible:$delay" > "$result_file"
                return
            else
                log "WARNING" "无法通过仓库 $test_user/$test_repo 访问站点 $site"
                # 继续尝试下一个测试仓库
            fi
        done
        
        # 2. 如果克隆失败，尝试通过HTTP GET请求测试
        if [ "$site_accessible" = false ]; then
            log "INFO" "尝试通过HTTP请求测试站点 $site..."
            
            if command_exists curl; then
                start_time=$(date +%s)
                if timeout 8 curl -s -o /dev/null -w "%{http_code}" "https://$site" | grep -q "^[23]"; then
                    end_time=$(date +%s)
                    delay=$((end_time - start_time))
                    site_accessible=true
                    log "SUCCESS" "站点 $site 可通过HTTP请求访问，延迟: ${delay}秒"
                    echo "$site:accessible:$delay" > "$result_file"
                    return
                else
                    log "ERROR" "站点 $site 无法通过HTTP请求访问"
                fi
            elif command_exists wget; then
                start_time=$(date +%s)
                if timeout 8 wget -q --spider "https://$site"; then
                    end_time=$(date +%s)
                    delay=$((end_time - start_time))
                    site_accessible=true
                    log "SUCCESS" "站点 $site 可通过HTTP请求访问，延迟: ${delay}秒"
                    echo "$site:accessible:$delay" > "$result_file"
                    return
                else
                    log "ERROR" "站点 $site 无法通过HTTP请求访问"
                fi
            fi
        fi
        
        # 如果站点完全无法访问
        if [ "$site_accessible" = false ]; then
            log "ERROR" "站点 $site 完全无法访问"
            echo "$site:inaccessible:999999" > "$result_file"
        fi
    }
    
    # 并行测试所有站点
    local result_files=()
    for site in "${sites[@]}"; do
        local result_file="$temp_dir/${site}_result.txt"
        result_files+=("$result_file")
        test_site "$site" "$result_file" &
    done
    
    # 等待所有测试完成
    wait
    
    # 分析结果
    local best_site=""
    local min_delay=999999
    local accessible=false
    
    for result_file in "${result_files[@]}"; do
        if [ -f "$result_file" ]; then
            local result=$(cat "$result_file")
            local site="${result%%:*}"
            local status="${result#*:}"
            status="${status%%:*}"
            local delay="${result##*:}"
            
            if [ "$status" = "accessible" ]; then
                accessible=true
                if [ "$delay" -lt "$min_delay" ]; then
                    min_delay=$delay
                    best_site=$site
                fi
            fi
        fi
    done
    
    # 清理临时目录
    if ! popd > /dev/null; then
        log "WARNING" "无法返回原始目录"
    fi
    rm -rf "$temp_dir"
    
    # 输出结果
    log "INFO" "GitHub连通性测试结果:"
    
    if [ "$accessible" = true ]; then
        log "SUCCESS" "使用延迟最低的站点: $best_site (延迟: ${min_delay}秒)"
        
        # 保存最佳站点到全局变量
        BEST_GITHUB_SITE="$best_site"
        
        # 根据最佳站点构建要使用的仓库URL
        REPO_URL="https://${best_site}/kvcache-ai/ktransformers.git"
        
        # 验证仓库URL的可访问性
        log "INFO" "验证仓库URL: ${REPO_URL}"
        if timeout 10 git ls-remote --quiet --exit-code "$REPO_URL" &>/dev/null; then
            log "SUCCESS" "仓库URL验证成功"
        else
            log "ERROR" "仓库URL验证失败，切换到默认GitHub URL"
            BEST_GITHUB_SITE="github.com"
            REPO_URL="https://github.com/kvcache-ai/ktransformers.git"
        fi
    else
        log "ERROR" "所有GitHub站点均无法访问"
        log "WARNING" "将尝试使用默认的GitHub URL"
        # 设置默认站点
        BEST_GITHUB_SITE="github.com"
        REPO_URL="https://github.com/kvcache-ai/ktransformers.git"
    fi
    
    log "INFO" "将使用仓库URL: ${REPO_URL}"
    return 0
}

# 2. 拉取仓库
clone_repository() {
    echo -e "${BLUE}[步骤 2] 拉取仓库${NC}"
    
    # 测试GitHub连通性并设置最佳仓库URL
    test_github_connectivity
    
    local default_dir="$(pwd)/ktransformers"
    
    echo -e "${YELLOW}请输入安装目录（默认为当前目录，10秒内未输入则使用默认目录）:${NC}"
    read -t 10 user_dir
    
    if [ -n "$user_dir" ]; then
        INSTALL_DIR="$user_dir"
        echo -e "${GREEN}使用指定目录: $INSTALL_DIR${NC}"
    else
        INSTALL_DIR="$default_dir"
        echo -e "${YELLOW}使用默认目录: $INSTALL_DIR${NC}"
    fi
    
    # 如果目录已存在，询问是否覆盖
    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}目录 $INSTALL_DIR 已存在。${NC}"
        echo -e "${YELLOW}1. 使用现有目录${NC}"
        echo -e "${YELLOW}2. 删除并重新克隆${NC}"
        read -t 10 -p "请选择 (默认: 1): " choice
        
        if [ "$choice" = "2" ]; then
            echo -e "${YELLOW}删除现有目录并重新克隆...${NC}"
            rm -rf "$INSTALL_DIR"
            retry_command_with_logging "git clone $REPO_URL $INSTALL_DIR" 300
        else
            echo -e "${YELLOW}使用现有目录...${NC}"
        fi
    else
        echo -e "${YELLOW}正在克隆仓库到 $INSTALL_DIR...${NC}"
        retry_command_with_logging "git clone $REPO_URL $INSTALL_DIR" 300
    fi
}

# 3. 检测conda，如果未安装则安装miniconda
install_conda() {
    echo -e "${BLUE}[步骤 3] 检测conda${NC}"
    
    # 先检查conda是否已在PATH中
    if command_exists conda; then
        echo -e "${GREEN}✓ conda已安装: $(which conda)${NC}"
        if [ $DEBUG_MODE -eq 1 ]; then
            conda_version=$(conda --version)
            echo -e "${CYAN}[调试] conda版本: ${conda_version}${NC}"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] conda已安装: $(which conda), 版本: ${conda_version}" >> "$LOG_FILE"
        fi
        return 0
    fi
    
    # 检查可能的conda路径
    local possible_conda_paths=(
        "$HOME/miniconda3/bin/conda"
        "$HOME/anaconda3/bin/conda"
        "/home/oak/miniconda3/bin/conda"  # 特别检查oak用户的miniconda路径
        "/opt/conda/bin/conda"
    )
    
    # 检查这些路径是否存在conda
    for conda_path in "${possible_conda_paths[@]}"; do
        if [ -f "$conda_path" ]; then
            echo -e "${YELLOW}找到conda但未在PATH中: ${conda_path}${NC}"
            echo -e "${YELLOW}正在将conda添加到PATH...${NC}"
            
            # 提取conda安装目录
            local conda_dir=$(dirname $(dirname "$conda_path"))
            export PATH="${conda_dir}/bin:$PATH"
            
            # 验证conda现在可用
            if command_exists conda; then
                echo -e "${GREEN}✓ 成功将conda添加到PATH: $(which conda)${NC}"
                if [ $DEBUG_MODE -eq 1 ]; then
                    conda_version=$(conda --version)
                    echo -e "${CYAN}[调试] conda版本: ${conda_version}${NC}"
                    echo "[$(date +"%Y-%m-%d %H:%M:%S")] 已将conda添加到PATH: $(which conda), 版本: ${conda_version}" >> "$LOG_FILE"
                fi
                return 0
            fi
        fi
    done
    
    echo -e "${YELLOW}conda未安装，正在安装miniconda...${NC}"
    
    # 下载miniconda安装脚本
    retry_command_with_logging "wget https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh"
    
    # 确定非root用户
    if [ "$(id -u)" -eq 0 ]; then
        local non_root_user=$(who | awk '{print $1}' | head -n 1)
        if [ -z "$non_root_user" ]; then
            non_root_user="ktuser"
            useradd -m -s /bin/bash $non_root_user || echo -e "${YELLOW}用户 $non_root_user 已存在${NC}"
            echo -e "${YELLOW}已创建用户 $non_root_user 用于安装conda${NC}"
        fi
        echo -e "${YELLOW}将为用户 $non_root_user 安装conda${NC}"
        
        # 检查miniconda目录是否已存在
        local miniconda_dir="/home/$non_root_user/miniconda3"
        if [ -d "$miniconda_dir" ]; then
            echo -e "${YELLOW}miniconda目录已存在: $miniconda_dir${NC}"
            echo -e "${YELLOW}尝试使用已有安装...${NC}"
            
            # 添加conda到系统变量
            echo "export PATH=$miniconda_dir/bin:\$PATH" > /etc/profile.d/conda.sh
            chmod +x /etc/profile.d/conda.sh
            
            # 设置当前会话的环境变量
            export PATH="$miniconda_dir/bin:$PATH"
            
            # 验证conda可用
            if command_exists conda; then
                echo -e "${GREEN}✓ conda设置成功${NC}"
                return 0
            else
                echo -e "${YELLOW}无法使用已有安装，尝试修复...${NC}"
                # 尝试使用-u参数更新已有安装
                su - $non_root_user -c "bash /tmp/miniconda.sh -u -b -p $miniconda_dir"
            fi
        else
            # 安装miniconda
            su - $non_root_user -c "bash /tmp/miniconda.sh -b -p $miniconda_dir"
        fi
        
        # 添加conda到系统变量
        echo "export PATH=$miniconda_dir/bin:\$PATH" > /etc/profile.d/conda.sh
        chmod +x /etc/profile.d/conda.sh
        
        # 设置当前会话的环境变量
        export PATH="$miniconda_dir/bin:$PATH"
        
        # 初始化conda给bash
        if command_exists conda; then
            echo -e "${YELLOW}正在初始化conda...${NC}"
            su - $non_root_user -c "conda init bash"
            echo -e "${GREEN}✓ conda初始化成功${NC}"
            
            if [ $DEBUG_MODE -eq 1 ]; then
                conda_version=$(conda --version)
                echo -e "${CYAN}[调试] conda版本: ${conda_version}${NC}"
                echo "[$(date +"%Y-%m-%d %H:%M:%S")] conda已安装: $(which conda), 版本: ${conda_version}" >> "$LOG_FILE"
            fi
            return 0
        else
            echo -e "${RED}× conda安装或配置失败${NC}"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] conda安装或配置失败" >> "$LOG_FILE"
            return 1
        fi
    else
        # 检查miniconda目录是否已存在
        local miniconda_dir="$HOME/miniconda3"
        if [ -d "$miniconda_dir" ]; then
            echo -e "${YELLOW}miniconda目录已存在: $miniconda_dir${NC}"
            echo -e "${YELLOW}尝试使用已有安装...${NC}"
            
            # 设置当前会话的环境变量
            export PATH="$miniconda_dir/bin:$PATH"
            
            # 验证conda可用
            if command_exists conda; then
                echo -e "${GREEN}✓ conda设置成功${NC}"
                
                # 确保初始化
                echo -e "${YELLOW}确保conda已初始化...${NC}"
                conda init bash
                
                if [ $DEBUG_MODE -eq 1 ]; then
                    conda_version=$(conda --version)
                    echo -e "${CYAN}[调试] conda版本: ${conda_version}${NC}"
                    echo "[$(date +"%Y-%m-%d %H:%M:%S")] conda已设置: $(which conda), 版本: ${conda_version}" >> "$LOG_FILE"
                fi
                return 0
            else
                echo -e "${YELLOW}无法使用已有安装，尝试修复...${NC}"
                # 尝试使用-u参数更新已有安装
                bash /tmp/miniconda.sh -u -b -p $miniconda_dir
            fi
        else
            # 直接安装
            bash /tmp/miniconda.sh -b -p $miniconda_dir
        fi
        
        # 设置环境变量
        export PATH="$miniconda_dir/bin:$PATH"
        echo "export PATH=$miniconda_dir/bin:\$PATH" >> $HOME/.bashrc
        
        # 初始化conda
        if command_exists conda; then
            echo -e "${YELLOW}正在初始化conda...${NC}"
            conda init bash
            echo -e "${GREEN}✓ conda初始化成功${NC}"
            
            if [ $DEBUG_MODE -eq 1 ]; then
                conda_version=$(conda --version)
                echo -e "${CYAN}[调试] conda版本: ${conda_version}${NC}"
                echo "[$(date +"%Y-%m-%d %H:%M:%S")] conda已安装: $(which conda), 版本: ${conda_version}" >> "$LOG_FILE"
            fi
            return 0
        else
            echo -e "${RED}× conda安装失败${NC}"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] conda安装失败" >> "$LOG_FILE"
            return 1
        fi
    fi
    
    rm -f /tmp/miniconda.sh
}

# 4. 使用conda创建环境
create_conda_env() {
    echo -e "${BLUE}[步骤 4] 创建conda环境${NC}"
    
    # 让用户输入环境名称
    local default_env_name="ktrans_main"
    
    echo -e "${YELLOW}请输入conda环境名称（默认为 $default_env_name，10秒内未输入则使用默认名称）:${NC}"
    read -t 10 user_env_name
    
    if [ -n "$user_env_name" ]; then
        ENV_NAME="$user_env_name"
        echo -e "${GREEN}使用指定环境名称: $ENV_NAME${NC}"
    else
        ENV_NAME="$default_env_name"
        echo -e "${YELLOW}使用默认环境名称: $ENV_NAME${NC}"
    fi
    
    retry_command_with_logging "conda create -n $ENV_NAME python=3.12 -y" 120
    echo -e "${GREEN}✓ conda环境 $ENV_NAME 创建成功${NC}"
}

# 检查并设置pip源
check_and_set_pip_mirror() {
    echo -e "${BLUE}[准备工作] 检查pip源配置${NC}"
    
    # 检查是否已经有pip配置
    local pip_config_file="$HOME/.pip/pip.conf"
    local is_china=false
    
    # 尝试通过IP和延迟判断是否在中国
    if command_exists curl; then
        # 检查延迟，如果访问国内网站延迟低于国外网站，则可能在中国
        local cn_delay=$(timeout 5 curl -s -o /dev/null -w "%{time_total}" https://www.baidu.com 2>/dev/null || echo "10")
        local global_delay=$(timeout 5 curl -s -o /dev/null -w "%{time_total}" https://www.google.com 2>/dev/null || echo "10")
        
        if (( $(echo "$cn_delay < $global_delay" | bc -l) )); then
            is_china=true
            echo -e "${YELLOW}检测到您可能位于中国大陆，建议使用国内镜像源${NC}"
        fi
    fi
    
    # 检查当前的pip源
    local current_index_url=""
    if [ -f "$pip_config_file" ]; then
        current_index_url=$(grep "index-url" "$pip_config_file" 2>/dev/null | cut -d "=" -f 2 | tr -d " ")
        
        if [ -n "$current_index_url" ]; then
            echo -e "${YELLOW}当前pip源: ${current_index_url}${NC}"
            
            # 判断是否为常见国内源
            if echo "$current_index_url" | grep -q -E "mirrors.ustc.edu.cn|tuna.tsinghua.edu.cn|mirrors.aliyun.com"; then
                echo -e "${GREEN}✓ 已配置国内pip源${NC}"
                return 0
            fi
        fi
    fi
    
    # 判断是否需要设置国内源
    if [ "$is_china" = true ] || [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${YELLOW}准备设置pip源为USTC源...${NC}"
        
        # 创建配置目录和文件
        mkdir -p $(dirname "$pip_config_file")
        echo "[global]
index-url = https://mirrors.ustc.edu.cn/pypi/web/simple
format = columns" > "$pip_config_file"
        
        echo -e "${GREEN}✓ pip源已设置为USTC源${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] pip源已设置为USTC源" >> "$LOG_FILE"
    else
        echo -e "${GREEN}✓ 保持当前pip源设置${NC}"
    fi
    
    return 0
}

# 增强的CUDA检测函数，支持更多场景
detect_pytorch_cuda_version() {
    echo -e "${BLUE}[准备工作] 检测CUDA环境${NC}"
    
    local cuda_version=""
    local nvcc_cuda_version=""
    local driver_version=""
    local estimated_cuda_version=""
    
    # 首先检查GPU驱动和CUDA兼容性
    if command_exists nvidia-smi; then
        driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)
        echo -e "${GREEN}✓ 检测到NVIDIA驱动版本: ${driver_version}${NC}"
        
        # 根据驱动版本估计兼容的CUDA版本
        case "${driver_version%%.*}" in
            "550"|"551"|"552"|"553"|"554"|"555") estimated_cuda_version="12.4" ;;
            "535"|"536"|"537"|"538"|"539"|"540") estimated_cuda_version="12.2" ;;
            "525"|"526"|"527"|"528"|"529"|"530") estimated_cuda_version="12.0" ;;
            "510"|"511"|"512"|"513"|"514"|"515"|"516"|"517"|"518"|"519"|"520") estimated_cuda_version="11.8" ;;
            "495"|"496"|"497"|"498"|"499"|"500"|"501"|"502"|"503"|"504"|"505") estimated_cuda_version="11.5" ;;
            *) estimated_cuda_version="" ;;
        esac
        
        if [ -n "$estimated_cuda_version" ]; then
            echo -e "${GREEN}✓ 驱动版本${driver_version}对应的CUDA版本: ${estimated_cuda_version}${NC}"
        else
            echo -e "${YELLOW}警告: 无法根据驱动版本${driver_version}估计CUDA版本${NC}"
        fi
        
        # 在调试模式下显示GPU信息
        if [ $DEBUG_MODE -eq 1 ]; then
            echo -e "${CYAN}[调试] GPU详细信息:${NC}"
            nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader | sed 's/^/  /'
        fi
    else
        echo -e "${YELLOW}警告: 未检测到NVIDIA GPU或无法运行nvidia-smi${NC}"
    fi
    
    # 检查常见的CUDA安装路径，优先选择与驱动兼容的版本
    local found_preferred_cuda=0
    local preferred_nvcc_path=""
    
    # 如果估计了CUDA版本，尝试找到对应的安装
    if [ -n "$estimated_cuda_version" ]; then
        local specific_cuda_path="/usr/local/cuda-${estimated_cuda_version}/bin/nvcc"
        local default_cuda_path="/usr/local/cuda/bin/nvcc"
        
        # 首先检查具体版本的路径
        if [ -f "$specific_cuda_path" ]; then
            preferred_nvcc_path="$specific_cuda_path"
            found_preferred_cuda=1
            echo -e "${GREEN}✓ 找到与驱动匹配的CUDA ${estimated_cuda_version}: ${preferred_nvcc_path}${NC}"
        # 然后检查默认路径是否为符合版本的软链接
        elif [ -f "$default_cuda_path" ]; then
            local default_version=$("$default_cuda_path" -V 2>&1 | grep "release" | awk '{print $6}' | sed 's/,//' | sed 's/V//')
            if [ "$default_version" = "$estimated_cuda_version" ]; then
                preferred_nvcc_path="$default_cuda_path"
                found_preferred_cuda=1
                echo -e "${GREEN}✓ 默认CUDA版本与驱动匹配: ${preferred_nvcc_path} (${default_version})${NC}"
            fi
        fi
    fi
    
    # 如果找到了与驱动匹配的CUDA，使用它
    if [ $found_preferred_cuda -eq 1 ] && [ -n "$preferred_nvcc_path" ]; then
        local version_output=$("$preferred_nvcc_path" -V 2>/dev/null)
        if [ -n "$version_output" ]; then
            nvcc_cuda_version=$(echo "$version_output" | grep "release" | awk '{print $6}' | sed 's/,//' | sed 's/V//')
            echo -e "${GREEN}✓ 使用与驱动匹配的CUDA版本: ${nvcc_cuda_version}${NC}"
            
            # 设置环境变量使用首选CUDA
            local nvcc_dir=$(dirname "$preferred_nvcc_path")
            export PATH="${nvcc_dir}:$PATH"
            echo -e "${YELLOW}已将匹配的CUDA版本添加到PATH: ${nvcc_dir}${NC}"
            
            # 在调试模式下显示详情
            if [ $DEBUG_MODE -eq 1 ]; then
                echo -e "${CYAN}[调试] 设置与驱动匹配的CUDA版本: ${nvcc_cuda_version}${NC}"
                echo -e "${CYAN}[调试] CUDA路径: ${nvcc_dir}${NC}"
                echo -e "${CYAN}[调试] 当前PATH: $PATH${NC}"
            fi
        fi
    # 否则，检查当前PATH中的nvcc
    elif command_exists nvcc; then
        local nvcc_path=$(which nvcc)
        nvcc_cuda_version=$(nvcc -V | grep "release" | awk '{print $6}' | sed 's/,//' | sed 's/V//')
        
        # 检查PATH中的版本是否与估计版本匹配
        if [ -n "$estimated_cuda_version" ] && [ "$nvcc_cuda_version" != "$estimated_cuda_version" ]; then
            echo -e "${YELLOW}警告: PATH中的CUDA版本(${nvcc_cuda_version})与驱动兼容的版本(${estimated_cuda_version})不匹配${NC}"
            echo -e "${YELLOW}推荐使用与驱动匹配的CUDA ${estimated_cuda_version}以获得最佳兼容性${NC}"
        fi
        
        echo -e "${GREEN}✓ 使用PATH中的CUDA版本: ${nvcc_cuda_version} (${nvcc_path})${NC}"
        
        # 在调试模式下，显示更多CUDA信息
        if [ $DEBUG_MODE -eq 1 ]; then
            echo -e "${CYAN}[调试] CUDA详细信息:${NC}"
            nvcc -V | sed 's/^/  /'
            
            # 检查系统中是否存在多个CUDA版本
            echo -e "${CYAN}[调试] 检查系统中的其他CUDA版本:${NC}"
            
            # 常见CUDA安装路径列表
            local cuda_dirs=(
                "/usr/local/cuda"
                "/usr/local/cuda-12.8"
                "/usr/local/cuda-12.4"
                "/usr/local/cuda-12.3"
                "/usr/local/cuda-12.2"
                "/usr/local/cuda-12.1"
                "/usr/local/cuda-12.0"
                "/usr/local/cuda-11.8"
                "/usr/local/cuda-11.7"
            )
            
            # 检查每个路径
            local found_other=0
            for cuda_dir in "${cuda_dirs[@]}"; do
                if [ -f "${cuda_dir}/bin/nvcc" ] && [ "${cuda_dir}/bin/nvcc" != "$nvcc_path" ]; then
                    local other_version=$("${cuda_dir}/bin/nvcc" -V 2>&1 | grep "release" | awk '{print $6}' | sed 's/,//' | sed 's/V//')
                    if [ -n "$other_version" ]; then
                        echo -e "${CYAN}[调试]   发现其他CUDA版本: ${other_version} (${cuda_dir}/bin/nvcc)${NC}"
                        found_other=1
                        
                        # 如果找到了与估计版本匹配的CUDA，提示用户
                        if [ "$other_version" = "$estimated_cuda_version" ] && [ "$nvcc_cuda_version" != "$estimated_cuda_version" ]; then
                            echo -e "${CYAN}[调试]   *** 推荐使用此版本，与NVIDIA驱动更兼容 ***${NC}"
                            echo -e "${CYAN}[调试]   可以通过设置PATH来使用它: export PATH=${cuda_dir}/bin:\$PATH${NC}"
                        fi
                    fi
                fi
            done
            
            if [ $found_other -eq 0 ]; then
                echo -e "${CYAN}[调试]   未发现其他CUDA版本${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}未在当前PATH中检测到nvcc命令，尝试其他方法...${NC}"
        
        # 如果正在使用sudo，尝试在原始用户环境中查找nvcc
        if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
            echo -e "${YELLOW}检测到sudo环境，尝试在用户${SUDO_USER}的环境中查找nvcc...${NC}"
            local user_nvcc_path=$(sudo -u "$SUDO_USER" which nvcc 2>/dev/null)
            
            if [ -n "$user_nvcc_path" ]; then
                echo -e "${GREEN}✓ 在用户${SUDO_USER}环境中找到nvcc: ${user_nvcc_path}${NC}"
                
                # 检查是否可以获取版本信息
                local version_output=$(sudo -u "$SUDO_USER" nvcc -V 2>/dev/null || "$user_nvcc_path" -V 2>/dev/null)
                if [ -n "$version_output" ]; then
                    nvcc_cuda_version=$(echo "$version_output" | grep "release" | awk '{print $6}' | sed 's/,//' | sed 's/V//')
                    echo -e "${GREEN}✓ 检测到CUDA版本: ${nvcc_cuda_version}${NC}"
                    
                    # 检查是否与驱动兼容
                    if [ -n "$estimated_cuda_version" ] && [ "$nvcc_cuda_version" != "$estimated_cuda_version" ]; then
                        echo -e "${YELLOW}警告: 用户环境中的CUDA版本(${nvcc_cuda_version})与驱动兼容的版本(${estimated_cuda_version})不匹配${NC}"
                    fi
                    
                    # 添加nvcc路径到当前PATH
                    local nvcc_dir=$(dirname "$user_nvcc_path")
                    echo -e "${YELLOW}添加${nvcc_dir}到PATH...${NC}"
                    export PATH="$nvcc_dir:$PATH"
                    
                    # 创建当前用户可以访问的软链接
                    local temp_bin_dir="/tmp/cuda_bin_$$"
                    echo -e "${YELLOW}创建临时CUDA工具目录: ${temp_bin_dir}${NC}"
                    mkdir -p "$temp_bin_dir"
                    ln -sf "$user_nvcc_path" "$temp_bin_dir/nvcc"
                    export PATH="$temp_bin_dir:$PATH"
                    
                    if [ $DEBUG_MODE -eq 1 ]; then
                        echo -e "${CYAN}[调试] 临时CUDA目录已创建: ${temp_bin_dir}${NC}"
                        echo -e "${CYAN}[调试] 已将nvcc软链接到: $temp_bin_dir/nvcc${NC}"
                        echo -e "${CYAN}[调试] 当前PATH: $PATH${NC}"
                    fi
                fi
            fi
        fi
        
        # 如果仍未找到nvcc，终止安装
        if [ -z "$nvcc_cuda_version" ]; then
            echo -e "${RED}[错误] 未能检测到有效的CUDA环境。${NC}"
            echo -e "${RED}[错误] 请确保已正确安装NVIDIA CUDA工具包，并将其添加到PATH中。${NC}"
            echo -e "${YELLOW}提示: 确认是否已安装NVIDIA驱动和CUDA工具包${NC}"
            echo -e "${YELLOW}提示: 请运行以下命令检查CUDA安装:${NC}"
            echo -e "${YELLOW}  which nvcc${NC}"
            echo -e "${YELLOW}  nvcc -V${NC}"
            
            if [ -n "$estimated_cuda_version" ]; then
                echo -e "${YELLOW}提示: 根据NVIDIA驱动版本${driver_version}，建议安装CUDA ${estimated_cuda_version}${NC}"
            fi
            
            echo -e "${YELLOW}提示: 如果已安装但未找到，请将CUDA路径添加到环境变量:${NC}"
            echo -e "${YELLOW}  export PATH=/usr/local/cuda/bin:\$PATH${NC}"
            
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] 安装终止: 未检测到CUDA环境" >> "$LOG_FILE"
            
            # 终止安装
            exit 1
        fi
    fi
    
    # 对nvcc_cuda_version处理
    cuda_version="$nvcc_cuda_version"
    
    # 格式化CUDA版本为flashinfer需要的格式
    local formatted_cuda_version=""
    if [ -n "$cuda_version" ]; then
        # 移除小数点，例如11.8变为118
        formatted_cuda_version="cu$(echo $cuda_version | sed 's/\.//')"
    else
        # 这种情况不应该发生，因为前面已经终止了安装
        echo -e "${RED}[错误] 无法确定CUDA版本${NC}"
        exit 1
    fi
    
    # 再次验证CUDA环境
    if command_exists nvcc; then
        echo -e "${GREEN}✓ nvcc命令可用${NC}"
        if [ $DEBUG_MODE -eq 1 ]; then
            echo -e "${CYAN}[调试] nvcc路径: $(which nvcc)${NC}"
            echo -e "${CYAN}[调试] nvcc版本: $(nvcc -V | head -n1)${NC}"
        fi
    else
        # 这种情况不应该发生，因为前面已经做了检查
        echo -e "${RED}[错误] nvcc命令检测失败，环境可能已经改变${NC}"
        exit 1
    fi
    
    # 将版本信息保存到全局变量
    CUDA_VERSION="$cuda_version"
    FORMATTED_CUDA_VERSION="$formatted_cuda_version"
    
    echo -e "${BLUE}格式化的CUDA版本：${FORMATTED_CUDA_VERSION}${NC}"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] 检测到CUDA版本: ${CUDA_VERSION}, 格式化为${FORMATTED_CUDA_VERSION}" >> "$LOG_FILE"
    
    return 0
}

# 安装并验证PyTorch
install_pytorch() {
    echo -e "${BLUE}[步骤 9.5] 安装GPU版本PyTorch${NC}"
    
    if ! command_exists pip; then
        echo -e "${YELLOW}pip命令不存在，尝试安装...${NC}"
        if command_exists conda; then
            if ! retry_command_with_logging "conda install -y pip"; then
                echo -e "${RED}× pip安装失败${NC}"
                return 1
            fi
        else
            if ! DEBIAN_FRONTEND=noninteractive apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip; then
                echo -e "${RED}× pip安装失败${NC}"
                return 1
            fi
        fi
    fi
    
    # 根据CUDA版本选择安装命令
    local torch_version=""
    local install_success=false
    
    echo -e "${YELLOW}开始安装PyTorch GPU版本 (CUDA ${CUDA_VERSION})...${NC}"
    
    # 优先使用pip安装，注意使用-f参数指定国内镜像源
    local pip_torch_cmd=""
    local torch_mirror="https://download.pytorch.org/whl"
    
    # 如果在中国大陆，尝试使用国内镜像
    if ping -c 1 mirrors.tuna.tsinghua.edu.cn &>/dev/null; then
        torch_mirror="https://mirrors.tuna.tsinghua.edu.cn/pytorch/whl"
        echo -e "${YELLOW}检测到国内网络环境，使用清华镜像源${NC}"
    elif ping -c 1 mirrors.ustc.edu.cn &>/dev/null; then
        torch_mirror="https://mirrors.ustc.edu.cn/pytorch/whl"
        echo -e "${YELLOW}检测到国内网络环境，使用中科大镜像源${NC}"
    fi
    
    # 根据CUDA版本构建pip安装命令
    if [ "${CUDA_VERSION}" = "12.4" ]; then
        pip_torch_cmd="pip install torch torchvision torchaudio -f ${torch_mirror}/cu124"
    elif [ "${CUDA_VERSION}" = "12.2" ]; then
        pip_torch_cmd="pip install torch torchvision torchaudio -f ${torch_mirror}/cu122"
    elif [ "${CUDA_VERSION}" = "12.1" ]; then
        pip_torch_cmd="pip install torch torchvision torchaudio -f ${torch_mirror}/cu121"
    elif [ "${CUDA_VERSION}" = "11.8" ]; then
        pip_torch_cmd="pip install torch torchvision torchaudio -f ${torch_mirror}/cu118"
    elif [ "${CUDA_VERSION}" = "11.7" ]; then
        pip_torch_cmd="pip install torch torchvision torchaudio -f ${torch_mirror}/cu117"
    else
        pip_torch_cmd="pip install torch torchvision torchaudio -f ${torch_mirror}/cu121"
    fi
    
    # 执行pip安装
    echo -e "${CYAN}[命令] ${pip_torch_cmd}${NC}"
    if eval "$pip_torch_cmd"; then
        echo -e "${GREEN}✓ PyTorch通过pip安装成功${NC}"
        install_success=true
    else
        echo -e "${YELLOW}通过pip安装PyTorch失败，尝试通过conda安装...${NC}"
        
        # 使用conda安装
        if command_exists conda; then
            echo -e "${CYAN}[命令] conda install -y pytorch torchvision torchaudio pytorch-cuda=${CUDA_VERSION} -c pytorch -c nvidia${NC}"
            if conda install -y pytorch torchvision torchaudio pytorch-cuda=${CUDA_VERSION} -c pytorch -c nvidia; then
                echo -e "${GREEN}✓ PyTorch通过conda安装成功${NC}"
                install_success=true
            else
                echo -e "${RED}× PyTorch安装失败${NC}"
                return 1
            fi
        else
            echo -e "${RED}× conda不可用，PyTorch安装失败${NC}"
            return 1
        fi
    fi
    
    # 验证PyTorch安装和CUDA可用性
    if [ "$install_success" = true ]; then
        echo -e "${YELLOW}验证PyTorch和CUDA...${NC}"
        
        # 获取PyTorch版本
        torch_version=$(python -c "import torch; print(torch.__version__.split('+')[0])" 2>/dev/null)
        if [ -n "$torch_version" ]; then
            echo -e "${GREEN}✓ PyTorch版本: ${torch_version}${NC}"
            TORCH_VERSION="$torch_version"
            
            # 格式化PyTorch版本为flashinfer需要的格式
            FORMATTED_TORCH_VERSION="torch$(echo $torch_version | cut -d '.' -f 1,2)"
            echo -e "${BLUE}格式化的PyTorch版本：${FORMATTED_TORCH_VERSION}${NC}"
            
            # 检查CUDA是否可用
            if python -c "import torch; exit(0 if torch.cuda.is_available() else 1)" &>/dev/null; then
                local cuda_torch_version=$(python -c "import torch; print(torch.version.cuda)" 2>/dev/null)
                echo -e "${GREEN}✓ CUDA可用，PyTorch报告的CUDA版本: ${cuda_torch_version}${NC}"
                
                # 更新CUDA_VERSION如果通过PyTorch检测到
                if [ -n "$cuda_torch_version" ] && [ -z "$CUDA_VERSION" ]; then
                    CUDA_VERSION="$cuda_torch_version"
                    FORMATTED_CUDA_VERSION="cu$(echo $cuda_torch_version | sed 's/\.//')"
                    echo -e "${YELLOW}更新CUDA版本为PyTorch报告的版本: ${CUDA_VERSION}${NC}"
                fi
                
                echo -e "${GREEN}✓ GPU加速已启用${NC}"
                return 0
            else
                echo -e "${RED}× CUDA不可用，PyTorch将使用CPU模式${NC}"
                echo -e "${YELLOW}您可能需要检查NVIDIA驱动和CUDA安装${NC}"
                return 1
            fi
        else
            echo -e "${RED}× 无法获取PyTorch版本信息${NC}"
            return 1
        fi
    fi
    
    return 1
}

# 6. 初始化和更新git子模块
init_git_submodules() {
    echo -e "${BLUE}[步骤 6] 初始化和更新git子模块${NC}"
    
    # 确保在git仓库目录中
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}× 目录 $INSTALL_DIR 不存在${NC}"
        return 1
    fi
    
    cd "$INSTALL_DIR" || {
        echo -e "${RED}× 无法进入 $INSTALL_DIR 目录${NC}"
        return 1
    }
    
    # 检查是否为git仓库
    if [ ! -d ".git" ]; then
        echo -e "${RED}× $INSTALL_DIR 不是一个git仓库${NC}"
        return 1
    fi
    
    # 如果使用了镜像站点，修改子模块URL
    if [ "$BEST_GITHUB_SITE" != "github.com" ] && [ -n "$BEST_GITHUB_SITE" ]; then
        echo -e "${YELLOW}正在将子模块URL修改为使用镜像站点 $BEST_GITHUB_SITE...${NC}"
        
        # 检查.gitmodules文件是否存在
        if [ -f ".gitmodules" ]; then
            # 备份原始.gitmodules文件
            cp .gitmodules .gitmodules.bak
            
            # 使用sed替换所有github.com为镜像站点
            sed -i "s|https://github.com|https://$BEST_GITHUB_SITE|g" .gitmodules
            echo -e "${GREEN}✓ 已修改.gitmodules文件中的URL${NC}"
            
            # 获取所有子模块路径
            local submodules=$(git config --file .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{ print $2 }')
            
            # 为每个子模块更新URL
            for submodule in $submodules; do
                # 获取子模块的新URL（从.gitmodules读取）
                local new_url=$(git config --file .gitmodules --get "submodule.$submodule.url")
                
                echo -e "${YELLOW}更新子模块 $submodule 的URL: $new_url${NC}"
                # 配置子模块的URL
                git config "submodule.$submodule.url" "$new_url"
            done
            
            echo -e "${GREEN}✓ 已更新所有子模块的URL配置${NC}"
        else
            echo -e "${YELLOW}未找到.gitmodules文件，跳过URL修改${NC}"
        fi
    fi
    
    echo -e "${YELLOW}正在初始化git子模块...${NC}"
    if git submodule init; then
        echo -e "${GREEN}✓ git子模块初始化完成${NC}"
    else
        echo -e "${RED}× git子模块初始化失败${NC}"
        return 1
    fi
    
    # 使用改进的进度显示函数更新子模块
    if update_git_submodules_with_progress; then
        echo -e "${GREEN}✓ git子模块配置全部完成${NC}"
        return 0
    else
        return 1
    fi
}

# 7. 安装libnuma-dev
install_libnuma() {
    echo -e "${BLUE}[步骤 7] 安装libnuma-dev${NC}"
    if DEBIAN_FRONTEND=noninteractive apt-get install -y libnuma-dev; then
        echo -e "${GREEN}✓ libnuma-dev安装成功${NC}"
        return 0
    else
        echo -e "${RED}× libnuma-dev安装失败${NC}"
        return 1
    fi
}

# 8. 设置USE_NUMA环境变量
set_use_numa() {
    echo -e "${BLUE}[步骤 8] 设置USE_NUMA环境变量${NC}"
    export USE_NUMA=1
    echo -e "${GREEN}✓ 已设置USE_NUMA=1${NC}"
}

# 9. 下载预编译的flashinfer - 改进版，自动匹配PyTorch和CUDA版本
download_flashinfer() {
    echo -e "${BLUE}[步骤 10] 安装flashinfer${NC}"
    
    # 确保已检测到PyTorch和CUDA版本
    if [ -z "$FORMATTED_CUDA_VERSION" ] || [ -z "$FORMATTED_TORCH_VERSION" ]; then
        echo -e "${YELLOW}CUDA或PyTorch版本信息缺失，尝试重新检测...${NC}"
        
        # 验证PyTorch安装和CUDA可用性
        local torch_version=$(python -c "import torch; print(torch.__version__.split('+')[0])" 2>/dev/null)
        if [ -n "$torch_version" ]; then
            TORCH_VERSION="$torch_version"
            FORMATTED_TORCH_VERSION="torch$(echo $torch_version | cut -d '.' -f 1,2)"
            
            # 检查CUDA是否可用
            if python -c "import torch; exit(0 if torch.cuda.is_available() else 1)" &>/dev/null; then
                local cuda_torch_version=$(python -c "import torch; print(torch.version.cuda)" 2>/dev/null)
                if [ -n "$cuda_torch_version" ]; then
                    CUDA_VERSION="$cuda_torch_version"
                    FORMATTED_CUDA_VERSION="cu$(echo $cuda_torch_version | sed 's/\.//')"
                fi
            fi
        fi
    fi
    
    # 安装路径构建
    local whl_url="https://flashinfer.ai/whl/${FORMATTED_CUDA_VERSION}/${FORMATTED_TORCH_VERSION}"
    local package_name="flashinfer-python"
    
    echo -e "${YELLOW}尝试安装预编译的flashinfer (${FORMATTED_CUDA_VERSION}/${FORMATTED_TORCH_VERSION})...${NC}"
    echo -e "${CYAN}[命令] pip install ${package_name} -f ${whl_url}${NC}"
    
    # 尝试使用预编译的wheel包安装 (注意：使用-f而不是-i)
    if pip install ${package_name} -f ${whl_url}; then
        echo -e "${GREEN}✓ flashinfer预编译包安装成功${NC}"
        
        # 验证安装
        if python -c "import flashinfer; print('flashinfer版本:', flashinfer.__version__)" 2>/dev/null; then
            echo -e "${GREEN}✓ flashinfer导入测试成功${NC}"
            return 0
        else
            echo -e "${YELLOW}flashinfer安装成功但导入失败，可能需要修复PYTHONPATH${NC}"
        fi
    else
        echo -e "${YELLOW}预编译包安装失败，尝试从源码安装...${NC}"
        
        # 尝试从源代码安装
        local temp_dir
        temp_dir=$(mktemp -d)
        pushd "$temp_dir" > /dev/null || return 1
        
        # 从最佳站点克隆flashinfer仓库（带--recursive获取所有子模块）
        local flashinfer_url="https://${BEST_GITHUB_SITE}/flashinfer-ai/flashinfer.git"
        echo -e "${YELLOW}从源码安装flashinfer: git clone ${flashinfer_url} --recursive${NC}"
        
        if ! git clone ${flashinfer_url} --recursive; then
            # 如果镜像站点失败，尝试从官方GitHub
            flashinfer_url="https://github.com/flashinfer-ai/flashinfer.git"
            echo -e "${YELLOW}尝试从官方GitHub安装: git clone ${flashinfer_url} --recursive${NC}"
            
            if ! git clone ${flashinfer_url} --recursive; then
                echo -e "${RED}× flashinfer克隆失败${NC}"
                popd > /dev/null || return 1
                rm -rf "$temp_dir"
                
                echo -e "${YELLOW}跳过flashinfer安装，后续可能会影响某些功能${NC}"
                return 1
            fi
        fi
        
        # 进入flashinfer目录安装
        cd flashinfer || return 1
        echo -e "${YELLOW}在源码目录中执行: pip install -e . -v${NC}"
        
        if pip install -e . -v; then
            echo -e "${GREEN}✓ flashinfer从源码安装成功${NC}"
            
            # 验证安装
            if python -c "import flashinfer; print('flashinfer版本:', flashinfer.__version__)" 2>/dev/null; then
                echo -e "${GREEN}✓ flashinfer导入测试成功${NC}"
                popd > /dev/null || return 1
                rm -rf "$temp_dir"
                return 0
            else
                echo -e "${YELLOW}flashinfer安装成功但导入失败，可能需要修复PYTHONPATH${NC}"
                
                # 尝试修复PYTHONPATH
                local site_packages=$(python -c "import site; print(site.getsitepackages()[0])")
                if [ -n "$site_packages" ]; then
                    echo -e "${YELLOW}尝试将flashinfer复制到site-packages目录...${NC}"
                    cp -r flashinfer "$site_packages/" 2>/dev/null
                    
                    if python -c "import flashinfer; print('flashinfer版本:', flashinfer.__version__)" 2>/dev/null; then
                        echo -e "${GREEN}✓ flashinfer导入修复成功${NC}"
                        popd > /dev/null || return 1
                        rm -rf "$temp_dir"
                        return 0
                    fi
                fi
            fi
            
            popd > /dev/null || return 1
            rm -rf "$temp_dir"
            echo -e "${YELLOW}将继续安装过程，但flashinfer导入可能有问题${NC}"
            return 1
        else
            echo -e "${RED}× flashinfer从源码安装失败${NC}"
            echo -e "${YELLOW}将继续安装过程，但某些功能可能不可用${NC}"
            popd > /dev/null || return 1
            rm -rf "$temp_dir"
            return 1
        fi
    fi
}

# 11. 执行make dev_install
make_dev_install() {
    echo -e "${BLUE}[步骤 11] 执行make dev_install${NC}"
    
    # 确保在仓库目录中
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}× 目录 $INSTALL_DIR 不存在${NC}"
        return 1
    fi
    
    cd "$INSTALL_DIR" || {
        echo -e "${RED}× 无法进入 $INSTALL_DIR 目录${NC}"
        return 1
    }
    
    # 检查make命令是否存在
    if ! command_exists make; then
        echo -e "${RED}× make命令不存在，尝试安装...${NC}"
        DEBIAN_FRONTEND=noninteractive apt-get update -y && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential
        
        if ! command_exists make; then
            echo -e "${RED}× 无法安装make工具，跳过make dev_install步骤${NC}"
            echo -e "${YELLOW}尝试使用pip直接安装...${NC}"
            
            if pip install -e .; then
                echo -e "${GREEN}✓ 使用pip安装成功${NC}"
                return 0
            else
                echo -e "${RED}× 使用pip安装也失败${NC}"
                echo -e "${YELLOW}您可能需要手动执行安装:${NC}"
                echo -e "${YELLOW}1. 安装build-essential${NC}"
                echo -e "${YELLOW}2. 进入 $INSTALL_DIR 目录${NC}"
                echo -e "${YELLOW}3. 执行 make dev_install 或 pip install -e .${NC}"
                return 1
            fi
        fi
    fi
    
    # 执行make dev_install并保存错误日志
    echo -e "${YELLOW}开始执行make dev_install（这可能需要一些时间）...${NC}"
    echo -e "${CYAN}编译过程中可能会显示一些警告，这是正常现象${NC}"
    
    local make_output=""
    local make_error_file="$INSTALL_DIR/make_error.log"
    
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] 开始执行make dev_install..." > "$make_error_file"
    
    # 执行make dev_install，将标准输出和错误输出都保存到变量和日志文件
    if make_output=$(make dev_install 2>&1); then
        echo -e "${GREEN}✓ make dev_install执行成功${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] make dev_install执行成功" >> "$make_error_file"
        return 0
    else
        local exit_code=$?
        echo -e "${RED}× make dev_install执行失败 (错误码: $exit_code)${NC}"
        echo -e "${YELLOW}编译错误已保存到 $make_error_file${NC}"
        
        # 保存详细错误信息到日志文件
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] make dev_install执行失败 (错误码: $exit_code)" >> "$make_error_file"
        echo "==================== 错误输出 ====================" >> "$make_error_file"
        echo "$make_output" >> "$make_error_file"
        echo "==================================================" >> "$make_error_file"
        
        # 显示错误摘要
        echo -e "${YELLOW}错误摘要:${NC}"
        echo "$make_output" | tail -n 15
        
        echo -e "${YELLOW}尝试使用pip直接安装...${NC}"
        if pip install -e .; then
            echo -e "${GREEN}✓ 使用pip安装成功${NC}"
            return 0
        else
            echo -e "${RED}× 使用pip安装也失败${NC}"
            echo -e "${YELLOW}将继续安装过程，但功能可能不完整${NC}"
            return 1
        fi
    fi
}

# 12. 更新libstdc++6
update_libstdcpp6() {
    echo -e "${BLUE}[步骤 12] 更新libstdc++6${NC}"
    
    # 检查add-apt-repository命令是否存在
    if ! command_exists add-apt-repository; then
        echo -e "${YELLOW}add-apt-repository命令不存在，尝试安装...${NC}"
        DEBIAN_FRONTEND=noninteractive apt-get update -y && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common
    fi
    
    if command_exists add-apt-repository; then
        if add-apt-repository ppa:ubuntu-toolchain-r/test -y && \
           DEBIAN_FRONTEND=noninteractive apt-get update -y && \
           DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade libstdc++6; then
            echo -e "${GREEN}✓ libstdc++6更新成功${NC}"
            return 0
        else
            echo -e "${RED}× libstdc++6更新失败${NC}"
            echo -e "${YELLOW}将继续安装过程，但可能影响某些运行时功能${NC}"
            return 1
        fi
    else
        echo -e "${RED}× 无法安装add-apt-repository工具，跳过libstdc++6更新${NC}"
        echo -e "${YELLOW}将继续安装过程，但可能影响某些运行时功能${NC}"
        return 1
    fi
}

# 13. 安装libstdcxx-ng
install_libstdcxx_ng() {
    echo -e "${BLUE}[步骤 13] 安装libstdcxx-ng${NC}"
    if retry_command_with_logging "conda install -c conda-forge libstdcxx-ng -y" 300; then
        echo -e "${GREEN}✓ libstdcxx-ng安装成功${NC}"
        return 0
    else
        echo -e "${RED}× libstdcxx-ng安装失败${NC}"
        echo -e "${YELLOW}将继续安装过程，但可能影响某些运行时功能${NC}"
        return 1
    fi
}

# 14. 检测版本信息
check_versions() {
    echo -e "${BLUE}[步骤 14] 检测版本信息${NC}"
    
    # 确保在仓库目录中
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}× 目录 $INSTALL_DIR 不存在${NC}"
        return 1
    fi
    
    cd "$INSTALL_DIR" || {
        echo -e "${RED}× 无法进入 $INSTALL_DIR 目录${NC}"
        return 1
    }
    
    echo -e "${YELLOW}检测ktransformers版本...${NC}"
    python -c "import ktransformers; print('ktransformers版本:', ktransformers.__version__)" || echo "无法获取ktransformers版本"
    
    echo -e "${YELLOW}检测flashinfer版本...${NC}"
    python -c "import flashinfer; print('flashinfer版本:', flashinfer.__version__)" || echo "无法获取flashinfer版本"
    
    echo -e "${YELLOW}检测CUDA版本...${NC}"
    nvcc --version || echo "无法获取CUDA版本"
    
    echo -e "${YELLOW}检测PyTorch版本及CUDA是否可用...${NC}"
    python -c "import torch; print('PyTorch版本:', torch.__version__); print('CUDA是否可用:', torch.cuda.is_available()); print('CUDA版本:', torch.version.cuda if torch.cuda.is_available() else 'N/A')" || echo "无法获取PyTorch信息"
    
    echo -e "${GREEN}✓ 版本信息检测完成${NC}"
}

# 5. 激活环境并进入仓库 - 增强版，添加修复功能
activate_conda_env() {
    echo -e "${BLUE}[步骤 5] 激活conda环境 $ENV_NAME 并进入仓库${NC}"
    
    # 创建不带颜色代码的激活脚本
    cat > activate_env.sh << EOF
#!/bin/bash
# 添加conda到PATH
export PATH="\$HOME/miniconda3/bin:\$PATH"
# 对root用户，可能需要不同的路径
if [ "\$(id -u)" -eq 0 ]; then
    non_root_user=\$(who | awk '{print \$1}' | head -n 1)
    if [ -n "\$non_root_user" ]; then
        export PATH="/home/\$non_root_user/miniconda3/bin:\$PATH"
    fi
fi

# 初始化conda
if [ -f "\$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    . "\$HOME/miniconda3/etc/profile.d/conda.sh"
elif [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
    . "/opt/conda/etc/profile.d/conda.sh"
elif [ -f "/home/oak/miniconda3/etc/profile.d/conda.sh" ]; then
    . "/home/oak/miniconda3/etc/profile.d/conda.sh"
else
    echo "conda.sh not found, conda may not be properly installed"
    exit 1
fi

# 激活环境
conda activate $ENV_NAME

# 切换到安装目录
cd "$INSTALL_DIR"

# 设置USE_NUMA环境变量
export USE_NUMA=1

# 显示当前环境信息
echo "当前环境: \$(conda info --envs | grep '*' || echo '未激活任何环境')"
echo "Python: \$(which python || echo '未找到Python')"
echo "当前目录: \$(pwd)"
EOF
    
    chmod +x activate_env.sh
    
    # 激活conda环境 - 尝试多种方式
    local activation_success=false
    
    # 方法1: 使用conda.sh
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        echo -e "${YELLOW}尝试使用conda.sh激活环境...${NC}"
        . "$HOME/miniconda3/etc/profile.d/conda.sh"
        if conda activate $ENV_NAME 2>/dev/null; then
            activation_success=true
            echo -e "${GREEN}✓ 成功激活环境 $ENV_NAME${NC}"
        fi
    fi
    
    # 方法2: 如果是root用户，尝试其他可能的conda.sh位置
    if [ "$(id -u)" -eq 0 ] && [ "$activation_success" = false ]; then
        local non_root_user=$(who | awk '{print $1}' | head -n 1)
        if [ -n "$non_root_user" ] && [ -f "/home/$non_root_user/miniconda3/etc/profile.d/conda.sh" ]; then
            echo -e "${YELLOW}尝试使用非root用户的conda.sh激活环境...${NC}"
            . "/home/$non_root_user/miniconda3/etc/profile.d/conda.sh"
            if conda activate $ENV_NAME 2>/dev/null; then
                activation_success=true
                echo -e "${GREEN}✓ 成功激活环境 $ENV_NAME${NC}"
            fi
        fi
    fi
    
    # 方法3: 尝试oak用户的conda.sh位置
    if [ "$activation_success" = false ] && [ -f "/home/oak/miniconda3/etc/profile.d/conda.sh" ]; then
        echo -e "${YELLOW}尝试使用oak用户的conda.sh激活环境...${NC}"
        . "/home/oak/miniconda3/etc/profile.d/conda.sh"
        if conda activate $ENV_NAME 2>/dev/null; then
            activation_success=true
            echo -e "${GREEN}✓ 成功激活环境 $ENV_NAME${NC}"
        fi
    fi
    
    # 方法4: 尝试直接使用conda命令
    if [ "$activation_success" = false ] && command_exists conda; then
        echo -e "${YELLOW}尝试直接使用conda命令激活环境...${NC}"
        conda activate $ENV_NAME 2>/dev/null
        if [ $? -eq 0 ]; then
            activation_success=true
            echo -e "${GREEN}✓ 成功激活环境 $ENV_NAME${NC}"
        fi
    fi
    
    # 如果所有方法都失败
    if [ "$activation_success" = false ]; then
        echo -e "${YELLOW}无法激活环境 $ENV_NAME，尝试修复...${NC}"
        
        # 尝试修复conda初始化
        if command_exists conda; then
            echo -e "${YELLOW}重新初始化conda...${NC}"
            conda init bash
            
            # 重新加载shell环境
            if [ -f "$HOME/.bashrc" ]; then
                echo -e "${YELLOW}重新加载shell环境...${NC}"
                . "$HOME/.bashrc"
                
                # 再次尝试激活
                if conda activate $ENV_NAME 2>/dev/null; then
                    activation_success=true
                    echo -e "${GREEN}✓ 修复后成功激活环境 $ENV_NAME${NC}"
                else
                    echo -e "${YELLOW}修复后仍无法激活环境，继续执行脚本...${NC}"
                    echo -e "${YELLOW}您可以稍后使用 'source activate_env.sh' 手动激活环境${NC}"
                fi
            else
                echo -e "${YELLOW}找不到.bashrc文件，无法重新加载环境${NC}"
            fi
        else
            echo -e "${RED}× 找不到conda命令，无法修复${NC}"
        fi
    fi
    
    # 切换到安装目录
    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR" || echo -e "${RED}切换到 $INSTALL_DIR 失败${NC}"
    else
        echo -e "${RED}目录 $INSTALL_DIR 不存在${NC}"
    fi
    
    echo -e "${GREEN}✓ 已创建激活脚本并尝试进入仓库目录${NC}"
    
    # 如果无法激活，提示用户
    if [ "$activation_success" = false ]; then
        echo -e "${YELLOW}提示: 安装完成后，请执行以下命令激活环境:${NC}"
        echo -e "${BLUE}source $(pwd)/activate_env.sh${NC}"
    fi
    
    return 0
}

# 修改的工具函数：估算git子模块的大小和进度
estimate_git_repo_size() {
    local repo_url="$1"
    local temp_file=$(mktemp)
    
    # 使用git ls-remote获取仓库引用信息
    timeout 30 git ls-remote --heads --tags "$repo_url" > "$temp_file" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        rm -f "$temp_file"
        echo "0" # 无法获取信息，返回0
        return
    fi
    
    # 计算大致大小：每个引用计算为2MB的估计大小
    local ref_count=$(wc -l < "$temp_file")
    local estimated_size=$((ref_count * 2))
    
    rm -f "$temp_file"
    
    # 返回估计大小（MB）
    echo "$estimated_size"
}

# 改进的git子模块更新进度条
update_git_submodules_with_progress() {
    echo -e "${YELLOW}正在更新git子模块，这可能需要一些时间...${NC}"
    
    # 创建临时输出文件
    local output_file=$(mktemp)
    
    # 启动git命令并将输出重定向到临时文件和终端
    git submodule update --init --recursive --progress 2>&1 | tee "$output_file"
    local update_result=$?
    
    # 检查更新结果
    if [ $update_result -eq 0 ]; then
        echo -e "${GREEN}✓ git子模块克隆和更新成功${NC}"
        rm -f "$output_file"  # 清理临时文件
        return 0
    else
        echo -e "${RED}× git子模块更新失败 (错误码: $update_result)${NC}"
        
        # 显示错误信息
        if [ $DEBUG_MODE -eq 1 ]; then
            echo -e "${YELLOW}错误输出:${NC}"
            tail -n 10 "$output_file"
            echo -e "${YELLOW}(完整输出已记录到日志)${NC}"
            cat "$output_file" >> "$LOG_FILE"
        fi
        
        echo -e "${YELLOW}尝试使用--jobs=4参数并行更新子模块...${NC}"
        
        # 并行更新子模块
        git submodule update --init --recursive --jobs=4
        update_result=$?
        
        if [ $update_result -eq 0 ]; then
            echo -e "${GREEN}✓ git子模块并行更新成功${NC}"
            rm -f "$output_file"  # 清理临时文件
            return 0
        else
            echo -e "${RED}× git子模块更新失败（错误码: $update_result），将继续安装流程${NC}"
            echo -e "${YELLOW}您可能需要在安装完成后手动更新子模块${NC}"
            rm -f "$output_file"  # 清理临时文件
            return $update_result
        fi
    fi
}

# 主函数
main() {
    echo -e "${BLUE}===== KTransformers 安装脚本 =====${NC}"
    
    # 提示调试模式
    prompt_debug_mode
    
    # 设置日志文件
    setup_log_file
    
    # 在调试模式下收集系统信息
    if [ $DEBUG_MODE -eq 1 ]; then
        collect_system_info
    fi
    
    # 显示安装脚本版本信息
    echo -e "${PURPLE}KTransformers 安装脚本 - 调试增强版${NC}"
    echo -e "${PURPLE}当前时间: $(date)${NC}\n"
    
    # 检查并安装必要的工具
    check_required_tools
    
    # 检查并设置pip源
    check_and_set_pip_mirror
    
    # 检查并安装构建工具
    check_build_tools
    
    # 检测CUDA版本 (只检测CUDA，不检测PyTorch)
    detect_pytorch_cuda_version
    
    # 用于跟踪安装状态的变量
    local install_status=0
    
    # 执行各个步骤
    check_root || exit 1
    install_git || exit 1
    clone_repository || { echo -e "${RED}仓库克隆失败，无法继续安装${NC}"; exit 1; }
    install_conda || { echo -e "${RED}Conda安装失败，无法继续安装${NC}"; exit 1; }
    create_conda_env || { echo -e "${RED}Conda环境创建失败，无法继续安装${NC}"; exit 1; }
    
    # 激活环境
    activate_conda_env || install_status=1
    
    # 初始化Git子模块
    init_git_submodules || install_status=1
    
    # 安装libnuma和设置环境变量
    install_libnuma || install_status=1
    set_use_numa
    
    # 安装PyTorch (GPU版本)
    install_pytorch || install_status=1
    
    # 安装flashinfer
    download_flashinfer || install_status=1
    
    # 编译安装KTransformers
    make_dev_install || install_status=1
    
    # 安装其他依赖
    update_libstdcpp6 || install_status=1
    install_libstdcxx_ng || install_status=1
    
    # 检查安装的版本
    check_versions
    
    # 创建安装报告
    echo -e "\n${BLUE}===== KTransformers 安装报告 =====${NC}"
    echo -e "安装目录: ${GREEN}$INSTALL_DIR${NC}"
    echo -e "Conda环境: ${GREEN}$ENV_NAME${NC}"
    echo -e "Git镜像站点: ${GREEN}$BEST_GITHUB_SITE${NC}"
    
    # 显示CUDA和PyTorch版本信息
    if [ -n "$TORCH_VERSION" ]; then
        echo -e "PyTorch版本: ${GREEN}$TORCH_VERSION${NC}"
    else
        echo -e "PyTorch版本: ${YELLOW}未检测到${NC}"
    fi
    
    if [ -n "$CUDA_VERSION" ]; then
        echo -e "CUDA版本: ${GREEN}$CUDA_VERSION${NC}"
    else
        echo -e "CUDA版本: ${YELLOW}未检测到${NC}"
    fi
    
    # 检查是否有Flashinfer
    if python -c "import flashinfer" &>/dev/null; then
        local flashinfer_version=$(python -c "import flashinfer; print(flashinfer.__version__)" 2>/dev/null)
        echo -e "Flashinfer版本: ${GREEN}${flashinfer_version:-已安装}${NC}"
    else
        echo -e "Flashinfer版本: ${RED}未安装或无法导入${NC}"
    fi
    
    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "调试日志: ${GREEN}$LOG_FILE${NC}"
        if [ -f "$INSTALL_DIR/make_error.log" ]; then
            echo -e "编译日志: ${GREEN}$INSTALL_DIR/make_error.log${NC}"
        fi
    fi
    
    if [ $install_status -eq 0 ]; then
        echo -e "${GREEN}✓ 所有组件安装成功${NC}"
        echo -e "${GREEN}===== KTransformers 安装完成! =====${NC}"
    else
        echo -e "${YELLOW}⚠ 部分组件安装失败或可能不完整${NC}"
        echo -e "${YELLOW}===== KTransformers 安装基本完成，但有部分组件可能需要手动处理 =====${NC}"
    fi
    
    echo -e "\n${YELLOW}要使用KTransformers，请运行:${NC}"
    echo -e "${BLUE}source $(pwd)/activate_env.sh${NC}"
    echo -e "${YELLOW}注意：首次使用可能需要重新打开终端或执行 source ~/.bashrc${NC}"
    
    if [ $install_status -ne 0 ]; then
        echo -e "\n${YELLOW}▶ 可能需要手动处理的问题:${NC}"
        if ! command_exists make; then
            echo -e "${YELLOW}  - 安装make: ${NC}apt-get install -y build-essential"
        fi
        if ! python -c "import flashinfer" &>/dev/null; then
            echo -e "${YELLOW}  - 安装flashinfer: ${NC}pip install flashinfer-python -f https://flashinfer.ai/whl/${FORMATTED_CUDA_VERSION}/${FORMATTED_TORCH_VERSION}"
            echo -e "${YELLOW}    或从源码安装: ${NC}git clone https://github.com/flashinfer-ai/flashinfer.git --recursive && cd flashinfer && pip install -e . -v"
        fi
        if ! python -c "import torch" &>/dev/null; then
            echo -e "${YELLOW}  - 安装PyTorch: ${NC}pip install torch torchvision torchaudio -f https://download.pytorch.org/whl/${FORMATTED_CUDA_VERSION}"
        fi
    fi
    
    # 在调试模式下添加额外的总结信息
    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "\n${CYAN}[调试] 安装过程总结:${NC}"
        echo -e "${CYAN}[调试] - 安装脚本执行时间: $(date)${NC}"
        echo -e "${CYAN}[调试] - 详细日志已保存到: $LOG_FILE${NC}"
        
        # 显示环境变量信息
        echo -e "${CYAN}[调试] - PATH环境变量:${NC}"
        echo -e "${CYAN}  $PATH${NC}" | tr ':' '\n' | sed 's/^/  /'
        
        if command_exists nvcc; then
            echo -e "${CYAN}[调试] - NVCC路径: $(which nvcc)${NC}"
            echo -e "${CYAN}[调试] - NVCC版本:${NC}"
            nvcc -V | sed 's/^/  /'
        else
            echo -e "${CYAN}[调试] - NVCC未找到${NC}"
        fi
        
        # 检查GPU是否可用
        if python -c "import torch; print('CUDA可用:' if torch.cuda.is_available() else 'CUDA不可用:')" 2>/dev/null; then
            echo -e "${CYAN}[调试] - $(python -c "import torch; print('CUDA可用' if torch.cuda.is_available() else 'CUDA不可用')")${NC}"
            if python -c "import torch; exit(0 if torch.cuda.is_available() else 1)" &>/dev/null; then
                echo -e "${CYAN}[调试] - 可用GPU: $(python -c "import torch; print(torch.cuda.get_device_name(0))" 2>/dev/null)${NC}"
            fi
        fi
        
        echo -e "${CYAN}[调试] - 如遇问题，请查看日志文件获取详细信息${NC}"
    fi
}

# 运行主函数
main

