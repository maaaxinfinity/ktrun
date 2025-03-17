#!/bin/bash

# 脚本版本信息
# 最后更新: 2025-03-16
# 版本: 1.0.1
# 作者: Limitee

# =====================================================
# KTransformers 安装脚本
# 
# 命令行选项:
#   -d, --debug           启用调试模式，记录详细日志
#   -f, --fast            快速模式，使用默认配置无需用户确认
#   -g, --git-debug       启用git详细日志输出（需要与-d一起使用）
#   -h, --help            显示帮助信息
# 
# 示例:
#   ./run.sh              正常安装
#   ./run.sh -d           启用调试模式安装
#   ./run.sh -f           快速模式安装（使用默认参数）
#   ./run.sh -d -g        启用调试模式和git详细日志
# =====================================================

# 显示帮助信息的函数
show_help() {
    echo "KTransformers 安装脚本"
    echo ""
    echo "用法: ./run.sh [选项]"
    echo ""
    echo "选项:"
    echo "  -d, --debug           启用调试模式，记录详细日志"
    echo "  -f, --fast            快速模式，使用默认配置无需用户确认"
    echo "  -g, --git-debug       启用git详细日志输出（需要与-d一起使用）"
    echo "  -h, --help            显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  ./run.sh              正常安装"
    echo "  ./run.sh -d           启用调试模式安装"
    echo "  ./run.sh -f           快速模式安装（使用默认参数）"
    echo "  ./run.sh -d -g        启用调试模式和git详细日志"
    echo ""
    exit 0
}

# 处理命令行参数
process_args() {
    for arg in "$@"; do
        case $arg in
            -h|--help)
                show_help
                ;;
            -d|--debug)
                DEBUG_MODE=1
                ;;
            -f|--fast)
                FAST_MODE=1
                ;;
            -g|--git-debug)
                GIT_DEBUG_MODE=1
                ;;
            *)
                ;;
        esac
    done
}

# 调用参数处理函数
process_args "$@"

# 安装前创建必要的临时目录和文件
TMP_DIR="/tmp/ktransformers_tmp_$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

# 处理sudo环境下的PATH保留问题
if [ "$(id -u)" -eq 0 ]; then

    if [ -n "$SUDO_USER" ]; then

        REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        REAL_USER="$SUDO_USER"
        

        if [ -f "$REAL_HOME/.bashrc" ]; then
            echo "检测到sudo环境，尝试保留原用户环境变量..."

            ORIGINAL_PATH=$(sudo -u "$SUDO_USER" bash -c 'echo $PATH')
            if [ -n "$ORIGINAL_PATH" ]; then
                export PATH="$ORIGINAL_PATH:$PATH"
                echo "已合并原用户PATH: $ORIGINAL_PATH"
            fi
        fi
        

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
        

        NVCC_PATH=$(sudo -u "$SUDO_USER" which nvcc 2>/dev/null)
        if [ -n "$NVCC_PATH" ]; then
            NVCC_DIR=$(dirname "$NVCC_PATH")
            export PATH="$NVCC_DIR:$PATH"
            echo "已添加nvcc路径: $NVCC_DIR"
        fi
    fi
else

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
NC='\033[0m'

# 全局变量
BEST_GITHUB_SITE=""
REPO_URL=""
INSTALL_DIR="$(pwd)/workspace"  # 默认安装目录为当前目录
ENV_NAME="ktrans_main"  # 默认环境名称
DEBUG_MODE=0
GIT_DEBUG_MODE=0  # 控制git详细日志输出，默认禁用
LOG_FILE=""
USE_NUMA=0  # 默认禁用USE_NUMA环境变量
CUSTOM_PATH=""
MAX_JOBS=$(nproc)
FAST_MODE=0  # 默认禁用快速模式，允许用户修改配置
USE_GHPROXY=0  # 默认禁用ghproxy，通过IP检测自动判断
GHPROXY_URL=""  # ghproxy服务器URL
IS_PROXY_SITE=0  # 是否使用代理站点

# 用户配置部分
configure_installation() {

    echo -e "${BLUE}"
    echo -e "   __ ____                    ___                         "
    echo -e "  / //_/ /________ ____  ___ / _/__   ______ _  ___ _______"
    echo -e " / ,< / __/ __/ _ \`/ _ \(_-</ _/ _ \/ __/  ' \/ -_) __(_-<"
    echo -e "/_/|_|\__/_/  \_,_/_//_/___/_/ \___/_/ /_/_/_/\__/_/ /___/"
    echo -e " +------------------------------------------------------+"
    echo -e "${NC}\n"
    

    if [ $FAST_MODE -eq 1 ]; then
        echo -e "${BLUE}===== 快速模式 - 使用默认配置 =====${NC}"
    else
        echo -e "${BLUE}===== KTransformers 安装配置 =====${NC}"
    fi
    

    local gpu_info="未检测到NVIDIA GPU"
    local cuda_info="未检测到CUDA"
    

    if command -v nvidia-smi &>/dev/null; then
        gpu_info=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n 1)
        if [ -z "$gpu_info" ]; then
            gpu_info="检测到NVIDIA驱动，但未找到GPU设备"
        fi
        

        if command -v nvcc &>/dev/null; then
            cuda_info=$(nvcc --version | grep "release" | awk '{print $6}' | cut -d',' -f1)
            if [ -n "$cuda_info" ]; then
                cuda_info="CUDA $cuda_info"
            else
                cuda_info="已安装CUDA，但无法获取版本"
            fi
        fi
    fi
    

    if [ $FAST_MODE -eq 1 ]; then
        echo -e "\n${YELLOW}快速模式：使用默认配置，跳过参数修改${NC}"
    else
        echo -e "\n${BLUE}配置安装参数${NC}"
        

        echo -e "${YELLOW}请输入安装路径 (默认: ${INSTALL_DIR}):${NC}"
        read -r user_install_dir
        if [ -n "$user_install_dir" ]; then
            INSTALL_DIR="$user_install_dir"
            echo -e "${GREEN}✓ 安装路径已更新为: ${INSTALL_DIR}${NC}"
        fi
        

        echo -e "${YELLOW}请输入Conda环境名称 (默认: ${ENV_NAME}):${NC}"
        read -r user_env_name
        if [ -n "$user_env_name" ]; then
            ENV_NAME="$user_env_name"
            echo -e "${GREEN}✓ Conda环境名称已更新为: ${ENV_NAME}${NC}"
        fi
        

        echo -e "${YELLOW}是否启用USE_NUMA环境变量? [y/N]:${NC}"
        read -r use_numa_option
        if [[ "$use_numa_option" =~ ^[Yy]$ ]]; then
            USE_NUMA=1
            echo -e "${GREEN}✓ 已启用USE_NUMA环境变量${NC}"
        else
            USE_NUMA=0
            echo -e "${GREEN}✓ 已禁用USE_NUMA环境变量${NC}"
        fi
        

        echo -e "${YELLOW}请输入编译最大线程数 (默认: ${MAX_JOBS}):${NC}"
        read -r user_max_jobs
        if [ -n "$user_max_jobs" ] && [ "$user_max_jobs" -gt 0 ] 2>/dev/null; then
            MAX_JOBS="$user_max_jobs"
            echo -e "${GREEN}✓ 编译最大线程数已更新为: ${MAX_JOBS}${NC}"
        fi
        

        echo -e "${YELLOW}是否启用调试模式? [y/N]:${NC}"
        read -r debug_option
        if [[ "$debug_option" =~ ^[Yy]$ ]]; then
            DEBUG_MODE=1
            echo -e "${GREEN}✓ 已启用调试模式${NC}"
        else
            DEBUG_MODE=0
            echo -e "${GREEN}✓ 已禁用调试模式${NC}"
        fi
    fi
    

    echo -e "\n${BLUE}=== 安装配置摘要 ===${NC}"
    echo -e "${BLUE}● 安装路径: ${GREEN}${INSTALL_DIR}${NC}"
    echo -e "${BLUE}● Conda环境: ${GREEN}${ENV_NAME}${NC}"
    echo -e "${BLUE}● GPU设备: ${GREEN}${gpu_info}${NC}"
    echo -e "${BLUE}● CUDA版本: ${GREEN}${cuda_info}${NC}"
    echo -e "${BLUE}● USE_NUMA: ${GREEN}$([ $USE_NUMA -eq 1 ] && echo "启用" || echo "禁用")${NC}"
    echo -e "${BLUE}● 编译线程: ${GREEN}${MAX_JOBS}${NC}"
    echo -e "${BLUE}● 调试模式: ${GREEN}$([ $DEBUG_MODE -eq 1 ] && echo "启用" || echo "禁用")${NC}"
    echo -e "${BLUE}● 运行模式: ${GREEN}$([ $FAST_MODE -eq 1 ] && echo "快速模式" || echo "标准模式")${NC}"
    echo -e "${BLUE}● 网络检测: ${GREEN}IP检测与镜像站点自动选择${NC}"
    

    if [ $FAST_MODE -eq 0 ]; then
        echo -e "\n${GREEN}✓ 配置已确认，3秒后开始安装...${NC}"
        sleep 3
    else
        echo -e "\n${GREEN}✓ 使用默认配置，开始安装...${NC}"
    fi
    

    clear
}

# 日志函数
log() {
    local level=$1
    local message=$2
    local color=""
    local prefix=""
    
    case $level in
        "DEBUG")
            color="$CYAN"
            prefix="[DEBUG]"
            # 只在调试模式下显示DEBUG级别日志
            if [ $DEBUG_MODE -eq 0 ]; then
                return 0
            fi
            ;;
        "INFO")
            color="$BLUE"
            prefix="[INFO]"
            ;;
        "SUCCESS")
            color="$GREEN"
            prefix="[SUCCESS]"
            ;;
        "WARN")
            color="$YELLOW"
            prefix="[WARN]"
            ;;
        "ERROR")
            color="$RED"
            prefix="[ERROR]"
            ;;
        "FATAL")
            color="$RED"
            prefix="[FATAL]"
            ;;
        *)
            color="$BLUE"
            prefix="[INFO]"
            ;;
    esac
    

    echo -e "${color}${prefix} ${message}${NC}"
    

    if [ -n "$LOG_FILE" ]; then
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] ${prefix} ${message}" >> "$LOG_FILE"
    fi
}

# 日志记录函数
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

    if [[ "$*" == *"-d"* ]] || [[ "$*" == *"--debug"* ]]; then
        DEBUG_MODE=1
        echo -e "${YELLOW}调试模式已启用${NC}"
    else
        echo -e "${BLUE}调试模式未启用 (使用 -d 或 --debug 参数可启用)${NC}"
    fi
}

# 函数：初始化日志文件
setup_log_file() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    LOG_FILE="ktransformers_install_${timestamp}.log"
    

    echo "===== KTransformers 安装日志 - $(date) =====" > "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    

    if [ $DEBUG_MODE -eq 1 ]; then
        echo "调试模式: 启用" >> "$LOG_FILE"
        echo -e "${CYAN}日志文件: ${LOG_FILE}${NC}"
    else
        echo "调试模式: 禁用" >> "$LOG_FILE"
    fi
    echo "" >> "$LOG_FILE"
    

    chmod 644 "$LOG_FILE"
    

    echo "[$(date +"%Y-%m-%d %H:%M:%S")] 日志文件初始化完成" >> "$LOG_FILE"
    

    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${CYAN}[调试] 日志文件已创建: ${LOG_FILE}${NC}"
        echo -e "${CYAN}[调试] 将记录详细安装过程${NC}"
    fi
}

# 函数：收集系统信息
collect_system_info() {
    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${CYAN}[调试] 正在收集系统信息...${NC}"
    fi
    
    echo "===== 系统信息 =====" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    

    echo "--- CPU信息 ---" >> "$LOG_FILE"
    if command -v lscpu &> /dev/null; then
        lscpu >> "$LOG_FILE"
    else
        echo "CPU型号: $(grep "model name" /proc/cpuinfo | head -n 1 | cut -d":" -f2 | sed 's/^[ \t]*//')" >> "$LOG_FILE"
        echo "CPU核心数: $(grep -c "processor" /proc/cpuinfo)" >> "$LOG_FILE"
    fi
    echo "" >> "$LOG_FILE"
    

    echo "--- 内存信息 ---" >> "$LOG_FILE"
    if command -v free &> /dev/null; then
        free -h >> "$LOG_FILE"
    fi
    echo "" >> "$LOG_FILE"
    

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
    

    echo "--- 系统信息 ---" >> "$LOG_FILE"
    if command -v lsb_release &> /dev/null; then
        lsb_release -a >> "$LOG_FILE" 2>&1
    elif [ -f /etc/os-release ]; then
        cat /etc/os-release >> "$LOG_FILE"
    fi
    echo "" >> "$LOG_FILE"
    

    echo "--- 内核信息 ---" >> "$LOG_FILE"
    uname -a >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    

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


command_exists() {
    command -v "$1" &> /dev/null
}


retry_command_with_logging() {
    local command="$1"
    local max_attempts=3
    local attempt=1
    local timeout_duration="${2:-300}"
    
    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${CYAN}[调试] 命令: $command${NC}"
        echo -e "${CYAN}[调试] 最大尝试次数: $max_attempts, 超时: ${timeout_duration}秒${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] 执行命令: $command (最大尝试次数: $max_attempts, 超时: ${timeout_duration}秒)" >> "$LOG_FILE"
    fi
    
    while [ $attempt -le $max_attempts ]; do
        echo -e "${BLUE}尝试执行命令 (尝试 $attempt/$max_attempts): ${NC}$command"
        

        if [ $DEBUG_MODE -eq 1 ]; then
            local start_time=$(date +%s)
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] 开始尝试 #$attempt: $command" >> "$LOG_FILE"
        fi
        

        local output
        output=$(timeout $timeout_duration bash -c "$command" 2>&1)
        local exit_code=$?
        

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

# 进度条函数
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

# 检测是否为超级用户
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

# 检查并安装必要的工具
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

            echo -e "${CYAN}[调试] $tool 已安装: $(which $tool)${NC}"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] $tool 已安装: $(which $tool)" >> "$LOG_FILE"
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${YELLOW}正在安装缺少的工具...${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] 正在安装缺少的工具: ${missing_tools[*]}" >> "$LOG_FILE"
        

        if [ $DEBUG_MODE -eq 1 ]; then
            echo -e "${CYAN}[调试] 更新软件包列表${NC}"
        fi
        
        if ! DEBIAN_FRONTEND=noninteractive apt-get update -y; then
            echo -e "${RED}更新包管理器失败${NC}"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] 更新包管理器失败" >> "$LOG_FILE"
            return 1
        fi
        

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
            log "WARN" "缺少构建工具: $tool"
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log "INFO" "正在安装缺少的构建工具..."
        

        if ! DEBIAN_FRONTEND=noninteractive apt-get update -y; then
            log "ERROR" "更新包管理器失败"
            return 1
        fi
        

        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common; then
            log "ERROR" "安装software-properties-common失败"
            log "WARN" "继续尝试安装其他工具"
        fi
        

        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential cmake; then
            log "ERROR" "安装build-essential和cmake失败"
            log "WARN" "继续尝试安装其他工具"
        fi
        

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
            log "WARN" "部分构建工具安装失败，可能影响后续步骤"

        else
            log "SUCCESS" "所有构建工具安装完成"
        fi
    else
        log "SUCCESS" "所有构建工具已安装"
    fi
    
    return 0
}

# 1. 检测git
install_git() {
    log "INFO" "[步骤 1] 检测git"
    
    if command_exists git; then
        log "SUCCESS" "git已安装"
    else
        log "WARN" "git未安装，正在安装..."
        
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

# 1.5 测试GitHub连通性
test_github_connectivity() {
    log "INFO" "测试GitHub连通性"
    

    IS_PROXY_SITE=0
    USE_GHPROXY=0
    

    if is_china_ip; then
        log "INFO" "检测到中国IP，使用ghfast.top代理服务"
        USE_GHPROXY=1
        BEST_GITHUB_SITE="github.com"
        GHPROXY_URL="https://ghfast.top"
        log "SUCCESS" "已配置使用ghfast.top代理服务: $GHPROXY_URL"
        export GHPROXY_URL
        export USE_GHPROXY
    else
        log "INFO" "检测到非中国IP，将直接使用GitHub"
        BEST_GITHUB_SITE="github.com"
        USE_GHPROXY=0
    fi
    
    return 0
}

# 2. 拉取仓库
clone_repository() {
    log "INFO" "克隆KTransformers仓库到 $INSTALL_DIR"
    

    mkdir -p "$INSTALL_DIR" 2>/dev/null
    if [ $? -ne 0 ]; then
        log "ERROR" "无法创建目录 $INSTALL_DIR，请检查权限"
        return 1
    fi
    

    if [ ! -w "$INSTALL_DIR" ]; then
        log "ERROR" "目录 $INSTALL_DIR 没有写入权限，请检查权限设置"
        return 1
    fi
    

    if [ -d "$INSTALL_DIR" ] && [ "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
        if [ $FAST_MODE -eq 0 ]; then
            log "WARN" "目录 $INSTALL_DIR 已存在且不为空"
            read -p "是否继续安装? 这可能会覆盖现有文件 [y/N]: " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "ERROR" "安装已取消"
                exit 1
            fi
        else
            log "WARN" "目录 $INSTALL_DIR 已存在且不为空，快速模式下将继续安装"
        fi
    fi
    

    local repo_url="https://github.com/kvcache-ai/ktransformers.git"
    

    if [ $USE_GHPROXY -eq 1 ]; then

        log "INFO" "使用ghfast.top代理克隆仓库"
        repo_url="${GHPROXY_URL}/https://github.com/kvcache-ai/ktransformers.git"
    elif [ $IS_PROXY_SITE -eq 1 ]; then

        log "INFO" "选择了代理站点 $BEST_GITHUB_SITE，使用代理克隆"
        repo_url="https://${BEST_GITHUB_SITE}/https://github.com/kvcache-ai/ktransformers.git"

        repo_url="https://${BEST_GITHUB_SITE}/kvcache-ai/ktransformers.git"
        log "INFO" "使用镜像站点URL: $repo_url"
    fi
    
    log "DEBUG" "使用仓库URL: $repo_url"
    

    local tmp_log=$(mktemp)
    log "INFO" "开始克隆仓库..."
    

    git clone "$repo_url" "$INSTALL_DIR" --progress 2>&1 | tee "$tmp_log" | grep --line-buffered -i "Receiving objects\|Resolving deltas"
    local exit_code=${PIPESTATUS[0]}
    

    if [ $exit_code -eq 0 ] && [ -d "$INSTALL_DIR/.git" ]; then
        log "SUCCESS" "仓库克隆成功"
        rm -f "$tmp_log"
        return 0
    else
        log "ERROR" "仓库克隆失败 (错误码: $exit_code)"
        log "DEBUG" "克隆错误详情:"
        cat "$tmp_log" | tail -n 20
        

        if grep -q "timeout\|timed out\|connection refused\|network" "$tmp_log"; then
            log "WARN" "检测到网络问题，尝试使用备用方法..."
            

            if [ $USE_GHPROXY -eq 1 ]; then

                if [[ "$GHPROXY_URL" == "https://ghfast.top" ]]; then

                    local other_proxies=(
                        "https://ghproxy.homeboyc.cn"
                        "https://mirror.ghproxy.com"
                        "https://ghproxy.net"
                        "https://gh.api.99988866.xyz"
                    )
                    
                    for proxy in "${other_proxies[@]}"; do
                        log "INFO" "尝试使用代理 $proxy 克隆..."
                        if git clone "${proxy}/https://github.com/kvcache-ai/ktransformers.git" "$INSTALL_DIR" --progress; then
                            log "SUCCESS" "使用代理 $proxy 克隆成功"
                            rm -f "$tmp_log"
                            return 0
                        fi
                    done
                fi
                

                log "INFO" "所有代理都失败，尝试直接从GitHub克隆..."
                if git clone "https://github.com/kvcache-ai/ktransformers.git" "$INSTALL_DIR" --progress; then
                    log "SUCCESS" "使用直接连接克隆成功"
                    rm -f "$tmp_log"
                    return 0
                fi

            elif [ $USE_GHPROXY -eq 0 ]; then
                log "INFO" "尝试使用ghfast.top代理克隆..."
                if git clone "https://ghfast.top/https://github.com/kvcache-ai/ktransformers.git" "$INSTALL_DIR" --progress; then
                    log "SUCCESS" "使用ghfast.top代理克隆成功"
                    rm -f "$tmp_log"
                    return 0
                fi
            fi
        fi
        
        rm -f "$tmp_log"
        return 1
    fi
}

# 3. 检测conda
install_conda() {
    echo -e "${BLUE}[步骤 3] 检测conda${NC}"
    

    if command_exists conda; then
        echo -e "${GREEN}✓ conda已安装: $(which conda)${NC}"
        if [ $DEBUG_MODE -eq 1 ]; then
            conda_version=$(conda --version)
            echo -e "${CYAN}[调试] conda版本: ${conda_version}${NC}"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] conda已安装: $(which conda), 版本: ${conda_version}" >> "$LOG_FILE"
        fi
        return 0
    fi
    

    local possible_conda_paths=(
        "$HOME/miniconda3/bin/conda"
        "$HOME/anaconda3/bin/conda"
        "~/miniconda3/bin/conda"
        "/opt/conda/bin/conda"
    )
    

    for conda_path in "${possible_conda_paths[@]}"; do
        if [ -f "$conda_path" ]; then
            echo -e "${YELLOW}找到conda但未在PATH中: ${conda_path}${NC}"
            echo -e "${YELLOW}正在将conda添加到PATH...${NC}"
            

            local conda_dir=$(dirname $(dirname "$conda_path"))
            export PATH="${conda_dir}/bin:$PATH"
            

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
    

    retry_command_with_logging "wget https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh"
    

    if [ "$(id -u)" -eq 0 ]; then
        local non_root_user=$(who | awk '{print $1}' | head -n 1)
        if [ -z "$non_root_user" ]; then
            non_root_user="ktuser"
            useradd -m -s /bin/bash $non_root_user || echo -e "${YELLOW}用户 $non_root_user 已存在${NC}"
            echo -e "${YELLOW}已创建用户 $non_root_user 用于安装conda${NC}"
        fi
        echo -e "${YELLOW}将为用户 $non_root_user 安装conda${NC}"
        

        local miniconda_dir="/home/$non_root_user/miniconda3"
        if [ -d "$miniconda_dir" ]; then
            echo -e "${YELLOW}miniconda目录已存在: $miniconda_dir${NC}"
            echo -e "${YELLOW}尝试使用已有安装...${NC}"
            

            echo "export PATH=$miniconda_dir/bin:\$PATH" > /etc/profile.d/conda.sh
            chmod +x /etc/profile.d/conda.sh
            

            export PATH="$miniconda_dir/bin:$PATH"
            

            if command_exists conda; then
                echo -e "${GREEN}✓ conda设置成功${NC}"
                return 0
            else
                echo -e "${YELLOW}无法使用已有安装，尝试修复...${NC}"

                su - $non_root_user -c "bash /tmp/miniconda.sh -u -b -p $miniconda_dir"
            fi
        else

            su - $non_root_user -c "bash /tmp/miniconda.sh -b -p $miniconda_dir"
        fi
        

        echo "export PATH=$miniconda_dir/bin:\$PATH" > /etc/profile.d/conda.sh
        chmod +x /etc/profile.d/conda.sh
        

        export PATH="$miniconda_dir/bin:$PATH"
        

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

        local miniconda_dir="$HOME/miniconda3"
        if [ -d "$miniconda_dir" ]; then
            echo -e "${YELLOW}miniconda目录已存在: $miniconda_dir${NC}"
            echo -e "${YELLOW}尝试使用已有安装...${NC}"
            

            export PATH="$miniconda_dir/bin:$PATH"
            

            if command_exists conda; then
                echo -e "${GREEN}✓ conda设置成功${NC}"
                

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

                bash /tmp/miniconda.sh -u -b -p $miniconda_dir
            fi
        else

            bash /tmp/miniconda.sh -b -p $miniconda_dir
        fi
        

        export PATH="$miniconda_dir/bin:$PATH"
        echo "export PATH=$miniconda_dir/bin:\$PATH" >> $HOME/.bashrc
        

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
    

    echo -e "${GREEN}使用环境名称: $ENV_NAME${NC}"
    
    retry_command_with_logging "conda create -n $ENV_NAME python=3.12 -y" 120
    echo -e "${GREEN}✓ conda环境 $ENV_NAME 创建成功${NC}"
}


check_and_set_pip_mirror() {
    echo -e "${BLUE}[准备工作] 检查pip源配置${NC}"
    

    local pip_config_file="$HOME/.pip/pip.conf"
    local is_china=false
    

    if command_exists curl; then

        local cn_delay=$(timeout 5 curl -s -o /dev/null -w "%{time_total}" https://www.baidu.com 2>/dev/null || echo "10")
        local global_delay=$(timeout 5 curl -s -o /dev/null -w "%{time_total}" https://www.google.com 2>/dev/null || echo "10")
        
        if (( $(echo "$cn_delay < $global_delay" | bc -l) )); then
            is_china=true
            echo -e "${YELLOW}检测到您可能位于中国大陆，建议使用国内镜像源${NC}"
        fi
    fi
    

    local current_index_url=""
    if [ -f "$pip_config_file" ]; then
        current_index_url=$(grep "index-url" "$pip_config_file" 2>/dev/null | cut -d "=" -f 2 | tr -d " ")
        
        if [ -n "$current_index_url" ]; then
            echo -e "${YELLOW}当前pip源: ${current_index_url}${NC}"
            

            if echo "$current_index_url" | grep -q -E "mirrors.ustc.edu.cn|tuna.tsinghua.edu.cn|mirrors.aliyun.com"; then
                echo -e "${GREEN}✓ 已配置国内pip源${NC}"
                return 0
            fi
        fi
    fi
    

    if [ "$is_china" = true ] || [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${YELLOW}准备设置pip源为USTC源...${NC}"
        

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

# CUDA检测函数
detect_pytorch_cuda_version() {
    echo -e "${BLUE}[准备工作] 检测CUDA环境${NC}"
    
    local cuda_version=""
    local nvcc_cuda_version=""
    local driver_version=""
    local estimated_cuda_version=""
    

    if command_exists nvidia-smi; then
        driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)
        echo -e "${GREEN}✓ 检测到NVIDIA驱动版本: ${driver_version}${NC}"
        

        case "${driver_version%%.*}" in
            "570") estimated_cuda_version="12.8" ;;  # >=570.124.06 (CUDA 12.8 Update 1) 和 >=570.117 (CUDA 12.8 GA)
            "560") estimated_cuda_version="12.6" ;;  # >=560.35.05 (CUDA 12.6 Update 3), >=560.35.03 (CUDA 12.6 Update 2/1), >=560.28.03 (CUDA 12.6 GA)
            "555") estimated_cuda_version="12.5" ;;  # >=555.42.06 (CUDA 12.5 Update 1), >=555.42.02 (CUDA 12.5 GA)
            "550") estimated_cuda_version="12.4" ;;  # >=550.54.15 (CUDA 12.4 Update 1), >=550.54.14 (CUDA 12.4 GA)
            "545") estimated_cuda_version="12.3" ;;  # >=545.23.08 (CUDA 12.3 Update 1), >=545.23.06 (CUDA 12.3 GA)
            "535") estimated_cuda_version="12.2" ;;  # >=535.104.05 (CUDA 12.2 Update 2), >=535.86.09 (CUDA 12.2 Update 1), >=535.54.03 (CUDA 12.2 GA)
            "530") estimated_cuda_version="12.1" ;;  # >=530.30.02 (CUDA 12.1 Update 1 和 CUDA 12.1 GA)
            "525") estimated_cuda_version="12.0" ;;  # >=525.85.12 (CUDA 12.0 Update 1), >=525.60.13 (CUDA 12.0 GA)
            "520") estimated_cuda_version="11.8" ;;  # >=520.61.05 (CUDA 11.8 GA)
            "495") estimated_cuda_version="11.5" ;;
            *) estimated_cuda_version="" ;;
        esac
        
        if [ -n "$estimated_cuda_version" ]; then
            echo -e "${GREEN}✓ 驱动版本${driver_version}对应的CUDA版本: ${estimated_cuda_version}${NC}"
        else
            echo -e "${YELLOW}警告: 无法根据驱动版本${driver_version}估计CUDA版本${NC}"
        fi
        

        if [ $DEBUG_MODE -eq 1 ]; then
            echo -e "${CYAN}[调试] GPU详细信息:${NC}"
            nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader | sed 's/^/  /'
        fi
    else
        echo -e "${YELLOW}警告: 未检测到NVIDIA GPU或无法运行nvidia-smi${NC}"
    fi
    

    local found_preferred_cuda=0
    local preferred_nvcc_path=""
    

    if [ -n "$estimated_cuda_version" ]; then
        local specific_cuda_path="/usr/local/cuda-${estimated_cuda_version}/bin/nvcc"
        local default_cuda_path="/usr/local/cuda/bin/nvcc"
        

        if [ -f "$specific_cuda_path" ]; then
            preferred_nvcc_path="$specific_cuda_path"
            found_preferred_cuda=1
            echo -e "${GREEN}✓ 找到与驱动匹配的CUDA ${estimated_cuda_version}: ${preferred_nvcc_path}${NC}"

        elif [ -f "$default_cuda_path" ]; then
            local default_version=$("$default_cuda_path" -V 2>&1 | grep "release" | awk '{print $6}' | sed 's/,//' | sed 's/V//')
            if [ "$default_version" = "$estimated_cuda_version" ]; then
                preferred_nvcc_path="$default_cuda_path"
                found_preferred_cuda=1
                echo -e "${GREEN}✓ 默认CUDA版本与驱动匹配: ${preferred_nvcc_path} (${default_version})${NC}"
            fi
        fi
    fi
    

    if [ $found_preferred_cuda -eq 1 ] && [ -n "$preferred_nvcc_path" ]; then
        local version_output=$("$preferred_nvcc_path" -V 2>/dev/null)
        if [ -n "$version_output" ]; then
            nvcc_cuda_version=$(echo "$version_output" | grep "release" | awk '{print $6}' | sed 's/,//' | sed 's/V//')
            echo -e "${GREEN}✓ 使用与驱动匹配的CUDA版本: ${nvcc_cuda_version}${NC}"
            

            local nvcc_dir=$(dirname "$preferred_nvcc_path")
            export PATH="${nvcc_dir}:$PATH"
            echo -e "${YELLOW}已将匹配的CUDA版本添加到PATH: ${nvcc_dir}${NC}"
            

            if [ $DEBUG_MODE -eq 1 ]; then
                echo -e "${CYAN}[调试] 设置与驱动匹配的CUDA版本: ${nvcc_cuda_version}${NC}"
                echo -e "${CYAN}[调试] CUDA路径: ${nvcc_dir}${NC}"
                echo -e "${CYAN}[调试] 当前PATH: $PATH${NC}"
            fi
        fi

    elif command_exists nvcc; then
        local nvcc_path=$(which nvcc)
        nvcc_cuda_version=$(nvcc -V | grep "release" | awk '{print $6}' | sed 's/,//' | sed 's/V//')
        

        if [ -n "$estimated_cuda_version" ] && [ "$nvcc_cuda_version" != "$estimated_cuda_version" ]; then
            echo -e "${YELLOW}警告: PATH中的CUDA版本(${nvcc_cuda_version})与驱动兼容的版本(${estimated_cuda_version})不匹配${NC}"
            echo -e "${YELLOW}推荐使用与驱动匹配的CUDA ${estimated_cuda_version}以获得最佳兼容性${NC}"
        fi
        
        echo -e "${GREEN}✓ 使用PATH中的CUDA版本: ${nvcc_cuda_version} (${nvcc_path})${NC}"
        

        if [ $DEBUG_MODE -eq 1 ]; then
            echo -e "${CYAN}[调试] CUDA详细信息:${NC}"
            nvcc -V | sed 's/^/  /'
            

            echo -e "${CYAN}[调试] 检查系统中的其他CUDA版本:${NC}"
            

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
            

            local found_other=0
            for cuda_dir in "${cuda_dirs[@]}"; do
                if [ -f "${cuda_dir}/bin/nvcc" ] && [ "${cuda_dir}/bin/nvcc" != "$nvcc_path" ]; then
                    local other_version=$("${cuda_dir}/bin/nvcc" -V 2>&1 | grep "release" | awk '{print $6}' | sed 's/,//' | sed 's/V//')
                    if [ -n "$other_version" ]; then
                        echo -e "${CYAN}[调试]   发现其他CUDA版本: ${other_version} (${cuda_dir}/bin/nvcc)${NC}"
                        found_other=1
                        

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
        

        if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
            echo -e "${YELLOW}检测到sudo环境，尝试在用户${SUDO_USER}的环境中查找nvcc...${NC}"
            local user_nvcc_path=$(sudo -u "$SUDO_USER" which nvcc 2>/dev/null)
            
            if [ -n "$user_nvcc_path" ]; then
                echo -e "${GREEN}✓ 在用户${SUDO_USER}环境中找到nvcc: ${user_nvcc_path}${NC}"
                

                local version_output=$(sudo -u "$SUDO_USER" nvcc -V 2>/dev/null || "$user_nvcc_path" -V 2>/dev/null)
                if [ -n "$version_output" ]; then
                    nvcc_cuda_version=$(echo "$version_output" | grep "release" | awk '{print $6}' | sed 's/,//' | sed 's/V//')
                    echo -e "${GREEN}✓ 检测到CUDA版本: ${nvcc_cuda_version}${NC}"
                    

                    if [ -n "$estimated_cuda_version" ] && [ "$nvcc_cuda_version" != "$estimated_cuda_version" ]; then
                        echo -e "${YELLOW}警告: 用户环境中的CUDA版本(${nvcc_cuda_version})与驱动兼容的版本(${estimated_cuda_version})不匹配${NC}"
                    fi
                    

                    local nvcc_dir=$(dirname "$user_nvcc_path")
                    echo -e "${YELLOW}添加${nvcc_dir}到PATH...${NC}"
                    export PATH="$nvcc_dir:$PATH"
                    

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
            

            exit 1
        fi
    fi
    

    cuda_version="$nvcc_cuda_version"
    

    local formatted_cuda_version=""
    if [ -n "$cuda_version" ]; then

        formatted_cuda_version="cu$(echo $cuda_version | sed 's/\.//')"
    else

        echo -e "${RED}[错误] 无法确定CUDA版本${NC}"
        exit 1
    fi
    

    if command_exists nvcc; then
        echo -e "${GREEN}✓ nvcc命令可用${NC}"
        if [ $DEBUG_MODE -eq 1 ]; then
            echo -e "${CYAN}[调试] nvcc路径: $(which nvcc)${NC}"
            echo -e "${CYAN}[调试] nvcc版本: $(nvcc -V | head -n1)${NC}"
        fi
    else

        echo -e "${RED}[错误] nvcc命令检测失败，环境可能已经改变${NC}"
        exit 1
    fi
    

    CUDA_VERSION="$cuda_version"
    FORMATTED_CUDA_VERSION="$formatted_cuda_version"
    
    echo -e "${BLUE}格式化的CUDA版本：${FORMATTED_CUDA_VERSION}${NC}"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] 检测到CUDA版本: ${CUDA_VERSION}, 格式化为${FORMATTED_CUDA_VERSION}" >> "$LOG_FILE"
    
    return 0
}

# 安装并验证PyTorch
install_pytorch() {
    echo -e "${BLUE}[步骤 9] 安装GPU版本PyTorch${NC}"
    
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
    

    local torch_version=""
    local install_success=false
    
    echo -e "${YELLOW}开始安装PyTorch GPU版本 (CUDA ${CUDA_VERSION})...${NC}"
    

    local cuda_major=$(echo "$CUDA_VERSION" | cut -d. -f1)
    local cuda_formatted="cu${cuda_major}$(echo "$CUDA_VERSION" | cut -d. -f2)"
    

    local pip_torch_cmd=""
    local torch_mirror=""
    

    local current_pip_index=$(pip config list | grep -o "index-url=.*" | cut -d= -f2 | tr -d "'")
    
    if [[ "$current_pip_index" == *"mirrors.ustc.edu.cn"* ]]; then
        echo -e "${YELLOW}检测到已配置中科大镜像源，将继续使用${NC}"
        torch_mirror="https://mirrors.ustc.edu.cn/pytorch/whl"
    elif [[ "$current_pip_index" == *"mirrors.tuna.tsinghua.edu.cn"* ]]; then
        echo -e "${YELLOW}检测到已配置清华镜像源，将继续使用${NC}"
        torch_mirror="https://mirrors.tuna.tsinghua.edu.cn/pytorch/whl"
    elif ping -c 1 mirrors.ustc.edu.cn &>/dev/null; then
        torch_mirror="https://mirrors.ustc.edu.cn/pytorch/whl"
        echo -e "${YELLOW}检测到国内网络环境，使用中科大镜像源${NC}"
    elif ping -c 1 mirrors.tuna.tsinghua.edu.cn &>/dev/null; then
        torch_mirror="https://mirrors.tuna.tsinghua.edu.cn/pytorch/whl"
        echo -e "${YELLOW}检测到国内网络环境，使用清华镜像源${NC}"
    else
        torch_mirror="https://download.pytorch.org/whl"
    fi
    

    pip_torch_cmd="pip install torch torchvision torchaudio -f ${torch_mirror}/cu${cuda_major}$(echo "$CUDA_VERSION" | cut -d. -f2)"
    

    echo -e "${CYAN}[命令] ${pip_torch_cmd}${NC}"
    if eval "$pip_torch_cmd"; then
        echo -e "${GREEN}✓ PyTorch通过pip安装成功${NC}"
        install_success=true
    else
        echo -e "${YELLOW}通过pip安装PyTorch失败，尝试通过conda安装...${NC}"
        

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
    

    if [ "$install_success" = true ]; then
        echo -e "${YELLOW}验证PyTorch和CUDA...${NC}"
        

        torch_version=$(python -c "import torch; print(torch.__version__.split('+')[0])" 2>/dev/null)
        if [ -n "$torch_version" ]; then
            echo -e "${GREEN}✓ PyTorch版本: ${torch_version}${NC}"
            TORCH_VERSION="$torch_version"
            

            FORMATTED_TORCH_VERSION="torch$(echo $torch_version | cut -d '.' -f 1,2)"
            echo -e "${BLUE}格式化的PyTorch版本：${FORMATTED_TORCH_VERSION}${NC}"
            

            if python -c "import torch; exit(0 if torch.cuda.is_available() else 1)" &>/dev/null; then
                local cuda_torch_version=$(python -c "import torch; print(torch.version.cuda)" 2>/dev/null)
                echo -e "${GREEN}✓ CUDA可用，PyTorch报告的CUDA版本: ${cuda_torch_version}${NC}"
                

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

# 6. 初始化git子模块
init_git_submodules() {
    log "INFO" "初始化git子模块"
    

    cd "$INSTALL_DIR" || {
        log "ERROR" "无法进入安装目录 $INSTALL_DIR"
        return 1
    }
    

    if [ $USE_GHPROXY -eq 1 ]; then
        log "INFO" "使用ghfast.top代理加速子模块克隆"
        

        if [ -f ".gitmodules" ]; then
            log "INFO" "修改.gitmodules使用ghfast.top代理"
            sed -i.bak "s|https://github.com|${GHPROXY_URL}/https://github.com|g" .gitmodules
            log "SUCCESS" "已为子模块添加ghfast.top代理前缀"
            

            log "INFO" "配置git全局设置，使用ghfast.top代理"
            git config --global url."${GHPROXY_URL}/https://github.com/".insteadOf "https://github.com/"
            

            if [ $DEBUG_MODE -eq 1 ]; then
                log "DEBUG" "当前git配置:"
                git config --global --get-regexp url
                log "DEBUG" "当前.gitmodules内容:"
                cat .gitmodules
            fi
        fi
    elif [ "$BEST_GITHUB_SITE" != "github.com" ] && [ $IS_PROXY_SITE -eq 0 ]; then

        if [ -f ".gitmodules" ]; then
            log "INFO" "修改.gitmodules使用镜像站点 $BEST_GITHUB_SITE"
            sed -i.bak "s|https://github.com|https://${BEST_GITHUB_SITE}|g" .gitmodules
            

            git config --global url."https://${BEST_GITHUB_SITE}/".insteadOf "https://github.com/"
        fi
    fi
    

    git submodule sync
    

    log "INFO" "执行git子模块初始化..."
    if git submodule init; then
        log "SUCCESS" "git子模块初始化完成"
        return 0
    else
        log "ERROR" "git子模块初始化失败"

        if [ -f ".gitmodules.bak" ]; then
            mv .gitmodules.bak .gitmodules
            git submodule sync
        fi
        

        if [ $USE_GHPROXY -eq 1 ]; then
            git config --global --unset url."${GHPROXY_URL}/https://github.com/".insteadOf
        elif [ "$BEST_GITHUB_SITE" != "github.com" ] && [ $IS_PROXY_SITE -eq 0 ]; then
            git config --global --unset url."https://${BEST_GITHUB_SITE}/".insteadOf
        fi
        
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
    

    if [ $USE_NUMA -eq 1 ]; then
        export USE_NUMA=1
        echo -e "${GREEN}✓ 已设置USE_NUMA=1${NC}"
    else
        export USE_NUMA=0
        echo -e "${YELLOW}USE_NUMA环境变量已禁用${NC}"
    fi
}

# 9. 下载预编译的flashinfer
download_flashinfer() {
    echo -e "${BLUE}[INFO] 安装flashinfer${NC}"
    

    if [ -z "$FORMATTED_CUDA_VERSION" ] || [ -z "$FORMATTED_TORCH_VERSION" ]; then
        echo -e "${YELLOW}CUDA或PyTorch版本信息缺失，尝试重新检测...${NC}"
        

        local torch_version=$(python -c "import torch; print(torch.__version__.split('+')[0])" 2>/dev/null)
        if [ -n "$torch_version" ]; then
            TORCH_VERSION="$torch_version"
            FORMATTED_TORCH_VERSION="torch$(echo $torch_version | cut -d '.' -f 1,2)"
            

            local cuda_torch_version=$(python -c "import torch; print(torch.version.cuda)" 2>/dev/null)
            if [ -n "$cuda_torch_version" ]; then
                CUDA_VERSION="$cuda_torch_version"
                FORMATTED_CUDA_VERSION="cu$(echo $cuda_torch_version | sed 's/\.//')"
                echo -e "${GREEN}✓ 从PyTorch检测到CUDA版本: ${CUDA_VERSION} (${FORMATTED_CUDA_VERSION})${NC}"
            fi
        else
            echo -e "${RED}[ERROR] 无法检测到PyTorch版本，请确保PyTorch已正确安装${NC}"
            return 1
        fi
    fi
    

    local actual_cuda_version="$CUDA_VERSION"
    local actual_formatted_cuda="$FORMATTED_CUDA_VERSION"
    

    local cuda_major=$(echo "$CUDA_VERSION" | cut -d. -f1)
    local cuda_minor=$(echo "$CUDA_VERSION" | cut -d. -f2)
    
    if [ "$cuda_major" -gt 12 ] || ([ "$cuda_major" -eq 12 ] && [ "$cuda_minor" -gt 4 ]); then
        echo -e "${YELLOW}检测到CUDA版本 ${CUDA_VERSION} 高于12.4，将使用cu124预编译包（向下兼容）${NC}"
        FORMATTED_CUDA_VERSION="cu124"
    fi
    

    local flashinfer_url="https://flashinfer.ai/whl/${FORMATTED_CUDA_VERSION}/${FORMATTED_TORCH_VERSION}"
    echo -e "${YELLOW}尝试从 ${flashinfer_url} 安装flashinfer...${NC}"
    

    local temp_dir="/tmp/flashinfer_download_$$"
    mkdir -p "$temp_dir"
    

    echo -e "${YELLOW}获取可用的wheel文件列表...${NC}"
    local wheel_list_file="$temp_dir/wheel_list.html"
    
    if wget -q -O "$wheel_list_file" "$flashinfer_url"; then

        local wheel_file_name=$(grep -o 'flashinfer_python-[0-9.]*-cp[0-9]*-cp[0-9]*-linux_x86_64.whl' "$wheel_list_file" | sort -V | tail -n 1)
        
        if [ -n "$wheel_file_name" ]; then
            local wheel_url="${flashinfer_url}/${wheel_file_name}"
            local wheel_file="$temp_dir/$wheel_file_name"
            
            echo -e "${YELLOW}找到wheel文件: ${wheel_file_name}${NC}"
            echo -e "${YELLOW}开始下载: ${wheel_url}${NC}"
            

            if wget -q --show-progress -O "$wheel_file" "$wheel_url"; then
                echo -e "${GREEN}✓ 下载成功，开始安装本地wheel文件${NC}"
                

                if pip install "$wheel_file"; then
                    echo -e "${GREEN}✓ flashinfer安装成功${NC}"
                    

                    if python -c "import flashinfer" &>/dev/null; then
                        local version=$(python -c "import flashinfer; print(flashinfer.__version__)" 2>/dev/null)
                        if [ -n "$version" ]; then
                            echo -e "${GREEN}✓ flashinfer导入测试成功，版本: $version${NC}"

                            rm -rf "$temp_dir"

                            FORMATTED_CUDA_VERSION="$actual_formatted_cuda"
                            return 0
                        else
                            echo -e "${YELLOW}flashinfer安装成功但获取版本信息失败${NC}"
                        fi
                    else
                        echo -e "${YELLOW}flashinfer安装成功但导入失败${NC}"
                    fi
                else
                    echo -e "${YELLOW}本地wheel文件安装失败${NC}"
                fi
            else
                echo -e "${YELLOW}下载wheel文件失败${NC}"
            fi
        else
            echo -e "${YELLOW}未找到匹配的wheel文件${NC}"
        fi
    else
        echo -e "${YELLOW}无法获取wheel文件列表${NC}"
    fi
    

    echo -e "${YELLOW}尝试使用pip的-f选项安装flashinfer...${NC}"
    if pip install flashinfer-python -f "$flashinfer_url"; then
        echo -e "${GREEN}✓ 通过pip -f选项安装flashinfer成功${NC}"
        

        if python -c "import flashinfer" &>/dev/null; then
            local version=$(python -c "import flashinfer; print(flashinfer.__version__)" 2>/dev/null)
            if [ -n "$version" ]; then
                echo -e "${GREEN}✓ flashinfer导入测试成功，版本: $version${NC}"

                rm -rf "$temp_dir"

                FORMATTED_CUDA_VERSION="$actual_formatted_cuda"
                return 0
            fi
        fi
    fi
    

    rm -rf "$temp_dir"
    

    echo -e "${YELLOW}从源代码安装flashinfer...${NC}"
    

    local temp_dir="/tmp/flashinfer_build_$$"
    mkdir -p "$temp_dir"
    cd "$temp_dir" || return 1
    

    echo -e "${YELLOW}克隆flashinfer仓库...${NC}"
    if [ -n "$BEST_GITHUB_SITE" ] && [ "$BEST_GITHUB_SITE" != "github.com" ]; then

        local repo_url="https://${BEST_GITHUB_SITE}/flashinfer-ai/flashinfer.git"
    else
        local repo_url="https://github.com/flashinfer-ai/flashinfer.git"
    fi
    
    if git clone --recursive "$repo_url"; then
        cd flashinfer || return 1
        echo -e "${YELLOW}开始编译安装flashinfer...${NC}"
        

        export MAX_JOBS="$MAX_JOBS"
        if [ $USE_NUMA -eq 1 ]; then
            export USE_NUMA=1
        fi
        

        if pip install -e . -v; then
            echo -e "${GREEN}✓ flashinfer从源码安装成功${NC}"
            

            if python -c "import flashinfer" &>/dev/null; then
                local version=$(python -c "import flashinfer; print(flashinfer.__version__)" 2>/dev/null)
                echo -e "${GREEN}✓ flashinfer导入测试成功，版本: ${version:-未知}${NC}"

                cd "$INSTALL_DIR" || return 1
                rm -rf "$temp_dir"

                FORMATTED_CUDA_VERSION="$actual_formatted_cuda"
                return 0
            else
                echo -e "${YELLOW}flashinfer安装成功但导入失败${NC}"
            fi
        else
            echo -e "${RED}[ERROR] flashinfer从源码安装失败${NC}"
        fi
    else
        echo -e "${RED}[ERROR] 克隆flashinfer仓库失败${NC}"
    fi
    

    cd "$INSTALL_DIR" || return 1
    rm -rf "$temp_dir"
    

    FORMATTED_CUDA_VERSION="$actual_formatted_cuda"
    return 1
}

# 11. 执行make dev_install
make_dev_install() {
    echo -e "${BLUE}[步骤 12] 执行make dev_install${NC}"
    

    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}× 目录 $INSTALL_DIR 不存在${NC}"
        return 1
    fi
    
    cd "$INSTALL_DIR" || {
        echo -e "${RED}× 无法进入 $INSTALL_DIR 目录${NC}"
        return 1
    }
    

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
    

    echo -e "${YELLOW}开始执行make dev_install（这可能需要一些时间）...${NC}"
    echo -e "${CYAN}编译过程中可能会显示一些警告，这是正常现象${NC}"
    
    local make_output=""
    local make_error_file="$INSTALL_DIR/make_error.log"
    
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] 开始执行make dev_install..." > "$make_error_file"
    

    if make_output=$(make dev_install 2>&1); then
        echo -e "${GREEN}✓ make dev_install执行成功${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] make dev_install执行成功" >> "$make_error_file"
        return 0
    else
        local exit_code=$?
        echo -e "${RED}× make dev_install执行失败 (错误码: $exit_code)${NC}"
        echo -e "${YELLOW}编译错误已保存到 $make_error_file${NC}"
        

        echo "[$(date +"%Y-%m-%d %H:%M:%S")] make dev_install执行失败 (错误码: $exit_code)" >> "$make_error_file"
        echo "==================== 错误输出 ====================" >> "$make_error_file"
        echo "$make_output" >> "$make_error_file"
        echo "==================================================" >> "$make_error_file"
        

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
    echo -e "${BLUE}[步骤 13] 更新libstdc++6${NC}"
    

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
    echo -e "${BLUE}[步骤 14] 安装libstdcxx-ng${NC}"
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
    echo -e "${BLUE}===== 安装组件版本检查 =====${NC}"
    

    cd "$INSTALL_DIR" || return 1
    
    echo -e "${YELLOW}● KTransformers 安装信息${NC}"
    

    if python -c "import ktransformers" &>/dev/null; then
        local ktrans_version=$(python -c "import ktransformers; print(ktransformers.__version__)" 2>/dev/null)
        echo -e "  ○ KTransformers版本: ${GREEN}${ktrans_version:-已安装}${NC}"
    else
        echo -e "  ○ KTransformers版本: ${RED}未安装或无法导入${NC}"
    fi
    

    if python -c "import torch" &>/dev/null; then
        local torch_version=$(python -c "import torch; print(torch.__version__)" 2>/dev/null)
        local cuda_available=$(python -c "import torch; print('可用' if torch.cuda.is_available() else '不可用')" 2>/dev/null)
        echo -e "  ○ PyTorch版本: ${GREEN}${torch_version}${NC} (CUDA: ${GREEN}${cuda_available}${NC})"
        

        if python -c "import torch; exit(0 if torch.cuda.is_available() else 1)" &>/dev/null; then
            local gpu_name=$(python -c "import torch; print(torch.cuda.get_device_name(0))" 2>/dev/null)
            echo -e "  ○ GPU设备: ${GREEN}${gpu_name}${NC}"
            

            local cuda_version=$(python -c "import torch; print(torch.version.cuda)" 2>/dev/null)
            echo -e "  ○ CUDA版本: ${GREEN}${cuda_version}${NC}"
        fi
    else
        echo -e "  ○ PyTorch版本: ${RED}未安装或无法导入${NC}"
    fi
    
    echo -e "${YELLOW}● 加速组件${NC}"
    

    if python -c "import flashinfer" &>/dev/null; then
        local flashinfer_version=$(python -c "import flashinfer; print(flashinfer.__version__)" 2>/dev/null)
        echo -e "  ○ FlashInfer版本: ${GREEN}${flashinfer_version:-已安装}${NC}"
    else
        echo -e "  ○ FlashInfer版本: ${RED}未安装或无法导入${NC}"
    fi
    

    if python -c "import flash_attn" &>/dev/null; then
        local flash_attn_version=$(python -c "import flash_attn; print(flash_attn.__version__)" 2>/dev/null)
        echo -e "  ○ Flash Attention版本: ${GREEN}${flash_attn_version:-已安装}${NC}"
    else
        echo -e "  ○ Flash Attention版本: ${RED}未安装或无法导入${NC}"
    fi
    

    if [ $USE_NUMA -eq 1 ]; then
        echo -e "  ○ USE_NUMA环境变量: ${GREEN}已启用${NC}"
    else
        echo -e "  ○ USE_NUMA环境变量: ${YELLOW}未启用${NC}"
    fi
    

    echo -e "  ○ 编译最大线程数: ${GREEN}${MAX_JOBS}${NC}"
    

    echo -e "\n${GREEN}✓ KTransformers安装完成!${NC}"
    echo -e "${YELLOW}您可以通过以下命令进入环境:${NC}"
    echo -e "${BLUE}  conda activate ${ENV_NAME}${NC}"
    echo -e "${YELLOW}然后运行示例:${NC}"
    echo -e "${BLUE}  cd ${INSTALL_DIR}/examples${NC}"
    echo -e "${BLUE}  python run_demo.py${NC}"
    echo -e "\n${GREEN}祝您使用愉快!${NC}\n"
}

# 5. 激活环境并进入仓库
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
elif [ -f "~/miniconda3/etc/profile.d/conda.sh" ]; then
    . "~/miniconda3/etc/profile.d/conda.sh"
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
    

    local activation_success=false
    

    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        echo -e "${YELLOW}尝试使用conda.sh激活环境...${NC}"
        . "$HOME/miniconda3/etc/profile.d/conda.sh"
        if conda activate $ENV_NAME 2>/dev/null; then
            activation_success=true
            echo -e "${GREEN}✓ 成功激活环境 $ENV_NAME${NC}"
        fi
    fi
    

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
    

    if [ "$activation_success" = false ] && [ -f "~/miniconda3/etc/profile.d/conda.sh" ]; then
        echo -e "${YELLOW}尝试使用用户的conda.sh激活环境...${NC}"
        . "~/miniconda3/etc/profile.d/conda.sh"
        if conda activate $ENV_NAME 2>/dev/null; then
            activation_success=true
            echo -e "${GREEN}✓ 成功激活环境 $ENV_NAME${NC}"
        fi
    fi
    

    if [ "$activation_success" = false ] && command_exists conda; then
        echo -e "${YELLOW}尝试直接使用conda命令激活环境...${NC}"
        conda activate $ENV_NAME 2>/dev/null
        if [ $? -eq 0 ]; then
            activation_success=true
            echo -e "${GREEN}✓ 成功激活环境 $ENV_NAME${NC}"
        fi
    fi
    

    if [ "$activation_success" = false ]; then
        echo -e "${YELLOW}无法激活环境 $ENV_NAME，尝试修复...${NC}"
        

        if command_exists conda; then
            echo -e "${YELLOW}重新初始化conda...${NC}"
            conda init bash
            

            if [ -f "$HOME/.bashrc" ]; then
                echo -e "${YELLOW}重新加载shell环境...${NC}"
                . "$HOME/.bashrc"

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
    

    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR" || echo -e "${RED}切换到 $INSTALL_DIR 失败${NC}"
    else
        echo -e "${RED}目录 $INSTALL_DIR 不存在${NC}"
    fi
    
    echo -e "${GREEN}✓ 已创建激活脚本并尝试进入仓库目录${NC}"
    

    if [ "$activation_success" = false ]; then
        echo -e "${YELLOW}提示: 安装完成后，请执行以下命令激活环境:${NC}"
        echo -e "${BLUE}source $(pwd)/activate_env.sh${NC}"
    fi
    
    return 0
}

# 工具函数
estimate_git_repo_size() {
    local repo_url="$1"
    local temp_file=$(mktemp)
    

    timeout 30 git ls-remote --heads --tags "$repo_url" > "$temp_file" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        rm -f "$temp_file"
        echo "0"
        return
    fi
    

    local ref_count=$(wc -l < "$temp_file")
    local estimated_size=$((ref_count * 2))
    
    rm -f "$temp_file"
    

    echo "$estimated_size"
}

# 更新git子模块
update_git_submodules_with_progress() {
    log "INFO" "更新git子模块，克隆和更新仓库"
    
    # 进入安装目录
    cd "$INSTALL_DIR" || {
        log "ERROR" "无法进入安装目录 $INSTALL_DIR"
        return 1
    }
    

    if [ $USE_GHPROXY -eq 1 ]; then

        if [ -f ".gitmodules" ] && ! grep -q "$GHPROXY_URL" .gitmodules; then
            log "INFO" "修改.gitmodules使用ghfast.top代理"
            sed -i.bak "s|https://github.com|${GHPROXY_URL}/https://github.com|g" .gitmodules
            log "SUCCESS" "已为子模块添加ghfast.top代理前缀"
            

            git submodule sync
            log "INFO" "已同步子模块配置"
            

            log "INFO" "配置git全局设置，使用ghfast.top代理"
            git config --global url."${GHPROXY_URL}/https://github.com/".insteadOf "https://github.com/"
            log "SUCCESS" "git全局配置已更新"
        fi
    fi
    

    local total_submodules=$(git config --file .gitmodules --get-regexp "^submodule\..*\.path$" | wc -l)
    
    if [ "$total_submodules" -eq 0 ]; then
        log "WARN" "未检测到git子模块"
        return 0
    fi
    
    log "INFO" "检测到 $total_submodules 个git子模块"
    

    if [ $DEBUG_MODE -eq 1 ]; then
        log "DEBUG" "当前.gitmodules内容:"
        cat .gitmodules
    fi
    

    local tmpfile=$(mktemp)
    

    if [ $DEBUG_MODE -eq 1 ] && [ $GIT_DEBUG_MODE -eq 1 ]; then

        export GIT_TRACE=1
        export GIT_CURL_VERBOSE=1
        log "DEBUG" "Git调试模式已启用，将显示详细日志"
    elif [ $DEBUG_MODE -eq 1 ]; then
        log "DEBUG" "Git调试模式已禁用，避免过多日志输出"
    fi
    
    log "INFO" "开始更新子模块，这可能需要一些时间..."
    

    if [ $DEBUG_MODE -eq 1 ]; then

        git submodule update --init --recursive --progress 2>&1 | tee "$tmpfile"
        local exit_code=${PIPESTATUS[0]}
    else

        git submodule update --init --recursive --progress 2>&1 | grep --line-buffered -E "Receiving objects:|Resolving deltas:" | tee "$tmpfile"
        local exit_code=${PIPESTATUS[0]}
    fi
    

    if [ $DEBUG_MODE -eq 1 ] && [ $GIT_DEBUG_MODE -eq 1 ]; then

        unset GIT_TRACE
        unset GIT_CURL_VERBOSE
        log "DEBUG" "Git调试模式已重置"
    elif [ $DEBUG_MODE -eq 1 ]; then
        log "DEBUG" "Git子模块更新完成"
    fi
    
    if [ $exit_code -eq 0 ]; then
        log "SUCCESS" "git子模块克隆和更新成功"

        rm -f "$tmpfile"
        

        if [ -f ".gitmodules.bak" ] && [ $USE_GHPROXY -eq 1 ]; then
            log "INFO" "恢复原始.gitmodules文件"
            mv .gitmodules.bak .gitmodules
            git submodule sync
            

            log "INFO" "恢复git全局配置"
            git config --global --unset url."${GHPROXY_URL}/https://github.com/".insteadOf
        fi
        
        return 0
    else
        log "ERROR" "git子模块更新失败"
        log "DEBUG" "错误详情: $(cat "$tmpfile")"
        

        log "WARN" "尝试使用非并行方式更新子模块..."
        if git submodule update --init --recursive --jobs=1 --progress; then
            log "SUCCESS" "使用非并行方式更新子模块成功"
            rm -f "$tmpfile"
            return 0
        fi
        
        rm -f "$tmpfile"
        return 1
    fi
}

# 安装flash_attn
install_flash_attn() {
    log "INFO" "安装Flash Attention"
    

    if [ -z "$FORMATTED_CUDA_VERSION" ] || [ -z "$FORMATTED_TORCH_VERSION" ]; then
        log "WARN" "CUDA或PyTorch版本信息缺失，尝试重新检测..."
        

        local torch_version=$(python -c "import torch; print(torch.__version__.split('+')[0])" 2>/dev/null)
        if [ -n "$torch_version" ]; then
            TORCH_VERSION="$torch_version"
            FORMATTED_TORCH_VERSION="torch$(echo $torch_version | cut -d. -f1,2 | sed 's/\.//')"
            

            local cuda_torch_version=$(python -c "import torch; print(torch.version.cuda)" 2>/dev/null)
            if [ -n "$cuda_torch_version" ]; then
                CUDA_VERSION="$cuda_torch_version"
                FORMATTED_CUDA_VERSION="cu$(echo $cuda_torch_version | sed 's/\.//')"
                log "SUCCESS" "从PyTorch检测到CUDA版本: ${CUDA_VERSION} (${FORMATTED_CUDA_VERSION})"
            fi
        else
            log "ERROR" "无法检测到PyTorch版本，请确保PyTorch已正确安装"
            return 1
        fi
    fi
    

    local python_version=$(python -c "import sys; print(f'cp{sys.version_info.major}{sys.version_info.minor}')" 2>/dev/null)
    if [ -z "$python_version" ]; then
        log "ERROR" "无法检测到Python版本"
        return 1
    fi
    

    local actual_cuda_version="$CUDA_VERSION"
    local actual_formatted_cuda="$FORMATTED_CUDA_VERSION"
    

    local cuda_major=$(echo "$CUDA_VERSION" | cut -d. -f1)
    

    FORMATTED_CUDA_VERSION="cu${cuda_major}"
    
    log "INFO" "检测到环境信息:"
    log "INFO" "- CUDA版本: ${actual_cuda_version} (${actual_formatted_cuda})"
    log "INFO" "- 将使用CUDA大版本: ${FORMATTED_CUDA_VERSION} 进行安装"
    log "INFO" "- PyTorch版本: ${TORCH_VERSION} (${FORMATTED_TORCH_VERSION})"
    log "INFO" "- Python版本: ${python_version}"
    

    log "INFO" "尝试安装预编译的Flash Attention..."
    

    local flash_attn_version="2.7.4.post1"
    local base_url="https://github.com/Dao-AILab/flash-attention/releases/download/v${flash_attn_version}"
    local package_name="flash_attn-${flash_attn_version}+${FORMATTED_CUDA_VERSION}${FORMATTED_TORCH_VERSION}cxx11abiFALSE-${python_version}-${python_version}-linux_x86_64.whl"
    

    local flash_attn_url
    if [ $USE_GHPROXY -eq 1 ] && [ -n "$GHPROXY_URL" ]; then

        flash_attn_url="${GHPROXY_URL}/https://github.com/Dao-AILab/flash-attention/releases/download/v${flash_attn_version}/${package_name}"
        log "INFO" "使用代理下载Flash Attention: ${flash_attn_url}"
    else
        flash_attn_url="${base_url}/${package_name}"
        log "INFO" "直接从GitHub下载Flash Attention: ${flash_attn_url}"
    fi
    
    log "INFO" "尝试下载: ${flash_attn_url}"
    

    if pip install "${flash_attn_url}"; then
        log "SUCCESS" "Flash Attention预编译包安装成功"
        

        if python -c "import flash_attn; print('Flash Attention版本:', flash_attn.__version__)" 2>/dev/null; then
            log "SUCCESS" "Flash Attention导入测试成功"

            FORMATTED_CUDA_VERSION="$actual_formatted_cuda"
            return 0
        else
            log "WARN" "Flash Attention安装成功但导入失败，尝试从源码安装..."
        fi
    else
        log "WARN" "预编译包安装失败，尝试从源码安装..."
    fi
    

    log "INFO" "准备从源码安装Flash Attention..."
    

    log "INFO" "安装ninja构建工具..."
    pip uninstall -y ninja && pip install ninja
    

    log "INFO" "设置编译环境变量，使用${MAX_JOBS}个编译线程..."
    export MAX_JOBS="$MAX_JOBS"
    

    if [ $USE_NUMA -eq 1 ]; then
        log "INFO" "启用NUMA优化..."
        export USE_NUMA=1
    fi
    

    log "INFO" "开始编译安装Flash Attention..."
    

    if [ $USE_GHPROXY -eq 1 ] && [ -n "$GHPROXY_URL" ]; then

        log "INFO" "使用代理从源码安装Flash Attention..."
        

        local temp_dir=$(mktemp -d)
        cd "$temp_dir" || {
            log "ERROR" "无法创建临时目录"
            return 1
        }
        

        log "INFO" "克隆Flash Attention仓库..."
        if git clone "${GHPROXY_URL}/https://github.com/Dao-AILab/flash-attention.git"; then
            cd flash-attention || {
                log "ERROR" "无法进入flash-attention目录"
                return 1
            }
            

            log "INFO" "从源码安装Flash Attention..."
            if pip install -e .; then
                log "SUCCESS" "Flash Attention从源码安装成功"
                

                if python -c "import flash_attn; print('Flash Attention版本:', flash_attn.__version__)" 2>/dev/null; then
                    log "SUCCESS" "Flash Attention导入测试成功"

                    FORMATTED_CUDA_VERSION="$actual_formatted_cuda"

                    cd "$INSTALL_DIR"
                    rm -rf "$temp_dir"
                    return 0
                else
                    log "WARN" "Flash Attention安装成功但导入失败"

                    FORMATTED_CUDA_VERSION="$actual_formatted_cuda"

                    cd "$INSTALL_DIR"
                    rm -rf "$temp_dir"
                    return 1
                fi
            else
                log "ERROR" "Flash Attention从源码安装失败"

                FORMATTED_CUDA_VERSION="$actual_formatted_cuda"

                cd "$INSTALL_DIR"
                rm -rf "$temp_dir"
                return 1
            fi
        else
            log "ERROR" "克隆Flash Attention仓库失败"

            FORMATTED_CUDA_VERSION="$actual_formatted_cuda"

            cd "$INSTALL_DIR"
            rm -rf "$temp_dir"
            return 1
        fi
    else

        if pip install flash-attn --no-build-isolation; then
            log "SUCCESS" "Flash Attention从源码安装成功"
            

            if python -c "import flash_attn; print('Flash Attention版本:', flash_attn.__version__)" 2>/dev/null; then
                log "SUCCESS" "Flash Attention导入测试成功"

                FORMATTED_CUDA_VERSION="$actual_formatted_cuda"
                return 0
            else
                log "WARN" "Flash Attention安装成功但导入失败"

                FORMATTED_CUDA_VERSION="$actual_formatted_cuda"
                return 1
            fi
        else
            log "ERROR" "Flash Attention从源码安装失败"

            FORMATTED_CUDA_VERSION="$actual_formatted_cuda"
            return 1
        fi
    fi
}

# 检查Git镜像站点
check_best_github_site() {
    log "INFO" "检查最佳GitHub镜像站点..."
    

    if [ -f "clone.sh" ]; then
        log "INFO" "运行GitHub镜像站点测试..."

        bash clone.sh >/dev/null 2>&1
        

        if [ -f "mirror_test/best_site.env" ]; then
            source mirror_test/best_site.env
            log "SUCCESS" "找到最佳GitHub镜像站点: $BEST_GITHUB_SITE"
            

            if [ "$IS_PROXY" = "1" ]; then
                GITHUB_PREFIX="https://${BEST_GITHUB_SITE}/https://github.com/"
                log "INFO" "使用代理镜像: $BEST_GITHUB_SITE"
            else
                GITHUB_PREFIX="https://${BEST_GITHUB_SITE}/"
                log "INFO" "使用直连镜像: $BEST_GITHUB_SITE"
            fi
        else
            log "WARN" "未找到GitHub镜像站点测试结果，使用默认站点"
            GITHUB_PREFIX="https://github.com/"
        fi
    else
        log "WARN" "未找到clone.sh脚本，使用默认GitHub站点"
        GITHUB_PREFIX="https://github.com/"
    fi
}

# 检测IP
is_china_ip() {
    log "INFO" "检测IP地理位置..."
    

    local ip_services=(
        "https://api.myip.la/en?json"
        "https://ipapi.co/json/"
        "https://ip.useragentinfo.com/json"
    )
    
    local is_china=0
    local country_code=""
    local ip_address=""
    
    for service in "${ip_services[@]}"; do
        local result=$(curl -s --connect-timeout 5 "$service" 2>/dev/null)
        

        if [ -n "$result" ]; then

            if echo "$result" | grep -qi "China\|CN"; then
                is_china=1
                country_code="CN"
                ip_address=$(echo "$result" | grep -o '"ip":"[^"]*"' | head -1 | cut -d'"' -f4)
                if [ -z "$ip_address" ]; then
                    ip_address=$(echo "$result" | grep -o '"ip":[^,]*' | head -1 | cut -d':' -f2 | tr -d ' "')
                fi
                break
            elif echo "$result" | grep -q "country_code\|countryCode"; then
                country_code=$(echo "$result" | grep -o '"country_code":"[^"]*"' | cut -d'"' -f4)
                if [ -z "$country_code" ]; then
                    country_code=$(echo "$result" | grep -o '"countryCode":"[^"]*"' | cut -d'"' -f4)
                fi
                
                ip_address=$(echo "$result" | grep -o '"ip":"[^"]*"' | head -1 | cut -d'"' -f4)
                if [ -z "$ip_address" ]; then
                    ip_address=$(echo "$result" | grep -o '"ip":[^,]*' | head -1 | cut -d':' -f2 | tr -d ' "')
                fi
                
                if [ "$country_code" = "CN" ]; then
                    is_china=1
                    break
                elif [ -n "$country_code" ]; then
                    break
                fi
            fi
        fi
    done
    

    if [ -z "$country_code" ]; then
        log "WARN" "无法通过API检测IP地理位置，尝试网络延迟测试..."
        

        local cn_site="baidu.com"
        local global_site="google.com"
        
        local cn_time=$(ping -c 3 $cn_site 2>/dev/null | grep "avg" | awk -F'/' '{print $5}' || echo 999)
        local global_time=$(ping -c 3 $global_site 2>/dev/null | grep "avg" | awk -F'/' '{print $5}' || echo 999)
        
        if [ $(echo "$cn_time < $global_time" | bc -l) -eq 1 ]; then
            log "DEBUG" "国内网站延迟($cn_time ms)低于国际网站($global_time ms)，可能位于中国网络环境"
            is_china=1
        else
            log "DEBUG" "国际网站延迟($global_time ms)低于国内网站($cn_time ms)，可能位于国际网络环境"
            is_china=0
        fi
    fi
    
    if [ $is_china -eq 1 ]; then
        log "INFO" "检测到中国IP地址: $ip_address"
        return 0
    else
        log "INFO" "检测到非中国IP地址: $ip_address (国家代码: $country_code)"
        return 1
    fi
}

# 主函数
main() {
    # 用户配置安装选项
    configure_installation
    
    # 显示开始安装标题
    echo -e "${BLUE}===== KTransformers 安装开始 =====${NC}\n"
    
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
    
    # 测试GitHub连通性
    test_github_connectivity
    
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
    
    # 安装conda和创建环境
    install_conda || { echo -e "${RED}Conda安装失败，无法继续安装${NC}"; exit 1; }
    create_conda_env || { echo -e "${RED}Conda环境创建失败，无法继续安装${NC}"; exit 1; }
    
    # 克隆仓库，添加更详细的错误处理
    if ! clone_repository; then
        log "ERROR" "仓库克隆失败，请检查网络连接和目录权限"
        log "INFO" "您可以尝试手动克隆仓库:"
        log "INFO" "  git clone https://github.com/kvcache-ai/ktransformers.git $INSTALL_DIR"
        log "INFO" "或者使用ghfast.top代理:"
        log "INFO" "  git clone https://ghfast.top/https://github.com/kvcache-ai/ktransformers.git $INSTALL_DIR"
        exit 1
    fi
    
    # 激活环境
    activate_conda_env || install_status=1
    
    # 初始化Git子模块
    init_git_submodules || install_status=1
    
    # 更新Git子模块
    update_git_submodules_with_progress || install_status=1
    
    # 安装libnuma和设置环境变量
    install_libnuma || install_status=1
    set_use_numa
    
    # 安装PyTorch (GPU版本)
    install_pytorch || install_status=1
    
    # 先安装flash_attn
    echo -e "${BLUE}[步骤 10] 安装Flash Attention${NC}"
    install_flash_attn || install_status=1
    
    # 安装flashinfer
    echo -e "${BLUE}[步骤 11] 安装FlashInfer${NC}"
    download_flashinfer || install_status=1
    
    # 编译安装KTransformers
    make_dev_install || install_status=1
    
    # 安装其他依赖
    update_libstdcpp6 || install_status=1
    install_libstdcxx_ng || install_status=1
    
    # 检查安装的版本
    check_versions
    
    # 安装完成
    if [ $install_status -eq 0 ]; then
        log "SUCCESS" "安装完成！"
        log "INFO" "现在你可以使用 ktransformers 了！"
        log "INFO" "启动命令: cd $INSTALL_DIR && conda activate $ENV_NAME && python -m ktransformers"
    else
        log "WARN" "安装过程中有部分步骤失败，请查看详细日志"
        log "INFO" "你可以尝试修复问题后重新运行脚本"
    fi
}

# 运行主函数
main "$@"



