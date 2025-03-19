#!/bin/bash

# 脚本版本信息
# 最后更新: 2025-03-20
# 版本: 1.1.0
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
#--------------------
# 安装配置
INSTALL_DIR="$(pwd)/workspace"  # 安装目录
ENV_NAME="ktrans_main"          # Conda环境名称
MAX_JOBS=$(nproc)               # 编译使用的最大线程数
USE_NUMA=0                      # 是否启用NUMA环境变量

# 网络与代理配置
USE_GHPROXY=0                   # 是否使用国内代理加速
GHPROXY_URL="https://ghfast.top" # 默认代理服务器URL

# 运行模式设置
DEBUG_MODE=0                    # 调试模式开关
GIT_DEBUG_MODE=0                # Git详细日志开关
FAST_MODE=0                     # 快速安装模式开关

# 内部使用变量
LOG_FILE=""                     # 日志文件路径
CUSTOM_PATH=""                  # 自定义PATH

# 添加单选框交互函数
show_selection_menu() {
    local title="$1"
    local opt1="$2"
    local opt2="$3"
    local default_opt="$4"
    
    local selected=""
    local opt1_status="○"
    local opt2_status="○"
    
    # 设置默认选项
    if [ "$default_opt" = "1" ]; then
        opt1_status="\033[1;32m●\033[0m"  # 绿色高亮
        selected="1"
    else
        opt2_status="\033[1;32m●\033[0m"  # 绿色高亮
        selected="2"
    fi
    
    while true; do
        echo -e "\n╭─ ${title}"
        echo -e "│"
        echo -e "╰─ ${opt1_status} ${opt1} / ${opt2_status} ${opt2}"
        echo -e ""
        read -p "请输入选项 [1/2] 或按左右方向键选择: " -n 1 choice
        
        # 捕获特殊按键（方向键）
        if [[ "$choice" == $'\e' ]]; then
            read -t 0.1 -n 2 rest
            if [[ "$rest" == "[C" ]]; then  # 右方向键
                if [ "$selected" = "1" ]; then
                    selected="2"
                    opt1_status="○"
                    opt2_status="\033[1;32m●\033[0m"  # 绿色高亮
                fi
                echo -e "\r\033[K"  # 清除当前行
                continue
            elif [[ "$rest" == "[D" ]]; then  # 左方向键
                if [ "$selected" = "2" ]; then
                    selected="1"
                    opt1_status="\033[1;32m●\033[0m"  # 绿色高亮
                    opt2_status="○"
                fi
                echo -e "\r\033[K"  # 清除当前行
                continue
            fi
        fi
        
        # 回车键处理
        if [[ "$choice" == "" ]]; then
            echo ""
            return $selected
        fi
        
        # 数字选择处理
        case "$choice" in
            1)
                echo ""
                return 1
                ;;
            2)
                echo ""
                return 2
                ;;
            *)
                echo -e "\r\033[K${YELLOW}请输入有效的选项: 1, 2, 或使用方向键${NC}"
                ;;
        esac
    done
}

# 添加路径选择函数
select_or_input_path() {
    local title="$1"
    local default_path="$2"
    local path_type="$3"  # 描述这是什么路径
    local result_path=""
    
    while true; do
        echo -e "\n╭─ ${title}"
        echo -e "│"
        echo -e "╰─ 默认路径: ${GREEN}${default_path}${NC}"
        echo -e ""
        
        show_selection_menu "是否使用默认${path_type}路径?" "是" "否" "1"
        local path_choice=$?
        
        if [ $path_choice -eq 1 ]; then
            echo -e "${GREEN}✓ 使用默认${path_type}路径: ${default_path}${NC}"
            result_path="${default_path}"
            break
        else
            read -p "请输入${path_type}路径: " user_path
            if [ -n "$user_path" ]; then
                echo -e "${GREEN}✓ 使用自定义${path_type}路径: ${user_path}${NC}"
                result_path="${user_path}"
                break
            else
                echo -e "${YELLOW}路径不能为空，请重新选择${NC}"
            fi
        fi
    done
    
    # 单独一行返回路径值，确保不包含其他输出
    echo "$result_path"
}

# 用户配置部分
configure_installation() {

    echo "+=======================================+"
    echo -e "|\033[0;1;31;91m╦\033[0;1;33;93m╔═\033[0;1;32;92m┌┬┐\033[0;1;36;96m┬─┐\033[0;1;34;94m┌─┐\033[0;1;35;95m┌┐┌\033[0;1;31;91m┌─┐\033[0;1;33;93m┌─┐\033[0;1;32;92m┌─┐\033[0;1;36;96m┬─┐\033[0;1;34;94m┌┬┐\033[0;1;35;95m┌─┐\033[0;1;31;91m┬─┐\033[0;1;33;93m┌─┐\033[0m|"
    echo -e "|\033[0;1;32;92m╠\033[0;1;36;96m╩╗\033[0;1;34;94m │ \033[0;1;35;95m├┬┘\033[0;1;31;91m├─┤\033[0;1;33;93m│││\033[0;1;32;92m└─┐\033[0;1;36;96m├┤ \033[0;1;34;94m│ │\033[0;1;35;95m├┬┘\033[0;1;31;91m│││\033[0;1;33;93m├┤ \033[0;1;32;92m├┬┘\033[0;1;36;96m└─┐\033[0m|"
    echo -e "|\033[0;1;34;94m╩\033[0;1;35;95m ╩\033[0;1;31;91m ┴ \033[0;1;33;93m┴└─\033[0;1;32;92m┴ ┴\033[0;1;36;96m┘└┘\033[0;1;34;94m└─┘\033[0;1;35;95m└  \033[0;1;31;91m└─┘\033[0;1;33;93m┴└─\033[0;1;32;92m┴ ┴\033[0;1;36;96m└─┘\033[0;1;34;94m┴└─\033[0;1;35;95m└─┘\033[0m|"
    echo "+=======================================+"
    

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
        
        # 安装路径选择
        local default_install_dir="${INSTALL_DIR}"
        echo -e "\n╭─ 请选择安装路径"
        echo -e "│"
        echo -e "╰─ 默认路径: ${GREEN}${default_install_dir}${NC}"
        echo -e ""
        
        show_selection_menu "是否使用默认安装路径?" "是" "否" "1"
        local path_choice=$?
        
        if [ $path_choice -eq 1 ]; then
            echo -e "${GREEN}✓ 使用默认安装路径: ${default_install_dir}${NC}"
            INSTALL_DIR="${default_install_dir}"
        else
            read -p "请输入安装路径: " user_path
            if [ -n "$user_path" ]; then
                echo -e "${GREEN}✓ 使用自定义安装路径: ${user_path}${NC}"
                INSTALL_DIR="$user_path"
            else
                echo -e "${YELLOW}路径不能为空，使用默认路径: ${default_install_dir}${NC}"
                INSTALL_DIR="${default_install_dir}"
            fi
        fi
        
        # 确保INSTALL_DIR是纯字符串，不包含格式字符
        INSTALL_DIR=$(echo "$INSTALL_DIR" | tr -d '\r')
        
        # Conda环境名称选择
        echo -e "\n╭─ 请选择Conda环境名称"
        echo -e "│"
        echo -e "╰─ 默认环境名称: ${GREEN}${ENV_NAME}${NC}"
        echo -e ""
        
        show_selection_menu "是否使用默认环境名称?" "是" "否" "1"
        local env_choice=$?
        
        if [ $env_choice -eq 2 ]; then
            read -p "请输入Conda环境名称: " user_env_name
            if [ -n "$user_env_name" ]; then
                ENV_NAME="$user_env_name"
                echo -e "${GREEN}✓ Conda环境名称已更新为: ${ENV_NAME}${NC}"
            else
                echo -e "${YELLOW}使用默认环境名称: ${ENV_NAME}${NC}"
            fi
        else
            echo -e "${GREEN}✓ 使用默认环境名称: ${ENV_NAME}${NC}"
        fi
        
        # 使用单选框选择NUMA环境变量设置
        show_selection_menu "是否启用USE_NUMA环境变量?" "是" "否" "2"
        local numa_choice=$?
        
        if [ $numa_choice -eq 1 ]; then
            USE_NUMA=1
            echo -e "${GREEN}✓ 已启用USE_NUMA环境变量${NC}"
        else
            USE_NUMA=0
            echo -e "${GREEN}✓ 已禁用USE_NUMA环境变量${NC}"
        fi
        
        # 添加是否使用国内代理的选项，使用改进的选择界面
        show_selection_menu "是否使用国内代理和镜像站点?" "是" "否" "1"
        local proxy_choice=$?
        
        if [ $proxy_choice -eq 1 ]; then
            USE_GHPROXY=1
            echo -e "${GREEN}✓ 已启用国内代理和镜像站点${NC}"
        else
            USE_GHPROXY=0
            echo -e "${GREEN}✓ 已禁用国内代理和镜像站点${NC}"
        fi

        # 编译线程数选择
        echo -e "\n╭─ 请选择编译最大线程数"
        echo -e "│"
        echo -e "╰─ 默认线程数: ${GREEN}${MAX_JOBS}${NC}"
        echo -e ""
        
        show_selection_menu "是否使用默认线程数?" "是" "否" "1"
        local jobs_choice=$?
        
        if [ $jobs_choice -eq 2 ]; then
            read -p "请输入编译最大线程数: " user_max_jobs
            if [ -n "$user_max_jobs" ] && [ "$user_max_jobs" -gt 0 ] 2>/dev/null; then
                MAX_JOBS="$user_max_jobs"
                echo -e "${GREEN}✓ 编译最大线程数已更新为: ${MAX_JOBS}${NC}"
            else
                echo -e "${YELLOW}使用默认线程数: ${MAX_JOBS}${NC}"
            fi
        else
            echo -e "${GREEN}✓ 使用默认线程数: ${MAX_JOBS}${NC}"
        fi
        
        # 使用单选框选择调试模式
        show_selection_menu "是否启用调试模式?" "是" "否" "2"
        local debug_choice=$?
        
        if [ $debug_choice -eq 1 ]; then
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
    echo -e "${BLUE}● 国内代理: ${GREEN}$([ $USE_GHPROXY -eq 1 ] && echo "启用" || echo "禁用")${NC}"
    

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
    
    # 默认设置GitHub站点
    BEST_GITHUB_SITE="github.com"
    
    # 使用用户选择的配置
    if [ $USE_GHPROXY -eq 1 ]; then
        log "INFO" "使用ghfast.top代理服务"
        GHPROXY_URL="https://ghfast.top"
        log "SUCCESS" "已配置使用ghfast.top代理服务: $GHPROXY_URL"
        export GHPROXY_URL
    else
        log "INFO" "将直接使用GitHub"
        USE_GHPROXY=0
    fi
    
    export USE_GHPROXY
    return 0
}

# 2. 拉取仓库
clone_repo() {
    echo -e "${BLUE}[步骤 2] 克隆代码仓库${NC}"
    
    # 确保INSTALL_DIR是纯路径，去除任何多余字符
    INSTALL_DIR=$(echo "$INSTALL_DIR" | tr -d '\r')
    
    # 确保安装目录存在
    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}[INFO] 目录已存在: $INSTALL_DIR${NC}"
        
        # 检查目录是否为空
        if [ "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
            echo -e "${YELLOW}[WARN] 安装目录不为空${NC}"
            
            show_selection_menu "安装目录不为空，是否继续?" "是" "否" "1"
            local continue_choice=$?
            
            if [ $continue_choice -ne 1 ]; then
                echo -e "${YELLOW}[INFO] 用户选择不继续，退出安装${NC}"
                exit 0
            fi
            
            echo -e "${YELLOW}[INFO] 继续安装${NC}"
            return 0
        fi
    else
        echo -e "${YELLOW}[INFO] 创建目录: $INSTALL_DIR${NC}"
        mkdir -p "$INSTALL_DIR" || {
            echo -e "${RED}× 无法创建目录: $INSTALL_DIR${NC}"
            return 1
        }
    fi
    
    # 根据用户选择设置不同的代理URL
    local repo_url="https://github.com/kvcache-ai/ktransformers.git"
    local clone_url="$repo_url"
    
    if [ $USE_GHPROXY -eq 1 ]; then
        echo -e "${YELLOW}[INFO] 根据用户设置，使用国内代理克隆仓库${NC}"
        clone_url="${GHPROXY_URL}/${repo_url}"
        echo -e "${YELLOW}[DEBUG] 初始仓库URL: ${clone_url}${NC}"
    fi
    
    echo -e "${YELLOW}[INFO] 开始$([ $USE_GHPROXY -eq 1 ] && echo "使用${GHPROXY_URL}代理")克隆...${NC}"
    
    # 克隆仓库
    if git clone "$clone_url" "$INSTALL_DIR"; then
        echo -e "${GREEN}✓ 仓库克隆成功${NC}"
        return 0
    else
        # 如果使用代理失败，尝试直接连接
        if [ $USE_GHPROXY -eq 1 ]; then
            echo -e "${YELLOW}[WARN] 使用代理克隆失败，尝试直接连接...${NC}"
            
            if git clone "$repo_url" "$INSTALL_DIR"; then
                echo -e "${GREEN}✓ 直接克隆仓库成功${NC}"
                return 0
            else
                echo -e "${RED}× 仓库克隆失败${NC}"
                return 1
            fi
        else
            echo -e "${RED}× 仓库克隆失败${NC}"
            return 1
        fi
    fi
}

# 3. 检测conda
install_conda() {
    echo -e "${BLUE}[步骤 3] 检测conda${NC}"
    
    # 记录当前用户信息
    local current_user=$(whoami)
    local non_root_user=""
    
    # 如果当前是root用户，尝试找到一个非root用户
    if [ "$(id -u)" -eq 0 ]; then
        non_root_user=$(who | awk '{print $1}' | grep -v "root" | head -n 1)
        if [ -z "$non_root_user" ]; then
            non_root_user=$SUDO_USER
        fi
        if [ -z "$non_root_user" ]; then
            echo -e "${YELLOW}未找到非root用户，将使用当前用户${NC}"
            non_root_user="root"
        fi
    else
        non_root_user=$current_user
    fi
    
    echo -e "${YELLOW}检测到用户: $current_user, 目标用户: $non_root_user${NC}"
    
    # 检查所有用户的conda安装
    local found_conda=0
    local found_conda_path=""
    local all_users=()
    
    # 获取所有普通用户列表
    if [ -f "/etc/passwd" ]; then
        all_users=($(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd))
        echo -e "${YELLOW}系统中的普通用户: ${all_users[*]}${NC}"
    fi
    
    # 添加当前用户和非root用户到检查列表
    all_users+=("$current_user")
    if [ "$non_root_user" != "$current_user" ] && [ "$non_root_user" != "root" ]; then
        all_users+=("$non_root_user")
    fi
    
    # 去重
    all_users=($(echo "${all_users[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    
    echo -e "${YELLOW}将检查以下用户的conda安装: ${all_users[*]}${NC}"
    
    # 先检查当前环境中是否有conda命令
    if command_exists conda; then
        found_conda=1
        found_conda_path=$(which conda)
        echo -e "${GREEN}✓ 当前环境中找到conda: $found_conda_path${NC}"
    else
        # 检查所有用户的可能conda安装路径
        for user in "${all_users[@]}"; do
            local home_dir
            
            if [ "$user" = "root" ]; then
                home_dir="/root"
            else
                home_dir="/home/$user"
            fi
            
            echo -e "${YELLOW}检查用户 $user 的conda安装 ($home_dir)${NC}"
            
            local possible_conda_paths=(
                "$home_dir/miniconda3/bin/conda"
                "$home_dir/anaconda3/bin/conda"
                "$home_dir/conda/bin/conda"
            )
            
            for conda_path in "${possible_conda_paths[@]}"; do
                if [ -f "$conda_path" ]; then
                    found_conda=1
                    found_conda_path=$conda_path
                    echo -e "${GREEN}✓ 在用户 $user 目录找到conda: ${conda_path}${NC}"
                    break 2
                fi
            done
        done
        
        # 检查系统目录
        local system_conda_paths=(
            "/usr/local/miniconda3/bin/conda"
            "/usr/local/anaconda3/bin/conda"
            "/usr/local/conda/bin/conda"
            "/opt/conda/bin/conda"
        )
        
        for conda_path in "${system_conda_paths[@]}"; do
            if [ -f "$conda_path" ]; then
                found_conda=1
                found_conda_path=$conda_path
                echo -e "${GREEN}✓ 在系统目录找到conda: ${conda_path}${NC}"
                break
            fi
        done
    fi
    
    # 如果找到了conda
    if [ $found_conda -eq 1 ]; then
        local conda_base_dir=$(dirname $(dirname "$found_conda_path"))
        echo -e "${GREEN}✓ 找到conda安装目录: $conda_base_dir${NC}"
        
        # 更新所有用户的PATH设置
        update_all_users_path "$conda_base_dir"
        
        # 确保当前环境中conda可用
        export PATH="$conda_base_dir/bin:$PATH"
        
        # 初始化conda
        if command_exists conda; then
            echo -e "${GREEN}✓ conda已可用${NC}"
            
            # 显示conda版本
            if [ $DEBUG_MODE -eq 1 ]; then
                conda_version=$(conda --version)
                echo -e "${CYAN}[调试] conda版本: ${conda_version}${NC}"
                echo "[$(date +"%Y-%m-%d %H:%M:%S")] conda已安装: $(which conda), 版本: ${conda_version}" >> "$LOG_FILE"
            fi
            return 0
        else
            echo -e "${YELLOW}虽然找到conda但未能使其在当前环境中可用，尝试安装新的conda${NC}"
        fi
    fi
    
    # 如果没有找到conda，则安装
    echo -e "${YELLOW}未找到可用的conda，准备安装miniconda...${NC}"
    
    # 确定安装目录（安装到非root用户目录下）
    local install_dir
    if [ "$non_root_user" != "root" ]; then
        install_dir="/home/$non_root_user/miniconda3"
        echo -e "${YELLOW}将安装conda到非root用户目录: $install_dir${NC}"
    else
        # 如果没有非root用户，则安装到/opt
        install_dir="/opt/conda"
        echo -e "${YELLOW}未找到适合的非root用户，将安装conda到系统目录: $install_dir${NC}"
    fi
    
    # 使用国内或国际镜像
    local miniconda_url=""
    if [ $USE_GHPROXY -eq 1 ]; then
        miniconda_url="https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh"
    else
        miniconda_url="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
    fi
    
    # 下载miniconda
    echo -e "${YELLOW}下载Miniconda安装脚本...${NC}"
    local miniconda_installer="/tmp/miniconda.sh"
    retry_command_with_logging "wget $miniconda_url -O $miniconda_installer" 300
    
    # 安装conda
    echo -e "${YELLOW}安装conda到: $install_dir${NC}"
    bash $miniconda_installer -b -p $install_dir
    local install_status=$?
    
    # 清理安装文件
    rm -f $miniconda_installer
    
    if [ $install_status -ne 0 ]; then
        echo -e "${RED}× conda安装失败${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] conda安装失败" >> "$LOG_FILE"
        return 1
    fi
    
    # 设置权限
    if [ "$non_root_user" != "root" ]; then
        echo -e "${YELLOW}设置conda目录权限给用户: $non_root_user${NC}"
        chown -R $non_root_user:$non_root_user $install_dir
    fi
    
    # 更新所有用户的PATH
    update_all_users_path "$install_dir"
    
    # 更新当前PATH
    export PATH="$install_dir/bin:$PATH"
    
    # 验证安装
    if command_exists conda; then
        echo -e "${GREEN}✓ conda安装成功且可用${NC}"
        
        # 初始化conda
        echo -e "${YELLOW}初始化conda...${NC}"
        "$install_dir/bin/conda" init bash
        
        if [ $DEBUG_MODE -eq 1 ]; then
            conda_version=$(conda --version)
            echo -e "${CYAN}[调试] conda版本: ${conda_version}${NC}"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] conda已安装: $(which conda), 版本: ${conda_version}" >> "$LOG_FILE"
        fi
        return 0
    else
        echo -e "${RED}× conda安装失败，无法在PATH中找到conda命令${NC}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] conda安装失败" >> "$LOG_FILE"
        return 1
    fi
}

# 更新所有用户的PATH以包含conda
update_all_users_path() {
    local conda_dir="$1"
    echo -e "${YELLOW}更新所有用户的PATH以包含conda: $conda_dir${NC}"
    
    # 创建系统级conda初始化脚本
    echo -e "${YELLOW}创建系统级conda初始化脚本...${NC}"
    cat > /etc/profile.d/conda.sh << EOF
# 添加conda到系统PATH
export PATH="$conda_dir/bin:\$PATH"

# 为了兼容不同的shell，添加conda初始化
if [ -f "$conda_dir/etc/profile.d/conda.sh" ]; then
    . "$conda_dir/etc/profile.d/conda.sh"
fi
EOF
    chmod +x /etc/profile.d/conda.sh
    
    # 确保/etc/bashrc中source该文件
    if [ -f "/etc/bashrc" ] && ! grep -q "/etc/profile.d/conda.sh" /etc/bashrc; then
        echo -e "${YELLOW}添加conda初始化到/etc/bashrc...${NC}"
        echo "[ -f /etc/profile.d/conda.sh ] && . /etc/profile.d/conda.sh" >> /etc/bashrc
    fi
    
    # 为所有用户添加conda初始化到.bashrc
    echo -e "${YELLOW}为用户添加conda初始化到.bashrc...${NC}"
    local all_users=($(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd))
    all_users+=("root")  # 也包括root用户
    
    for user in "${all_users[@]}"; do
        local home_dir
        if [ "$user" = "root" ]; then
            home_dir="/root"
        else
            home_dir="/home/$user"
        fi
        
        local bashrc="$home_dir/.bashrc"
        
        if [ -f "$bashrc" ] && ! grep -q "conda.sh" "$bashrc"; then
            echo -e "${YELLOW}添加conda初始化到 $user 的.bashrc...${NC}"
            cat >> "$bashrc" << EOF

# >>> conda initialize >>>
# !! 由KTransformers安装脚本添加 !!
export PATH="$conda_dir/bin:\$PATH"
if [ -f "$conda_dir/etc/profile.d/conda.sh" ]; then
    . "$conda_dir/etc/profile.d/conda.sh"
else
    export PATH="$conda_dir/bin:\$PATH"
fi
# <<< conda initialize <<<
EOF
            
            # 设置正确的所有权
            if [ "$user" != "root" ] && [ "$(id -u)" -eq 0 ]; then
                chown $user:$user "$bashrc"
            fi
        fi
    done
    
    echo -e "${GREEN}✓ 已更新所有用户的PATH${NC}"
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
    
    # 查看当前pip配置
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
    
    # 使用用户选择的国内代理配置
    if [ $USE_GHPROXY -eq 1 ]; then
        echo -e "${YELLOW}根据您的选择，将设置pip源为USTC源...${NC}"
        
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
    echo -e "${BLUE}[步骤 6] 安装GPU版本PyTorch${NC}"
    
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
    log "INFO" "初始化子模块..."
    
    # 更新.gitmodules中的URL以使用代理
    if [ $USE_GHPROXY -eq 1 ] && [ -n "$GHPROXY_URL" ]; then
        log "INFO" "使用代理配置子模块URL..."
        
        # 检查.gitmodules文件是否存在
        if [ -f ".gitmodules" ]; then
            # 备份原始.gitmodules文件
            cp .gitmodules .gitmodules.backup
            
            # 替换顶级.gitmodules中的URL
            sed -i "s#url = https://github.com/#url = ${GHPROXY_URL}/https://github.com/#g" .gitmodules
            
            log "INFO" "更新.gitmodules中的URL以使用代理..."
            git submodule sync
        fi
    fi
    
    # 初始化顶级子模块
    git submodule update --init
    
    # 递归处理所有子模块及其嵌套子模块的URL
    if [ $USE_GHPROXY -eq 1 ] && [ -n "$GHPROXY_URL" ]; then
        log "INFO" "递归更新所有子模块的URL以使用代理..."
        
        # 获取所有子模块路径
        submodule_paths=$(git config --file .gitmodules --get-regexp path | awk '{ print $2 }')
        
        for submodule_path in $submodule_paths; do
            log "INFO" "处理子模块: $submodule_path"
            
            # 进入子模块目录
            if [ -d "$submodule_path" ]; then
                (cd "$submodule_path" && {
                    # 检查子模块中是否有自己的.gitmodules文件
                    if [ -f ".gitmodules" ]; then
                        log "INFO" "更新子模块 $submodule_path 中的.gitmodules"
                        
                        # 备份原始.gitmodules文件
                        cp .gitmodules .gitmodules.backup
                        
                        # 替换子模块中的.gitmodules中的URL
                        sed -i "s#url = https://github.com/#url = ${GHPROXY_URL}/https://github.com/#g" .gitmodules
                        
                        # 同步子模块中的子模块
                        git submodule sync
                        
                        # 初始化和更新嵌套的子模块
                        git submodule update --init
                        
                        # 递归处理嵌套子模块
                        nested_submodule_paths=$(git config --file .gitmodules --get-regexp path | awk '{ print $2 }')
                        for nested_path in $nested_submodule_paths; do
                            log "INFO" "处理嵌套子模块: $nested_path"
                            # 进入嵌套子模块目录
                            if [ -d "$nested_path" ]; then
                                (cd "$nested_path" && {
                                    if [ -f ".gitmodules" ]; then
                                        log "INFO" "更新嵌套子模块 $nested_path 中的.gitmodules"
                                        cp .gitmodules .gitmodules.backup
                                        sed -i "s#url = https://github.com/#url = ${GHPROXY_URL}/https://github.com/#g" .gitmodules
                                        git submodule sync
                                        git submodule update --init
                                    fi
                                })
                            fi
                        done
                    fi
                })
            fi
        done
    fi
    
    # 最后再执行一次完整的递归更新
    log "INFO" "完成子模块初始化..."
    git submodule update --init --recursive
    
    log "SUCCESS" "子模块初始化完成"
    return 0
}

# 7. 安装libnuma库
install_libnuma() {
    echo -e "${BLUE}[步骤 7] 安装libnuma库${NC}"
    
    # 检查是否已安装
    if ldconfig -p | grep -q "libnuma.so"; then
        echo -e "${GREEN}✓ libnuma已安装${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}libnuma未安装，尝试安装...${NC}"
    
    # 尝试使用apt安装
    if command_exists apt-get; then
        echo -e "${YELLOW}使用apt安装libnuma-dev...${NC}"
        apt-get update && apt-get install -y libnuma-dev
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ libnuma-dev安装成功${NC}"
            return 0
        else
            echo -e "${RED}× apt安装libnuma-dev失败${NC}"
        fi
    fi
    
    # 尝试使用yum安装
    if command_exists yum; then
        echo -e "${YELLOW}使用yum安装numactl-devel...${NC}"
        yum install -y numactl-devel
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ numactl-devel安装成功${NC}"
            return 0
        else
            echo -e "${RED}× yum安装numactl-devel失败${NC}"
        fi
    fi
    
    # 尝试使用dnf安装
    if command_exists dnf; then
        echo -e "${YELLOW}使用dnf安装numactl-devel...${NC}"
        dnf install -y numactl-devel
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ numactl-devel安装成功${NC}"
            return 0
        else
            echo -e "${RED}× dnf安装numactl-devel失败${NC}"
        fi
    fi
    
    echo -e "${RED}× 无法安装libnuma库，请手动安装后再继续${NC}"
    return 1
}

# 8. 设置USE_NUMA环境变量
set_use_numa() {
    echo -e "${BLUE}[步骤 8] 设置USE_NUMA环境变量${NC}"
    
    if [ $USE_NUMA -eq 1 ]; then
        export USE_NUMA=1
        echo -e "${GREEN}✓ 已启用USE_NUMA环境变量${NC}"
    else
        echo -e "${YELLOW}未启用USE_NUMA环境变量${NC}"
    fi
    
    return 0
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
export PATH="/usr/local/conda/bin:\$PATH"

# 初始化conda
if [ -f "/usr/local/conda/etc/profile.d/conda.sh" ]; then
    . "/usr/local/conda/etc/profile.d/conda.sh"
elif [ -f "/etc/profile.d/conda.sh" ]; then
    . "/etc/profile.d/conda.sh"
else
    echo "conda.sh not found, conda may not be properly installed"
    echo "尝试使用PATH中的conda"
fi

# 激活环境
conda activate $ENV_NAME

# 切换到安装目录
cd "$INSTALL_DIR"

# 设置USE_NUMA环境变量
if [ "$USE_NUMA" = "1" ]; then
    export USE_NUMA=1
    echo "已启用USE_NUMA环境变量"
fi

# 显示当前环境信息
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                       环境激活信息                                 "
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "➤ 当前环境: \$(conda info --envs | grep '*' || echo '未激活任何环境')"
echo "➤ Python: \$(which python || echo '未找到Python')"
echo "➤ 当前目录: \$(pwd)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
EOF
    
    chmod +x activate_env.sh
    
    # 尝试激活环境
    local activation_success=false
    
    # 首先尝试系统安装的conda
    if [ -f "/usr/local/conda/etc/profile.d/conda.sh" ]; then
        echo -e "${YELLOW}尝试使用系统级conda激活环境...${NC}"
        . "/usr/local/conda/etc/profile.d/conda.sh"
        if conda activate $ENV_NAME 2>/dev/null; then
            activation_success=true
            echo -e "${GREEN}✓ 成功激活环境 $ENV_NAME${NC}"
        fi
    fi
    
    # 如果失败，尝试/etc/profile.d中的conda
    if [ "$activation_success" = false ] && [ -f "/etc/profile.d/conda.sh" ]; then
        echo -e "${YELLOW}尝试使用/etc/profile.d/conda.sh激活环境...${NC}"
        . "/etc/profile.d/conda.sh"
        if conda activate $ENV_NAME 2>/dev/null; then
            activation_success=true
            echo -e "${GREEN}✓ 成功激活环境 $ENV_NAME${NC}"
        fi
    fi
    
    # 如果以上都失败，尝试直接使用conda命令
    if [ "$activation_success" = false ] && command_exists conda; then
        echo -e "${YELLOW}尝试直接使用conda命令激活环境...${NC}"
        conda activate $ENV_NAME 2>/dev/null
        if [ $? -eq 0 ]; then
            activation_success=true
            echo -e "${GREEN}✓ 成功激活环境 $ENV_NAME${NC}"
        fi
    fi
    
    # 如果所有尝试都失败
    if [ "$activation_success" = false ]; then
        echo -e "${YELLOW}无法自动激活环境 $ENV_NAME${NC}"
        echo -e "${YELLOW}完成安装后，请运行以下命令激活环境:${NC}"
        echo -e "${BLUE}source $(pwd)/activate_env.sh${NC}"
    fi
    
    # 进入安装目录
    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR" || echo -e "${RED}切换到 $INSTALL_DIR 失败${NC}"
    else
        echo -e "${RED}目录 $INSTALL_DIR 不存在${NC}"
    fi
    
    echo -e "${GREEN}✓ 已创建激活脚本: $(pwd)/activate_env.sh${NC}"
    
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

# 安装Flash Attention
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

    # 克隆并编译
    local temp_dir=$(mktemp -d)
    cd "$temp_dir" || {
        log "ERROR" "无法创建临时目录"
        return 1
    }

    if git clone https://github.com/Dao-AILab/flash-attention.git; then
        cd flash-attention || {
            log "ERROR" "无法进入flash-attention目录"
            return 1
        }

        log "INFO" "使用ninja编译并安装..."
        if python setup.py install --use_ninja; then
            log "SUCCESS" "Flash Attention从源码编译安装成功"
            return 0
        else
            log "ERROR" "Flash Attention从源码编译安装失败"
            return 1
        fi
    else
        log "ERROR" "克隆Flash Attention仓库失败"
        return 1
    fi
}

# 验证conda安装路径并修复环境
validate_conda_path() {
    local expected_path="$1"
    local detected_path=$(which conda 2>/dev/null)
    
    echo -e "${YELLOW}验证conda安装路径...${NC}"
    echo -e "${YELLOW}预期路径: $expected_path/bin/conda${NC}"
    
    if [ -z "$detected_path" ]; then
        echo -e "${RED}× 无法在PATH中找到conda${NC}"
        # 添加到当前PATH
        export PATH="$expected_path/bin:$PATH"
        echo -e "${YELLOW}已添加 $expected_path/bin 到当前PATH${NC}"
    elif [ "$detected_path" != "$expected_path/bin/conda" ]; then
        echo -e "${YELLOW}检测到的conda路径与预期不符: $detected_path${NC}"
        
        # 修复bashrc中的路径
        for bashrc in "/root/.bashrc" "/home/$non_root_user/.bashrc"; do
            if [ -f "$bashrc" ]; then
                echo -e "${YELLOW}修正 $bashrc 中的conda路径引用${NC}"
                sed -i -E "s|^export PATH=.*conda.*:|export PATH=$expected_path/bin:\$PATH:|g" "$bashrc"
                sed -i -E "s|^[.] \".*conda/etc/profile.d/conda.sh\"$|. \"$expected_path/etc/profile.d/conda.sh\"|g" "$bashrc"
            fi
        done
        
        # 重新添加到PATH
        export PATH="$expected_path/bin:$PATH"
        echo -e "${GREEN}✓ conda路径已修正${NC}"
    else
        echo -e "${GREEN}✓ conda路径正确: $detected_path${NC}"
    fi
}


# 检查Git镜像站点
check_best_github_site() {
    log "INFO" "检查GitHub连接配置..."
    
    # 根据用户选择设置代理
    if [ $USE_GHPROXY -eq 1 ]; then
        log "INFO" "使用国内代理服务加速GitHub访问"
        log "SUCCESS" "已配置代理服务器: $GHPROXY_URL"
        
        # 如果存在.gitmodules文件，则修改其中的URL
        if [ -f ".gitmodules" ]; then
            log "INFO" "为git子模块添加代理前缀"
            sed -i.bak "s|https://github.com|${GHPROXY_URL}/https://github.com|g" .gitmodules
            log "SUCCESS" "已为子模块添加代理前缀"
        fi
        
        # 配置git全局代理
        log "DEBUG" "配置git全局代理设置"
        git config --global url."${GHPROXY_URL}/https://github.com/".insteadOf "https://github.com/"
    else
        log "INFO" "将直接连接GitHub，不使用代理"
    fi
    
    return 0
}

# 安装Python依赖
install_python_deps() {
    echo -e "${BLUE}[步骤 10] 安装Python依赖${NC}"
    
    cd "$INSTALL_DIR" || {
        echo -e "${RED}× 无法进入 $INSTALL_DIR 目录${NC}"
        return 1
    }
    
    echo -e "${YELLOW}安装Python依赖...${NC}"
    
    # 查找requirements.txt文件
    if [ -f "requirements.txt" ]; then
        echo -e "${YELLOW}找到requirements.txt，开始安装依赖...${NC}"
        
        # 使用pip安装依赖
        if pip install -r requirements.txt; then
            echo -e "${GREEN}✓ Python依赖安装成功${NC}"
            return 0
        else
            echo -e "${RED}× Python依赖安装失败${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}未找到requirements.txt，尝试安装基本依赖...${NC}"
        
        # 安装基本依赖
        if pip install numpy requests tqdm transformers huggingface_hub; then
            echo -e "${GREEN}✓ 基本Python依赖安装成功${NC}"
            return 0
        else
            echo -e "${RED}× 基本Python依赖安装失败${NC}"
            return 1
        fi
    fi
}

# 编译和构建所需库
build_libraries() {
    log "INFO" "编译和构建所需库"
    
    # 检查llama.cpp子模块是否已正确注册
    if [ -d "third_party/llama.cpp" ] && [ -f "third_party/llama.cpp/CMakeLists.txt" ]; then
        log "SUCCESS" "llama.cpp子模块已正确注册，跳过构建"
    else
        log "ERROR" "llama.cpp子模块未正确注册，请检查子模块初始化"
        return 1
    fi
    
    # 1. 更新libstdc++6
    log "INFO" "更新libstdc++6"
    
    if ! command_exists add-apt-repository; then
        log "WARN" "add-apt-repository命令不存在，尝试安装..."
        DEBIAN_FRONTEND=noninteractive apt-get update -y && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common
    fi
    
    if command_exists add-apt-repository; then
        if add-apt-repository ppa:ubuntu-toolchain-r/test -y && \
           DEBIAN_FRONTEND=noninteractive apt-get update -y && \
           DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade libstdc++6; then
            log "SUCCESS" "libstdc++6更新成功"
        else
            log "ERROR" "libstdc++6更新失败"
            log "WARN" "将继续安装过程，但可能影响某些运行时功能"
        fi
    else
        log "ERROR" "无法安装add-apt-repository工具，跳过libstdc++6更新"
        log "WARN" "将继续安装过程，但可能影响某些运行时功能"
    fi
    
    # 2. 安装libstdcxx-ng
    log "INFO" "安装libstdcxx-ng"
    if retry_command_with_logging "conda install -c conda-forge libstdcxx-ng -y" 300; then
        log "SUCCESS" "libstdcxx-ng安装成功"
    else
        log "ERROR" "libstdcxx-ng安装失败"
        log "WARN" "将继续安装过程，但可能影响某些运行时功能"
    fi
    
    return 0
}

# 安装KTransformers
install_ktransformers() {
    log "INFO" "安装KTransformers"
    
    if [ ! -d "$INSTALL_DIR" ]; then
        log "ERROR" "目录 $INSTALL_DIR 不存在"
        return 1
    fi
    
    cd "$INSTALL_DIR" || {
        log "ERROR" "无法进入 $INSTALL_DIR 目录"
        return 1
    }
    
    # 首先尝试使用make
    if ! command_exists make; then
        log "ERROR" "make命令不存在，尝试安装..."
        DEBIAN_FRONTEND=noninteractive apt-get update -y && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential
        
        if ! command_exists make; then
            log "ERROR" "无法安装make工具，跳过make dev_install步骤"
            log "WARN" "尝试使用pip直接安装..."
            
            if pip install -e .; then
                log "SUCCESS" "使用pip安装成功"
                return 0
            else
                log "ERROR" "使用pip安装也失败"
                log "WARN" "您可能需要手动执行安装:"
                log "WARN" "1. 安装build-essential"
                log "WARN" "2. 进入 $INSTALL_DIR 目录"
                log "WARN" "3. 执行 make dev_install 或 pip install -e ."
                return 1
            fi
        fi
    fi
    
    log "INFO" "开始执行make dev_install（这可能需要一些时间）..."
    log "INFO" "编译过程中可能会显示一些警告，这是正常现象"
    
    local make_output=""
    local make_error_file="$INSTALL_DIR/make_error.log"
    
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] 开始执行make dev_install..." > "$make_error_file"
    
    if make_output=$(make dev_install 2>&1); then
        log "SUCCESS" "make dev_install执行成功"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] make dev_install执行成功" >> "$make_error_file"
        return 0
    else
        local exit_code=$?
        log "ERROR" "make dev_install执行失败 (错误码: $exit_code)"
        log "WARN" "编译错误已保存到 $make_error_file"
        
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] make dev_install执行失败 (错误码: $exit_code)" >> "$make_error_file"
        echo "==================== 错误输出 ====================" >> "$make_error_file"
        echo "$make_output" >> "$make_error_file"
        echo "==================================================" >> "$make_error_file"
        
        log "WARN" "错误摘要:"
        echo "$make_output" | tail -n 15
        
        log "WARN" "尝试使用pip直接安装..."
        if pip install -e .; then
            log "SUCCESS" "使用pip安装成功"
            return 0
        else
            log "ERROR" "使用pip安装也失败"
            log "WARN" "将继续安装过程，但功能可能不完整"
            return 1
        fi
    fi
}

# 完成消息
completion_message() {
    echo -e "\n${BLUE}===== 安装完成信息 =====${NC}\n"
    
    echo -e "${GREEN}✓ 系统检查:${NC}"
    echo -e "  ○ 目录: ${GREEN}${INSTALL_DIR}${NC}"
    
    if command_exists python; then
        python_version=$(python --version 2>&1)
        echo -e "  ○ Python: ${GREEN}$python_version${NC}"
    else
        echo -e "  ○ Python: ${YELLOW}未找到${NC}"
    fi
    
    if command_exists conda; then
        conda_version=$(conda --version 2>&1)
        echo -e "  ○ Conda: ${GREEN}${conda_version}${NC}"
    else
        echo -e "  ○ Conda: ${YELLOW}未找到${NC}"
    fi
    
    if command_exists nvcc; then
        cuda_version=$(nvcc --version | grep "release" | awk '{print $6}' | sed 's/,//')
        echo -e "  ○ CUDA: ${GREEN}${cuda_version}${NC}"
    else
        echo -e "  ○ CUDA: ${YELLOW}未找到${NC}"
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
    echo -e "${PURPLE}KTransformers 安装脚本${NC}"
    echo -e "${PURPLE}当前时间: $(date)${NC}\n"
    
    # 检查并安装必要的工具
    check_required_tools
    
    # 测试GitHub连通性
    test_github_connectivity
    
    # 检查并设置pip源
    check_and_set_pip_mirror
    
    # 检查并安装构建工具
    check_build_tools
    
    # 检测CUDA版本
    detect_pytorch_cuda_version
    
    # 用于跟踪安装状态的变量
    local install_status=0
    
    # 执行各个步骤
    check_root || exit 1
    
    install_git || exit 1
    
    # 克隆仓库，添加更详细的错误处理
    if ! clone_repo; then
        echo -e "${RED}× 仓库克隆失败，请检查网络连接和目录权限${NC}"
        echo -e "${YELLOW}您可以尝试手动克隆仓库:${NC}"
        echo -e "  ${BLUE}git clone https://github.com/kvcache-ai/ktransformers.git $INSTALL_DIR${NC}"
        if [ $USE_GHPROXY -eq 1 ]; then
            echo -e "或者使用ghfast.top代理:"
            echo -e "  ${BLUE}git clone ${GHPROXY_URL}/https://github.com/kvcache-ai/ktransformers.git $INSTALL_DIR${NC}"
        fi
        exit 1
    fi
    
    # 安装conda和创建环境 - 关键步骤，失败直接退出
    install_conda || { echo -e "${RED}× Conda安装失败，无法继续安装${NC}"; exit 1; }

    create_conda_env || { echo -e "${RED}× Conda环境创建失败，无法继续安装${NC}"; exit 1; }
    
    # 激活conda环境
    activate_conda_env || { echo -e "${RED}× Conda环境激活失败，无法继续安装${NC}"; exit 1; }
    
    # 安装PyTorch
    install_pytorch || { echo -e "${RED}× PyTorch安装失败，可能导致功能受限${NC}"; install_status=1; }
    
    # 初始化git子模块
    init_git_submodules || install_status=1
    
    # 添加缺失的步骤
    install_libnuma || install_status=1
    set_use_numa || install_status=1
    
    # 编译和构建所需库
    build_libraries || install_status=1
    
    # 安装 Flash Attention
    echo -e "${BLUE}[步骤 9] 安装Flash Attention${NC}"
    install_flash_attn || install_status=1
    
    # 安装 FlashInfer
    echo -e "${BLUE}[步骤 10] 安装FlashInfer${NC}"
    download_flashinfer || install_status=1
    
    # 安装Python依赖
    install_python_deps || install_status=1
    
    # 安装KTransformers
    install_ktransformers || install_status=1
    
    # 安装完成
    if [ $install_status -eq 0 ]; then
        echo -e "${GREEN}✓ 安装完成！${NC}"
        
        # 如果当前是root用户，将workspace所有权交给非root用户
        if [ "$(id -u)" -eq 0 ]; then
            # 查找适合的非root用户
            local non_root_user=""
            non_root_user=$(who | awk '{print $1}' | grep -v "root" | head -n 1)
            if [ -z "$non_root_user" ]; then
                non_root_user=$SUDO_USER
            fi
            
            if [ -n "$non_root_user" ] && [ "$non_root_user" != "root" ]; then
                echo -e "${YELLOW}将workspace所有权交给用户: $non_root_user${NC}"
                
                # 确保workspace存在
                if [ -d "$INSTALL_DIR" ]; then
                    chown -R $non_root_user:$non_root_user "$INSTALL_DIR"
                    echo -e "${GREEN}✓ 已更改workspace所有权${NC}"
                    echo "[$(date +"%Y-%m-%d %H:%M:%S")] 已将workspace所有权交给: $non_root_user" >> "$LOG_FILE"
                else
                    echo -e "${YELLOW}警告: workspace目录不存在${NC}"
                    echo "[$(date +"%Y-%m-%d %H:%M:%S")] 警告: workspace目录不存在" >> "$LOG_FILE"
                fi
                
                # 也更改日志文件的所有权
                if [ -f "$LOG_FILE" ]; then
                    chown $non_root_user:$non_root_user "$LOG_FILE"
                fi
                
                # 更改激活脚本的所有权
                if [ -f "activate_env.sh" ]; then
                    chown $non_root_user:$non_root_user "activate_env.sh"
                fi
            else
                echo -e "${YELLOW}未找到适合的非root用户，workspace保持当前所有权${NC}"
                echo "[$(date +"%Y-%m-%d %H:%M:%S")] 未找到适合的非root用户，workspace保持当前所有权" >> "$LOG_FILE"
            fi
        fi
        
        completion_message
    else
        echo -e "${YELLOW}[WARN] 安装过程中有部分步骤失败，请查看详细日志${NC}"
        echo -e "${YELLOW}[INFO] 你可以尝试修复问题后重新运行脚本${NC}"
    fi
}

# 运行主函数
main "$@"









