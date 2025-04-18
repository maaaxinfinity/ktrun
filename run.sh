#!/bin/bash

# 脚本版本信息
# 最后更新: 2025-04-19
# 版本: 1.1.4
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
PURPLE='\033[1;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# 全局变量
#--------------------
# 安装配置
INSTALL_DIR=""                  # 安装目录，将在select_ktrans_version中设置
ENV_INSTALL_DIR=""              # 环境安装目录，将在configure_installation中设置
CONDA_BASE_DIR=""               # Conda基础目录，将在configure_installation中设置
ENV_NAME=""                     # Conda环境名称，将基于选择的版本号自动生成
MAX_JOBS=$(nproc)               # 编译使用的最大线程数
USE_NUMA=0                      # 是否启用NUMA环境变量（默认不启用）
SCRIPT_DIR="$(pwd)"


# 网络与代理配置
USE_GHPROXY=0                   # 是否使用国内代理加速
GHPROXY_URL="https://ghfast.top" # 默认代理服务器URL

# 运行模式设置
DEBUG_MODE=0                    # 调试模式开关
GIT_DEBUG_MODE=0                # Git详细日志开关
FAST_MODE=0                     # 快速安装模式开关

# 版本设置
KTRANS_VERSION="v0.2.4post1"         # KTransformers 版本，默认使用最新版本

# 内部使用变量
LOG_FILE=""                     # 日志文件路径

# 显示KTransformers Logo函数
show_ktransformers_logo() {
    echo "+=======================================+"
    echo -e "|\033[1;35m╦\033[1;35m╔═\033[1;37m┌┬┐\033[1;37m┬─┐\033[1;37m┌─┐\033[1;37m┌┐┌\033[1;37m┌─┐\033[1;37m┌─┐\033[1;37m┌─┐\033[1;37m┬─┐\033[1;37m┌┬┐\033[1;37m┌─┐\033[1;37m┬─┐\033[1;37m┌─┐\033[0m|"
    echo -e "|\033[1;35m╠\033[1;35m╩╗\033[1;37m │ \033[1;37m├┬┘\033[1;37m├─┤\033[1;37m│││\033[1;37m└─┐\033[1;37m├┤ \033[1;37m│ │\033[1;37m├┬┘\033[1;37m│││\033[1;37m├┤ \033[1;37m├┬┘\033[1;37m└─┐\033[0m|"
    echo -e "|\033[1;35m╩\033[1;35m ╩\033[1;37m ┴ \033[1;37m┴└─\033[1;37m┴ ┴\033[1;37m┘└┘\033[1;37m└─┘\033[1;37m└  \033[1;37m└─┘\033[1;37m┴└─\033[1;37m┴ ┴\033[1;37m└─┘\033[1;37m┴└─\033[1;37m└─┘\033[0m|"
    echo "+=======================================+"
}

# 版本选择函数
select_ktrans_version() {
    
    # 定义版本列表
    local versions=(
        "v0.2.2"
        "v0.2.2rc1"
        "v0.2.2rc2"
        "v0.2.3"
        "v0.2.3post1"
        "v0.2.3post2"
        "v0.2.4"
        "v0.2.4post1"
    )
    
    # 定义推荐版本
    local recommended=(
        "v0.2.2"
        "v0.2.3post2"
        "v0.2.4post1"
    )
    
    # 默认版本和索引
    local default_version="v0.2.4post1"
    local default_index=8
    
    # 构建选项数组
    local version_options=()
    for version in "${versions[@]}"; do
        local is_recommended=""
        for rec in "${recommended[@]}"; do
            if [ "$version" = "$rec" ]; then
                # 使用echo -e来处理ANSI颜色转义序列
                is_recommended=" $(echo -e "${CYAN}(R)${NC}")"
                break
            fi
        done
        version_options+=("$version$is_recommended")
    done
    
    # 显示选择界面
    show_multi_selection_menu "选择KTransformers版本(R为推荐版本)" "$default_version" "$default_index" "${version_options[@]}"
    local choice=$?
    
    # 设置选择的版本
    if [ $choice -ge 1 ] && [ $choice -le ${#versions[@]} ]; then
        KTRANS_VERSION="${versions[$((choice-1))]}"
        
        # 根据版本号生成环境名称和安装目录名
        # 去掉v前缀,然后去掉小数点
        local version_str=$(echo $KTRANS_VERSION | sed 's/^v//' | sed 's/\.//g')
        ENV_NAME="ktrans_${version_str}"
        
        # 设置默认安装目录为当前目录下的workspace/kt_版本号
        local workspace_dir="$(pwd)/workspace"
        INSTALL_DIR="${workspace_dir}/kt_${version_str}"
        
        echo -e "${GREEN}已选择版本: $KTRANS_VERSION${NC}"
        echo -e "${GREEN}环境名称将设为: $ENV_NAME${NC}"
        echo -e "${GREEN}默认安装目录: $INSTALL_DIR${NC}"
        return 0  # 明确返回成功状态
    else
        echo -e "${RED}无效的选择${NC}"
        return 1
    fi
}

# 添加多选项选择函数
show_multi_selection_menu() {
    local title="$1"
    local default_value="$2"  # 默认值显示文本
    local default_index="$3"  # 新增：默认选中索引
    shift 3
    local options=("$@")
    local num_options=${#options[@]}
    local selected=1
    local statuses=()
    
    # 根据默认值设置初始选择
    if [ -n "$default_index" ]; then
        selected=$default_index
    elif [ "$default_value" = "False" ]; then
        selected=1  # 默认选择"否"选项
    elif [ "$default_value" = "True" ]; then
        selected=0  # 默认选择"是"选项
    fi
    
    # 初始化状态数组
    for ((i=0; i<num_options; i++)); do
        if [ $i -eq $((selected-1)) ]; then
            statuses+=("\033[1;32m●\033[0m")  # 绿色高亮
        else
            statuses+=("○")
        fi
    done
    
    # 清屏并显示选项
    render_menu() {
        clear  # 清屏
        show_ktransformers_logo
        echo -e "\n${BLUE}===== KTransformers 安装配置 =====${NC}"
        
        # 显示选项
        echo -e "\n╭─ ${title}"
        if [ -n "$default_value" ]; then
            echo -e "│"
            echo -e "├─ 默认值: ${GREEN}${default_value}${NC}"
        fi
        echo -e "│"
        
        # 判断是否需要拆分显示
        if [ $num_options -gt 4 ]; then
            # 计算每行显示的选项数
            local items_per_row=4
            local rows=$(( (num_options + items_per_row - 1) / items_per_row ))
            
            # 设置固定宽度值
            local col_widths=(20 20 20 20)
            
            # 显示除最后一行外的选项
            for ((row=0; row<rows-1; row++)); do
                echo -ne "├─ "
                for ((col=0; col<items_per_row; col++)); do
                    local i=$((row*items_per_row + col))
                    if [ $i -lt $num_options ]; then
                        echo -ne "${statuses[$i]} "
                        echo -ne "${options[$i]}"
                        
                        if [ $col -lt $((items_per_row-1)) ] && [ $i -lt $((num_options-1)) ]; then
                            # 剥离颜色代码计算真实长度
                            local plain_option=$(echo "${options[$i]}" | sed 's/\x1b\[[0-9;]*m//g')
                            printf "%*s" $((col_widths[$col] - ${#plain_option})) ""
                            echo -ne "| "
                        fi
                    fi
                done
                echo -e ""
            done
            
            # 显示最后一行选项
            echo -ne "╰─ "
            for ((col=0; col<items_per_row; col++)); do
                local i=$(((rows-1)*items_per_row + col))
                if [ $i -lt $num_options ]; then
                    echo -ne "${statuses[$i]} "
                    echo -ne "${options[$i]}"
                    
                    if [ $col -lt $((items_per_row-1)) ] && [ $i -lt $((num_options-1)) ]; then
                        # 剥离颜色代码计算真实长度
                        local plain_option=$(echo "${options[$i]}" | sed 's/\x1b\[[0-9;]*m//g')
                        printf "%*s" $((col_widths[$col] - ${#plain_option})) ""
                        echo -ne "| "
                    fi
                fi
            done
            echo -e ""
        else
            # 原来的单行显示方式
            echo -ne "╰─ "
            for ((i=0; i<num_options; i++)); do
                echo -ne "${statuses[$i]} ${options[$i]}"
                if [ $i -lt $((num_options-1)) ]; then
                    echo -ne " | "
                fi
            done
            echo -e ""
        fi
        
        echo -e "\n使用方向键选择，回车确认"
    }
    
    # 初始渲染
    render_menu
    
    # 用于存储上一次的选择
    local last_selected=$selected
    
    while true; do
        # 读取用户输入
        read -s -n 1 key
        
        # 处理方向键
        if [[ $key == $'\e' ]]; then
            read -s -n 2 rest
            if [[ $rest == "[C" ]]; then  # 右方向键
                statuses[$((selected-1))]="○"
                selected=$((selected % num_options + 1))
                statuses[$((selected-1))]="\033[1;32m●\033[0m"
                last_selected=$selected
                render_menu
            elif [[ $rest == "[D" ]]; then  # 左方向键
                statuses[$((selected-1))]="○"
                selected=$(((selected - 2 + num_options) % num_options + 1))
                statuses[$((selected-1))]="\033[1;32m●\033[0m"
                last_selected=$selected
                render_menu
            fi
        elif [[ $key == "" ]]; then  # 回车键
            # 保存当前选择结果
            local result=$selected
            
            echo -e "\n${GREEN}✓ 已选择: ${options[$((result-1))]}${NC}"
            sleep 0.3
            
            return $result
        fi
    done
}

# 添加路径选择函数
select_or_input_path() {
    local title="$1"
    local default_path="$2"
    local path_type="$3"
    local result_path=""
    
    while true; do
        echo -e "\n╭─ ${title}"
        echo -e "│"
        echo -e "├─ 默认路径: ${GREEN}${default_path}${NC}"
        echo -e ""
        
        show_multi_selection_menu "是否使用默认${path_type}路径?" "True" 1 "True" "False"
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

}

# 用户选择函数
select_install_user() {
    echo -e "\n${BLUE}===== 选择安装用户 =====${NC}"
    
    # 获取所有普通用户列表
    local all_users=($(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd))
    all_users=("root" "${all_users[@]}")
    
    # 准备用户选项数组（包含用户名和主目录信息）
    local user_options=()
    local default_user=""
    local default_home=""
    
    # 设置默认用户优先级：SUDO_USER > 第一个非root用户 > root
    if [ -n "$SUDO_USER" ]; then
        default_user="$SUDO_USER"
        default_home="/home/$SUDO_USER"
    elif [ ${#all_users[@]} -gt 1 ]; then
        # 如果有非root用户，选择第一个非root用户作为默认
        default_user="${all_users[1]}"  # 索引1是第一个非root用户
        default_home="/home/${all_users[1]}"
    else
        # 如果只有root用户
        default_user="root"
        default_home="/root"
    fi
    
    # 构建选项数组
    for user in "${all_users[@]}"; do
        local home_dir
        if [ "$user" = "root" ]; then
            home_dir="/root"
        else
            # 检查用户主目录是否为符号链接
            if [ -L "/home/$user" ]; then
                home_dir=$(readlink -f "/home/$user")
            else
                home_dir="/home/$user"
            fi
        fi
        user_options+=("$user ($home_dir)")
    done
    
    # 找到默认用户在列表中的位置
    local default_index=0
    for i in "${!all_users[@]}"; do
        if [ "${all_users[$i]}" = "$default_user" ]; then
            default_index=$((i+1))
            break
        fi
    done
    
    # 使用新的多选项选择函数，显示默认用户
    show_multi_selection_menu "选择安装用户" "${default_user} (${default_home})" "$default_index" "${user_options[@]}"
    local choice=$?
    
    # 设置选中的用户
    INSTALL_USER="${all_users[$((choice-1))]}"
    if [ "$INSTALL_USER" = "root" ]; then
        INSTALL_HOME="/root"
    else
        # 检查用户主目录是否为符号链接
        if [ -L "/home/$INSTALL_USER" ]; then
            INSTALL_HOME=$(readlink -f "/home/$INSTALL_USER")
            echo -e "${YELLOW}用户 $INSTALL_USER 的主目录是符号链接，解析为: $INSTALL_HOME${NC}"
        else
            INSTALL_HOME="/home/$INSTALL_USER"
        fi
    fi
    
    # 更新安装目录
    INSTALL_DIR="$INSTALL_HOME/ktransformers"
    
    # 验证目录权限
    if [ ! -d "$INSTALL_HOME" ]; then
        echo -e "${RED}× 用户主目录不存在: $INSTALL_HOME${NC}"
        return 1
    fi
    
    # 检查目录权限
    if ! sudo -u "$INSTALL_USER" mkdir -p "$INSTALL_DIR" 2>/dev/null; then
        echo -e "${RED}× 无法在用户目录创建安装目录${NC}"
        return 1
    fi
    
    # 清理测试目录
    rmdir "$INSTALL_DIR"
    
    return 0
}


# 用户配置部分
configure_installation() {
        show_ktransformers_logo

    # 选择安装用户
    if ! select_install_user; then
        echo -e "${RED}× 用户选择失败${NC}"
        exit 1
    fi
    
    # 选择KTransformers版本
    if ! select_ktrans_version; then
        echo -e "${RED}× 版本选择失败${NC}"
        exit 1
    fi

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
        local default_install_dir="${INSTALL_DIR:-/opt/ktransformers}"
        show_multi_selection_menu "是否使用默认安装路径?" "${default_install_dir}" 1 "True" "False"
        local path_choice=$?
        
        if [ $path_choice -eq 1 ]; then
            echo -e "${GREEN}✓ 使用默认安装路径: ${default_install_dir}${NC}"
            sleep 0.3
            INSTALL_DIR="${default_install_dir}"
        else
            read -p "请输入安装路径: " user_path
            if [ -n "$user_path" ]; then
                echo -e "${GREEN}✓ 使用自定义安装路径: ${user_path}${NC}"
                sleep 0.3
                INSTALL_DIR="$user_path"
            else
                echo -e "${YELLOW}路径不能为空，使用默认路径: ${default_install_dir}${NC}"
                sleep 0.3
                INSTALL_DIR="${default_install_dir}"
            fi
        fi

        INSTALL_DIR=$(echo "$INSTALL_DIR" | tr -d '\r')
        
        show_multi_selection_menu "是否使用默认环境名称?" "${ENV_NAME}" 1 "True" "False"
        local env_choice=$?
        
        if [ $env_choice -eq 2 ]; then
            read -p "请输入Conda环境名称: " user_env_name
            if [ -n "$user_env_name" ]; then
                ENV_NAME="$user_env_name"
                echo -e "${GREEN}✓ Conda环境名称已更新为: ${ENV_NAME}${NC}"
                sleep 0.3
            else
                echo -e "${YELLOW}使用默认环境名称: ${ENV_NAME}${NC}"
                sleep 0.3
            fi
        else
            echo -e "${GREEN}✓ 使用默认环境名称: ${ENV_NAME}${NC}"
            sleep 0.3
        fi
        
        show_multi_selection_menu "是否启用USE_NUMA环境变量?" "False" 2 "True" "False"
        local numa_choice=$?
        
        if [ $numa_choice -eq 1 ]; then
            USE_NUMA=1
            echo -e "${GREEN}✓ 已启用USE_NUMA环境变量${NC}"
            sleep 0.3
        else
            USE_NUMA=0
            echo -e "${GREEN}✓ 已禁用USE_NUMA环境变量${NC}"
            sleep 0.3
        fi
        
        show_multi_selection_menu "是否使用国内代理和镜像站点?" "True" 1 "True" "False"
        local proxy_choice=$?
        
        if [ $proxy_choice -eq 1 ]; then
            USE_GHPROXY=1
            echo -e "${GREEN}✓ 已启用国内代理和镜像站点${NC}"
            sleep 0.3
        else
            USE_GHPROXY=0
            echo -e "${GREEN}✓ 已禁用国内代理和镜像站点${NC}"
            sleep 0.3
        fi

        show_multi_selection_menu "是否使用默认线程数?" "${MAX_JOBS}" 1 "True" "False"
        local jobs_choice=$?
        
        if [ $jobs_choice -eq 2 ]; then
            read -p "请输入编译最大线程数: " user_max_jobs
            if [ -n "$user_max_jobs" ] && [ "$user_max_jobs" -gt 0 ] 2>/dev/null; then
                MAX_JOBS="$user_max_jobs"
                echo -e "${GREEN}✓ 编译最大线程数已更新为: ${MAX_JOBS}${NC}"
                sleep 0.3
            else
                echo -e "${YELLOW}使用默认线程数: ${MAX_JOBS}${NC}"
            fi
        else
            echo -e "${GREEN}✓ 使用默认线程数: ${MAX_JOBS}${NC}"
            sleep 0.3
        fi
        
        show_multi_selection_menu "是否启用调试模式?" "False" 2 "True" "False"
        local debug_choice=$?
        
        if [ $debug_choice -eq 1 ]; then
            DEBUG_MODE=1
            echo -e "${GREEN}✓ 已启用调试模式${NC}"
            sleep 0.3
        else
            DEBUG_MODE=0
            echo -e "${GREEN}✓ 已禁用调试模式${NC}"
            sleep 0.3
        fi
    fi
    

    echo -e "\n${BLUE}=== 安装配置摘要 ===${NC}"
    echo -e "${BLUE}● Ktrans版本: ${GREEN}${KTRANS_VERSION}${NC}"
    echo -e "${BLUE}● 安装用户: ${GREEN}${INSTALL_USER}${NC}"
    echo -e "${BLUE}● 安装路径: ${GREEN}${INSTALL_DIR}${NC}"
    echo -e "${BLUE}● Conda环境名称: ${GREEN}${ENV_NAME}${NC}"
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
    

    if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] ${prefix} ${message}" >> "$LOG_FILE"
    elif [ -n "$LOG_FILE" ]; then
        # 尝试创建日志文件目录（如果不存在）
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] ${prefix} ${message}" >> "$LOG_FILE" 2>/dev/null || true
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
    
    LOG_FILE="${SCRIPT_DIR}/ktransformers_install_${timestamp}.log"
    

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
    
    if [ "$(id -u)" -eq 0 ] && [ -n "$INSTALL_USER" ] && [ "$INSTALL_USER" != "root" ]; then
        echo -e "${YELLOW}设置日志文件所有权为用户: $INSTALL_USER${NC}"
        local target_group=$(id -gn $INSTALL_USER 2>/dev/null || echo $INSTALL_USER)
        chown $INSTALL_USER:$target_group "$LOG_FILE"
    elif [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        echo -e "${YELLOW}设置日志文件所有权为sudo用户: $SUDO_USER${NC}"
        local target_group=$(id -gn $SUDO_USER 2>/dev/null || echo $SUDO_USER)
        chown $SUDO_USER:$target_group "$LOG_FILE"
    fi
    

    echo "[$(date +"%Y-%m-%d %H:%M:%S")] 日志文件初始化完成" >> "$LOG_FILE"
    

    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${CYAN}[DEBUG] 日志文件已创建: ${LOG_FILE}${NC}"
        echo -e "${CYAN}[DEBUG] 将记录详细安装过程${NC}"
    fi
    
    export LOG_FILE
}

# 函数：收集系统信息
collect_system_info() {
    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${CYAN}[DEBUG] 正在收集系统信息...${NC}"
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
            echo -e "${CYAN}[DEBUG] 检测到NVIDIA显卡:${NC}"
            nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
        fi
    else
        echo "未找到NVIDIA显卡或nvidia-smi工具" >> "$LOG_FILE"
        if [ $DEBUG_MODE -eq 1 ]; then
            echo -e "${YELLOW}[DEBUG] 未检测到NVIDIA显卡或nvidia-smi工具${NC}"
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
        echo -e "${CYAN}[DEBUG] 命令: $command${NC}"
        echo -e "${CYAN}[DEBUG] 最大尝试次数: $max_attempts, 超时: ${timeout_duration}秒${NC}"
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
                echo -e "${CYAN}[DEBUG] 命令成功执行，耗时: ${duration}秒${NC}"
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

# 检测是否为超级用户
check_root() {
    echo -e "${BLUE}[步骤 0] 检测是否为超级用户${NC}"
    
    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${CYAN}[DEBUG] 当前用户ID: $(id -u)${NC}"
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

#0 检查并安装所有依赖和工具
setup_dependencies() {
    echo -e "${BLUE}[准备工作] 设置系统依赖和工具${NC}"
    
    # 基础工具列表
    local essential_tools=("git" "bc" "wget" "timeout" "sed" "awk" "mktemp")
    # 构建工具列表
    local build_tools=("make" "cmake" "gcc" "g++" "add-apt-repository")
    
    local missing_tools=()
    
    # 1. 检查Git
    log "INFO" "[步骤 1] 检测git"
    if ! command_exists git; then
        log "WARN" "git未安装，将在后续安装"
    else
        log "SUCCESS" "git已安装"
    fi
    
    # 2. 检查所有工具
    log "INFO" "检查基础工具和构建工具"
    for tool in "${essential_tools[@]}" "${build_tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
            log "WARN" "缺少工具: $tool"
        elif [ $DEBUG_MODE -eq 1 ]; then
            log "DEBUG" "$tool 已安装: $(which $tool)"
        fi
    done
    
    # 3. 更新软件包列表
    log "INFO" "更新软件包列表"
    if ! DEBIAN_FRONTEND=noninteractive apt-get update -y; then
        log "ERROR" "更新包管理器失败"
        log "WARN" "将尝试继续安装"
    fi
    
    # 4. 安装缺少的工具
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log "INFO" "正在安装缺少的工具: ${missing_tools[*]}"
        
        log "INFO" "安装构建基础包"
        DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential cmake software-properties-common
        
        for tool in "${missing_tools[@]}"; do
            log "INFO" "安装: $tool"
            
            case "$tool" in
                "git")
                    if ! retry_command_with_logging "apt-get install -y git" 300; then
                        log "ERROR" "git安装失败"
                        return 1
                    fi
                    ;;
                "bc")
                    DEBIAN_FRONTEND=noninteractive apt-get install -y bc
                    ;;
                "wget")
                    DEBIAN_FRONTEND=noninteractive apt-get install -y wget
                    ;;
                "timeout"|"sed"|"awk"|"mktemp")
                    DEBIAN_FRONTEND=noninteractive apt-get install -y coreutils
                    ;;
                "make"|"gcc"|"g++")
                    ;;
                "cmake")
                    ;;
                "add-apt-repository")
                    ;;
                *)
                    DEBIAN_FRONTEND=noninteractive apt-get install -y "$tool"
                    ;;
            esac
            
            if ! command_exists "$tool"; then
                log "ERROR" "工具 $tool 安装失败"
                if [ "$tool" = "git" ]; then
                    return 1  # git是必需的，如果安装失败就退出
                fi
            else
                log "SUCCESS" "已安装: $tool"
            fi
        done
        
        log "SUCCESS" "所有基本工具安装完成 " >> "$LOG_FILE"
    else
        log "SUCCESS" "所有基本工具已安装" >> "$LOG_FILE"
    fi

    return 0
}

# 1. 测试GitHub连通性
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
    log "INFO" "开始克隆KTransformers仓库..."

    INSTALL_DIR=$(echo "$INSTALL_DIR" | tr -d '\r')
    
        log "WARN" "目录 $INSTALL_DIR 已存在"
        echo -e "${YELLOW}[INFO] 目录已存在: $INSTALL_DIR${NC}"
        
        if [ "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
            echo -e "${YELLOW}[WARN] 安装目录不为空${NC}"
            
            show_multi_selection_menu "安装目录不为空，是否继续?" "True" 1 "True" "False"
            local continue_choice=$?
            
            if [ $continue_choice -ne 1 ]; then
                echo -e "${YELLOW}[INFO] 用户选择不继续，退出安装${NC}"
                exit 0
            fi
            
            echo -e "${YELLOW}[INFO] 继续安装${NC}"
            return 0
        fi

        if [ ! -d "$INSTALL_DIR" ]; then
            echo -e "${YELLOW}[INFO] 创建目录: $INSTALL_DIR${NC}"
            mkdir -p "$INSTALL_DIR" || {
                echo -e "${RED}× 无法创建目录: $INSTALL_DIR${NC}"
                return 1
            }
        else
            echo -e "${YELLOW}[INFO] 目录已存在: $INSTALL_DIR${NC}"
        fi

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
        
        # 切换到安装目录
        cd "$INSTALL_DIR" || return 1
        
        # 检出指定版本
        echo -e "${YELLOW}[INFO] 检出版本: ${KTRANS_VERSION}${NC}"
        if git checkout "$KTRANS_VERSION"; then
            echo -e "${GREEN}✓ 成功切换到版本: ${KTRANS_VERSION}${NC}"
        else
            echo -e "${RED}× 无法切换到版本: ${KTRANS_VERSION}，将使用默认分支${NC}"
        fi
        
        return 0
    else
        # 如果使用代理失败，尝试直接连接
        if [ $USE_GHPROXY -eq 1 ]; then
            echo -e "${YELLOW}[WARN] 使用代理克隆失败，尝试直接连接...${NC}"
            
            if git clone "$repo_url" "$INSTALL_DIR"; then
                echo -e "${GREEN}✓ 直接克隆仓库成功${NC}"
                
                # 切换到安装目录
                cd "$INSTALL_DIR" || return 1
                
                # 检出指定版本
                echo -e "${YELLOW}[INFO] 检出版本: ${KTRANS_VERSION}${NC}"
                if git checkout "$KTRANS_VERSION"; then
                    echo -e "${GREEN}✓ 成功切换到版本: ${KTRANS_VERSION}${NC}"
                else
                    echo -e "${RED}× 无法切换到版本: ${KTRANS_VERSION}，将使用默认分支${NC}"
                fi
                
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

    local using_sudo=0
    local real_home=""
    local real_user=""
    local conda_executable=""
    local conda_found_msg=""

    # 确定目标用户和主目录
    if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        using_sudo=1
        real_user="$SUDO_USER"
        real_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        log "INFO" "在sudo模式下操作，目标用户: $real_user, 主目录: $real_home"
    else
        real_user=$(whoami)
        real_home="$HOME"
        # 处理root用户情况
        if [ "$real_user" = "root" ]; then
            real_home="/root"
        fi
        log "INFO" "当前用户: $real_user, 主目录: $real_home"
    fi

    local common_conda_paths=(
        "$real_home/miniconda3"
        "$real_home/anaconda3"
        "$real_home/miniforge3"
        "$real_home/.conda"
    )
    
    for conda_path in "${common_conda_paths[@]}"; do
        if [ -d "$conda_path/bin" ] && [ -x "$conda_path/bin/conda" ]; then
            log "INFO" "在用户目录找到conda安装: $conda_path" >> "$LOG_FILE"
            CONDA_BASE_DIR="$conda_path"
            export PATH="$conda_path/bin:$PATH"
            
            # 验证conda是否可用
            if "$conda_path/bin/conda" --version &> /dev/null; then
                local conda_version=$("$conda_path/bin/conda" --version)
                log "SUCCESS" "✓ 用户目录中的conda可用，版本: $conda_version" >> "$LOG_FILE"
                conda config --set auto_activate_base false
                return 0
            else

                log "WARN" "未找到可用的conda，将在目标用户主目录安装Miniconda..."
                CONDA_BASE_DIR="$real_home/miniconda3"
                log "INFO" "目标安装路径: $CONDA_BASE_DIR"
            fi
        fi
    done

    # 检查目标目录是否已存在且包含conda
    if [ -d "$CONDA_BASE_DIR/bin" ] && [ -x "$CONDA_BASE_DIR/bin/conda" ]; then
         log "WARN" "目标目录 $CONDA_BASE_DIR 已存在且包含conda，可能之前的安装未完成或损坏。将尝试使用它。"
         export PATH="$CONDA_BASE_DIR/bin:$PATH"
         if "$CONDA_BASE_DIR/bin/conda" --version &> /dev/null; then
             local conda_version=$("$CONDA_BASE_DIR/bin/conda" --version)
             log "SUCCESS" "✓ $CONDA_BASE_DIR 中的conda可用，版本: $conda_version" >> "$LOG_FILE"
             conda config --set auto_activate_base false
             return 0
         else
             log "WARN" "$CONDA_BASE_DIR 中的conda无法执行，将继续安装..." >> "$LOG_FILE"
             # 清理旧目录以避免冲突
             log "WARN" "移除旧的 $CONDA_BASE_DIR 以重新安装..." >> "$LOG_FILE"
             rm -rf "$CONDA_BASE_DIR"
         fi
    fi


    # 使用国内或国际镜像
    local miniconda_url=""
    if [ $USE_GHPROXY -eq 1 ]; then
        miniconda_url="https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh"
        log "INFO" "使用清华镜像下载Miniconda" >> "$LOG_FILE"
    else
        miniconda_url="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
        log "INFO" "使用官方源下载Miniconda" >> "$LOG_FILE"
    fi

    # 下载miniconda安装脚本
    log "INFO" "下载Miniconda安装脚本..." >> "$LOG_FILE"
    local miniconda_installer="$TMP_DIR/miniconda.sh" # 使用临时目录
    retry_command_with_logging "wget --quiet --show-progress $miniconda_url -O $miniconda_installer" 300 || {
            log "ERROR" "下载Miniconda失败" >> "$LOG_FILE"
        rm -f "$miniconda_installer"
        return 1
    }

    # 安装conda
    log "INFO" "开始安装conda到: $CONDA_BASE_DIR" >> "$LOG_FILE"
    # 使用 -u 选项尝试更新（如果已存在），-b 批处理模式，-p 指定路径
    bash "$miniconda_installer" -b -u -p "$CONDA_BASE_DIR"
    local install_status=$?

    # 清理安装文件
    rm -f "$miniconda_installer"

    if [ $install_status -ne 0 ]; then
        log "ERROR" "conda安装失败 (退出码: $install_status)" >> "$LOG_FILE"
        return 1
    fi

    # 如果是sudo模式，设置正确的权限
    if [ $using_sudo -eq 1 ]; then
        log "INFO" "设置conda目录权限给用户: $real_user" >> "$LOG_FILE"
        chown -R "$real_user:$(id -gn $real_user 2>/dev/null || echo $real_user)" "$CONDA_BASE_DIR" || log "WARN" "设置 $CONDA_BASE_DIR 权限失败" >> "$LOG_FILE"
    fi

    # 确保新安装的conda在当前会话PATH中
    export PATH="$CONDA_BASE_DIR/bin:$PATH"
    log "INFO" "已将新安装的conda路径添加到当前会话PATH: $CONDA_BASE_DIR/bin" >> "$LOG_FILE"

    # 验证安装
    if "$CONDA_BASE_DIR/bin/conda" --version &> /dev/null; then
        log "SUCCESS" "✓ conda安装成功且可用" >> "$LOG_FILE"
        local conda_version=$("$CONDA_BASE_DIR/bin/conda" --version)
        log "INFO" "conda版本: $conda_version" >> "$LOG_FILE"

        # 初始化conda (将配置写入用户的 .bashrc)
        log "INFO" "初始化conda (修改 $real_home/.bashrc)..." >> "$LOG_FILE"
        # 需要确保以目标用户身份执行conda init
        if [ $using_sudo -eq 1 ]; then
            sudo -u "$real_user" "$CONDA_BASE_DIR/bin/conda" init bash || log "WARN" "以用户 $real_user 初始化conda失败"
        else
            "$CONDA_BASE_DIR/bin/conda" init bash || log "WARN" "初始化conda失败"
        fi

        log "INFO" "配置conda默认设置" >> "$LOG_FILE"
        conda config --set auto_activate_base false

        log "SUCCESS" "conda安装和初始化完成" >> "$LOG_FILE"
        
        return 0
    else
        log "ERROR" "conda安装后验证失败，无法执行 $CONDA_BASE_DIR/bin/conda" >> "$LOG_FILE"
        return 1
    fi
}

# 4. 使用conda创建环境
create_conda_env() {
    echo -e "${BLUE}[步骤 4] 创建conda环境${NC}"

    # 环境将创建在conda的默认环境目录下

    echo -e "${GREEN}使用环境名称: $ENV_NAME${NC}"

    # 创建环境
    echo -e "${YELLOW}创建conda环境: ${ENV_NAME}...${NC}"
    # 增加超时时间
    retry_command_with_logging "conda create -n $ENV_NAME python=3.12 -y" 300 >> "$LOG_FILE"

    local status=$?
    if [ $status -eq 0 ]; then
        echo -e "${GREEN}✓ conda环境 $ENV_NAME 创建成功${NC}" >> "$LOG_FILE"
        # 打印环境路径
        local env_path=$(conda info --envs | grep "^${ENV_NAME}\s" | awk '{print $NF}')
        if [ -n "$env_path" ]; then
             echo -e "${GREEN}环境路径: ${env_path}${NC}" >> "$LOG_FILE"
        fi
        return 0
    else
        echo -e "${RED}× conda环境 $ENV_NAME 创建失败${NC}" >> "$LOG_FILE"
        # 尝试列出现有环境以帮助诊断
        echo -e "${YELLOW}当前存在的conda环境:${NC}" >> "$LOG_FILE"
        conda info --envs >> "$LOG_FILE"
        return 1
    fi
}


check_and_set_pip_mirror() {
    echo -e "${BLUE}[准备工作] 检查pip源配置${NC}"
    
    local pip_config_file="$HOME/.pip/pip.conf"
    
    # 查看当前pip配置
    local current_index_url=""
    if [ -f "$pip_config_file" ]; then
        current_index_url=$(grep "index-url" "$pip_config_file" 2>/dev/null | cut -d "=" -f 2 | tr -d " ")
        
        if [ -n "$current_index_url" ]; then
            echo -e "${YELLOW}当前pip源: ${current_index_url}${NC}" >> "$LOG_FILE"
            
            if echo "$current_index_url" | grep -q -E "mirrors.ustc.edu.cn|tuna.tsinghua.edu.cn|mirrors.aliyun.com"; then
                echo -e "${GREEN}✓ 已配置国内pip源${NC}" >> "$LOG_FILE"
                return 0
            fi
        fi
    fi
    
    # 使用用户选择的国内代理配置
    if [ $USE_GHPROXY -eq 1 ]; then
        echo -e "${YELLOW}根据您的选择，将设置pip源为USTC源...${NC}" >> "$LOG_FILE"
        
        mkdir -p $(dirname "$pip_config_file")
        echo "[global]
index-url = https://mirrors.ustc.edu.cn/pypi/web/simple
format = columns" > "$pip_config_file"
        
        echo -e "${GREEN}✓ pip源已设置为USTC源${NC}" >> "$LOG_FILE"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] pip源已设置为USTC源" >> "$LOG_FILE"
    else
        echo -e "${GREEN}✓ 保持当前pip源设置${NC}" >> "$LOG_FILE"
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
        echo -e "${GREEN}✓ 检测到NVIDIA驱动版本: ${driver_version}${NC}" >> "$LOG_FILE"
        

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
            echo -e "${GREEN}✓ 驱动版本${driver_version}对应的CUDA版本: ${estimated_cuda_version}${NC}" >> "$LOG_FILE"
        else
            echo -e "${YELLOW}警告: 无法根据驱动版本${driver_version}估计CUDA版本${NC}" >> "$LOG_FILE"
        fi
        

        if [ $DEBUG_MODE -eq 1 ]; then
            echo -e "${CYAN}[DEBUG] GPU详细信息:${NC}" >> "$LOG_FILE"
            nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader | sed 's/^/  /' >> "$LOG_FILE"
        fi
    else
        echo -e "${YELLOW}警告: 未检测到NVIDIA GPU或无法运行nvidia-smi${NC}" >> "$LOG_FILE"
    fi
    

    local found_preferred_cuda=0
    local preferred_nvcc_path=""
    

    if [ -n "$estimated_cuda_version" ]; then
        local specific_cuda_path="/usr/local/cuda-${estimated_cuda_version}/bin/nvcc"
        local default_cuda_path="/usr/local/cuda/bin/nvcc"
        

        if [ -f "$specific_cuda_path" ]; then
            preferred_nvcc_path="$specific_cuda_path"
            found_preferred_cuda=1
            echo -e "${GREEN}✓ 找到与驱动匹配的CUDA ${estimated_cuda_version}: ${preferred_nvcc_path}${NC}" >> "$LOG_FILE"

        elif [ -f "$default_cuda_path" ]; then
            local default_version=$("$default_cuda_path" -V 2>&1 | grep "release" | awk '{print $6}' | sed 's/,//' | sed 's/V//')
            if [ "$default_version" = "$estimated_cuda_version" ]; then
                preferred_nvcc_path="$default_cuda_path"
                found_preferred_cuda=1
                echo -e "${GREEN}✓ 默认CUDA版本与驱动匹配: ${preferred_nvcc_path} (${default_version})${NC}" >> "$LOG_FILE"
            fi
        fi
    fi
    

    if [ $found_preferred_cuda -eq 1 ] && [ -n "$preferred_nvcc_path" ]; then
        local version_output=$("$preferred_nvcc_path" -V 2>/dev/null)
        if [ -n "$version_output" ]; then
            nvcc_cuda_version=$(echo "$version_output" | grep "release" | awk '{print $6}' | sed 's/,//' | sed 's/V//')
            echo -e "${GREEN}✓ 使用与驱动匹配的CUDA版本: ${nvcc_cuda_version}${NC}" >> "$LOG_FILE"
            

            local nvcc_dir=$(dirname "$preferred_nvcc_path")
            export PATH="${nvcc_dir}:$PATH"
            echo -e "${YELLOW}已将匹配的CUDA版本添加到PATH: ${nvcc_dir}${NC}" >> "$LOG_FILE"
            

            if [ $DEBUG_MODE -eq 1 ]; then
                echo -e "${CYAN}[DEBUG] 设置与驱动匹配的CUDA版本: ${nvcc_cuda_version}${NC}" >> "$LOG_FILE"
                echo -e "${CYAN}[DEBUG] CUDA路径: ${nvcc_dir}${NC}" >> "$LOG_FILE"
                echo -e "${CYAN}[DEBUG] 当前PATH: $PATH${NC}" >> "$LOG_FILE"
            fi
        fi

    elif command_exists nvcc; then
        local nvcc_path=$(which nvcc)
        nvcc_cuda_version=$(nvcc -V | grep "release" | awk '{print $6}' | sed 's/,//' | sed 's/V//')
        

        if [ -n "$estimated_cuda_version" ] && [ "$nvcc_cuda_version" != "$estimated_cuda_version" ]; then
            echo -e "${YELLOW}警告: PATH中的CUDA版本(${nvcc_cuda_version})与驱动兼容的版本(${estimated_cuda_version})不匹配${NC}" >> "$LOG_FILE"
            echo -e "${YELLOW}推荐使用与驱动匹配的CUDA ${estimated_cuda_version}以获得最佳兼容性${NC}" >> "$LOG_FILE"
        fi
        
        echo -e "${GREEN}✓ 使用PATH中的CUDA版本: ${nvcc_cuda_version} (${nvcc_path})${NC}" >> "$LOG_FILE"
        

        if [ $DEBUG_MODE -eq 1 ]; then
            echo -e "${CYAN}[DEBUG] CUDA详细信息:${NC}" >> "$LOG_FILE"
            nvcc -V | sed 's/^/  /' >> "$LOG_FILE"
            

            echo -e "${CYAN}[DEBUG] 检查系统中的其他CUDA版本:${NC}" >> "$LOG_FILE"
            

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
                        echo -e "${CYAN}[DEBUG]   发现其他CUDA版本: ${other_version} (${cuda_dir}/bin/nvcc)${NC}" >> "$LOG_FILE"
                        found_other=1
                        

                        if [ "$other_version" = "$estimated_cuda_version" ] && [ "$nvcc_cuda_version" != "$estimated_cuda_version" ]; then
                            echo -e "${CYAN}[DEBUG]   *** 推荐使用此版本，与NVIDIA驱动更兼容 ***${NC}" >> "$LOG_FILE"
                            echo -e "${CYAN}[DEBUG]   可以通过设置PATH来使用它: export PATH=${cuda_dir}/bin:\$PATH${NC}" >> "$LOG_FILE"
                        fi
                    fi
                fi
            done
            
            if [ $found_other -eq 0 ]; then
                echo -e "${CYAN}[DEBUG]   未发现其他CUDA版本${NC}" >> "$LOG_FILE"
            fi
        fi
    else
        echo -e "${YELLOW}未在当前PATH中检测到nvcc命令，尝试其他方法...${NC}" >> "$LOG_FILE"
        

        if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
            echo -e "${YELLOW}检测到sudo环境，尝试在用户${SUDO_USER}的环境中查找nvcc...${NC}" >> "$LOG_FILE"
            local user_nvcc_path=$(sudo -u "$SUDO_USER" which nvcc 2>/dev/null)
            
            if [ -n "$user_nvcc_path" ]; then
                echo -e "${GREEN}✓ 在用户${SUDO_USER}环境中找到nvcc: ${user_nvcc_path}${NC}" >> "$LOG_FILE"
                

                local version_output=$(sudo -u "$SUDO_USER" nvcc -V 2>/dev/null || "$user_nvcc_path" -V 2>/dev/null)
                if [ -n "$version_output" ]; then
                    nvcc_cuda_version=$(echo "$version_output" | grep "release" | awk '{print $6}' | sed 's/,//' | sed 's/V//')
                    echo -e "${GREEN}✓ 检测到CUDA版本: ${nvcc_cuda_version}${NC}" >> "$LOG_FILE"
                    

                    if [ -n "$estimated_cuda_version" ] && [ "$nvcc_cuda_version" != "$estimated_cuda_version" ]; then
                        echo -e "${YELLOW}警告: 用户环境中的CUDA版本(${nvcc_cuda_version})与驱动兼容的版本(${estimated_cuda_version})不匹配${NC}" >> "$LOG_FILE"
                    fi
                    

                    local nvcc_dir=$(dirname "$user_nvcc_path")
                    echo -e "${YELLOW}添加${nvcc_dir}到PATH...${NC}" >> "$LOG_FILE"
                    export PATH="$nvcc_dir:$PATH"
                    

                    local temp_bin_dir="/tmp/cuda_bin_$$"
                    echo -e "${YELLOW}创建临时CUDA工具目录: ${temp_bin_dir}${NC}" >> "$LOG_FILE"
                    mkdir -p "$temp_bin_dir"
                    ln -sf "$user_nvcc_path" "$temp_bin_dir/nvcc"
                    export PATH="$temp_bin_dir:$PATH"
                    
                    if [ $DEBUG_MODE -eq 1 ]; then
                        echo -e "${CYAN}[DEBUG] 临时CUDA目录已创建: ${temp_bin_dir}${NC}" >> "$LOG_FILE"
                        echo -e "${CYAN}[DEBUG] 已将nvcc软链接到: $temp_bin_dir/nvcc${NC}" >> "$LOG_FILE"
                        echo -e "${CYAN}[DEBUG] 当前PATH: $PATH${NC}" >> "$LOG_FILE"
                    fi
                fi
            fi
        fi
        

        if [ -z "$nvcc_cuda_version" ]; then
            echo -e "${RED}[错误] 未能检测到有效的CUDA环境。${NC}"
            echo -e "${RED}[错误] 请确保已正确安装NVIDIA CUDA工具包，并将其添加到PATH中。${NC}" >> "$LOG_FILE"
            echo -e "${YELLOW}提示: 确认是否已安装NVIDIA驱动和CUDA工具包${NC}" >> "$LOG_FILE"
            echo -e "${YELLOW}提示: 请运行以下命令检查CUDA安装:${NC}" >> "$LOG_FILE"
            echo -e "${YELLOW}  which nvcc${NC}" >> "$LOG_FILE"
            echo -e "${YELLOW}  nvcc -V${NC}" >> "$LOG_FILE"
            
            if [ -n "$estimated_cuda_version" ]; then
                echo -e "${YELLOW}提示: 根据NVIDIA驱动版本${driver_version}，建议安装CUDA ${estimated_cuda_version}${NC}" >> "$LOG_FILE"
            fi
            
            echo -e "${YELLOW}提示: 如果已安装但未找到，请将CUDA路径添加到环境变量:${NC}" >> "$LOG_FILE"
            echo -e "${YELLOW}  export PATH=/usr/local/cuda/bin:\$PATH${NC}" >> "$LOG_FILE"
            
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] 安装终止: 未检测到CUDA环境" >> "$LOG_FILE"
            

            exit 1
        fi
    fi
    

    cuda_version="$nvcc_cuda_version"
    

    local formatted_cuda_version=""
    if [ -n "$cuda_version" ]; then

        formatted_cuda_version="cu$(echo $cuda_version | sed 's/\.//')"
    else

        echo -e "${RED}[错误] 无法确定CUDA版本${NC}" >> "$LOG_FILE"
        exit 1
    fi
    

    if command_exists nvcc; then
        echo -e "${GREEN}✓ nvcc命令可用${NC}"
        if [ $DEBUG_MODE -eq 1 ]; then
            echo -e "${CYAN}[DEBUG] nvcc路径: $(which nvcc)${NC}" >> "$LOG_FILE"
            echo -e "${CYAN}[DEBUG] nvcc版本: $(nvcc -V | head -n1)${NC}" >> "$LOG_FILE"
        fi
    else

        echo -e "${RED}[错误] nvcc命令检测失败，环境可能已经改变${NC}" >> "$LOG_FILE"
        exit 1
    fi
    

    CUDA_VERSION="$cuda_version"
    FORMATTED_CUDA_VERSION="$formatted_cuda_version"
    
    echo -e "${BLUE}格式化的CUDA版本：${FORMATTED_CUDA_VERSION}${NC}" >> "$LOG_FILE"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] 检测到CUDA版本: ${CUDA_VERSION}, 格式化为${FORMATTED_CUDA_VERSION}" >> "$LOG_FILE"
    
    return 0
}

# 安装并验证PyTorch
install_pytorch() {
    echo -e "${BLUE}[步骤 6] 安装GPU版本PyTorch${NC}" >> "$LOG_FILE"

    
    local torch_version=""
    local install_success=false
    
    echo -e "${YELLOW}开始安装PyTorch GPU版本 (CUDA ${CUDA_VERSION})...${NC}" >> "$LOG_FILE"
    

    local cuda_major=$(echo "$CUDA_VERSION" | cut -d. -f1)
    local cuda_formatted="cu${cuda_major}$(echo "$CUDA_VERSION" | cut -d. -f2)"
    

    local pip_torch_cmd=""
    local torch_mirror=""
    

    local current_pip_index=$(pip config list | grep -o "index-url=.*" | cut -d= -f2 | tr -d "'")
    
    if [[ "$current_pip_index" == *"mirrors.ustc.edu.cn"* ]]; then
        echo -e "${YELLOW}检测到已配置中科大镜像源，将继续使用${NC}" >> "$LOG_FILE"
        torch_mirror="https://mirrors.ustc.edu.cn/pytorch/whl"
    elif [[ "$current_pip_index" == *"mirrors.tuna.tsinghua.edu.cn"* ]]; then
        echo -e "${YELLOW}检测到已配置清华镜像源，将继续使用${NC}" >> "$LOG_FILE"
        torch_mirror="https://mirrors.tuna.tsinghua.edu.cn/pytorch/whl"
    elif [ "${USE_GHPROXY:-0}" = "1" ]; then
        # 国内环境，使用镜像站
        torch_mirror="https://mirrors.ustc.edu.cn/pytorch/whl"
        echo -e "${YELLOW}根据用户设置使用中科大镜像源${NC}" >> "$LOG_FILE"
    else
        # 国外环境，使用官方源
        torch_mirror="https://download.pytorch.org/whl"
        echo -e "${YELLOW}根据用户设置使用官方源${NC}" >> "$LOG_FILE"
    fi
    

    pip_torch_cmd="pip install torch torchvision torchaudio -f ${torch_mirror}/cu${cuda_major}$(echo "$CUDA_VERSION" | cut -d. -f2)"
    

    echo -e "${CYAN}[命令] ${pip_torch_cmd}${NC}" >> "$LOG_FILE"
    if eval "$pip_torch_cmd"; then
        echo -e "${GREEN}✓ PyTorch通过pip安装成功${NC}"
        install_success=true
    else
        echo -e "${YELLOW}通过pip安装PyTorch失败，尝试通过conda安装...${NC}" >> "$LOG_FILE"
        

        if command_exists conda; then
            echo -e "${CYAN}[命令] conda install -y pytorch torchvision torchaudio pytorch-cuda=${CUDA_VERSION} -c pytorch -c nvidia${NC}" >> "$LOG_FILE"
            if conda install -y pytorch torchvision torchaudio pytorch-cuda=${CUDA_VERSION} -c pytorch -c nvidia; then
                echo -e "${GREEN}✓ PyTorch通过conda安装成功${NC}"
                install_success=true
            else
                echo -e "${RED}× PyTorch安装失败${NC}" >> "$LOG_FILE"
                return 1
            fi
        else
            echo -e "${RED}× conda不可用，PyTorch安装失败${NC}" >> "$LOG_FILE"
            return 1
        fi
    fi
    

    if [ "$install_success" = true ]; then
        echo -e "${YELLOW}验证PyTorch和CUDA...${NC}" >> "$LOG_FILE"
        

        torch_version=$(python -c "import torch; print(torch.__version__.split('+')[0])" 2>/dev/null)
        if [ -n "$torch_version" ]; then
            echo -e "${GREEN}✓ PyTorch版本: ${torch_version}${NC}" >> "$LOG_FILE"
            TORCH_VERSION="$torch_version"
            

            FORMATTED_TORCH_VERSION="torch$(echo $torch_version | cut -d '.' -f 1,2)"
            echo -e "${BLUE}格式化的PyTorch版本：${FORMATTED_TORCH_VERSION}${NC}" >> "$LOG_FILE"
            

            if python -c "import torch; exit(0 if torch.cuda.is_available() else 1)" &>/dev/null; then
                local cuda_torch_version=$(python -c "import torch; print(torch.version.cuda)" 2>/dev/null)
                echo -e "${GREEN}✓ CUDA可用，PyTorch报告的CUDA版本: ${cuda_torch_version}${NC}" >> "$LOG_FILE"
                

                if [ -n "$cuda_torch_version" ] && [ -z "$CUDA_VERSION" ]; then
                    CUDA_VERSION="$cuda_torch_version"
                    FORMATTED_CUDA_VERSION="cu$(echo $cuda_torch_version | sed 's/\.//')"
                    echo -e "${YELLOW}更新CUDA版本为PyTorch报告的版本: ${CUDA_VERSION}${NC}" >> "$LOG_FILE"
                fi
                
                echo -e "${GREEN}✓ GPU加速已启用${NC}" >> "$LOG_FILE"
                return 0
            else
                echo -e "${RED}× CUDA不可用，PyTorch将使用CPU模式${NC}" >> "$LOG_FILE" 
                echo -e "${YELLOW}您可能需要检查NVIDIA驱动和CUDA安装${NC}" >> "$LOG_FILE"
                return 1
            fi
        else
            echo -e "${RED}× 无法获取PyTorch版本信息${NC}" >> "$LOG_FILE"
            return 1
        fi
    fi
    
    return 1
}

# 6. 初始化git子模块
init_git_submodules() {
    log "INFO" "初始化子模块..." >> "$LOG_FILE"
    
    # 更新.gitmodules中的URL以使用代理
    if [ $USE_GHPROXY -eq 1 ] && [ -n "$GHPROXY_URL" ]; then
        log "INFO" "使用代理配置子模块URL..." >> "$LOG_FILE"
        
        # 检查.gitmodules文件是否存在
        if [ -f ".gitmodules" ]; then
            # 备份原始.gitmodules文件
            cp .gitmodules .gitmodules.backup
            
            # 替换顶级.gitmodules中的URL
            sed -i "s#url = https://github.com/#url = ${GHPROXY_URL}/https://github.com/#g" .gitmodules
            
            log "INFO" "更新.gitmodules中的URL以使用代理..." >> "$LOG_FILE"
            git submodule sync
        fi
    fi
    
    # 初始化顶级子模块
    git submodule update --init
    
    # 递归处理所有子模块及其嵌套子模块的URL
    if [ $USE_GHPROXY -eq 1 ] && [ -n "$GHPROXY_URL" ]; then
        log "INFO" "递归更新所有子模块的URL以使用代理..." >> "$LOG_FILE"
        
        # 获取所有子模块路径
        submodule_paths=$(git config --file .gitmodules --get-regexp path | awk '{ print $2 }')
        
        for submodule_path in $submodule_paths; do
            log "INFO" "处理子模块: $submodule_path" >> "$LOG_FILE"
            
            # 进入子模块目录
            if [ -d "$submodule_path" ]; then
                (cd "$submodule_path" && {
                    # 检查子模块中是否有自己的.gitmodules文件
                    if [ -f ".gitmodules" ]; then
                        log "INFO" "更新子模块 $submodule_path 中的.gitmodules" >> "$LOG_FILE"
                        
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
                            log "INFO" "处理嵌套子模块: $nested_path" >> "$LOG_FILE"
                            # 进入嵌套子模块目录
                            if [ -d "$nested_path" ]; then
                                (cd "$nested_path" && {
                                    if [ -f ".gitmodules" ]; then
                                        log "INFO" "更新嵌套子模块 $nested_path 中的.gitmodules" >> "$LOG_FILE"
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
    log "INFO" "完成子模块初始化..." >> "$LOG_FILE"
    git submodule update --init --recursive
    
    log "SUCCESS" "子模块初始化完成" >> "$LOG_FILE"
    return 0
}

# 7. 安装libnuma库
install_libnuma() {
    echo -e "${BLUE}[步骤 7] 安装libnuma库${NC}" >> "$LOG_FILE"
    
    # 检查是否已安装
    if ldconfig -p | grep -q "libnuma.so"; then
        echo -e "${GREEN}✓ libnuma已安装${NC}" >> "$LOG_FILE"
        return 0
    fi
    
    echo -e "${YELLOW}libnuma未安装，尝试安装...${NC}" >> "$LOG_FILE"
    
    # 尝试使用apt安装
    if command_exists apt-get; then
        echo -e "${YELLOW}使用apt安装libnuma-dev...${NC}" >> "$LOG_FILE"
        apt-get update && apt-get install -y libnuma-dev
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ libnuma-dev安装成功${NC}" >> "$LOG_FILE"
            return 0
        else
            echo -e "${RED}× apt安装libnuma-dev失败${NC}" >> "$LOG_FILE"
        fi
    fi
    
    echo -e "${RED}× 无法安装libnuma库，请手动安装后再继续${NC}" >> "$LOG_FILE"
    return 1
}

# 8. 设置USE_NUMA环境变量
set_use_numa() {
    echo -e "${BLUE}[步骤 8] 设置USE_NUMA环境变量${NC}" >> "$LOG_FILE"
    
    if [ $USE_NUMA -eq 1 ]; then
        export USE_NUMA=1
        echo -e "${GREEN}✓ 已启用USE_NUMA环境变量${NC}" >> "$LOG_FILE"
    else
        echo -e "${YELLOW}未启用USE_NUMA环境变量${NC}" >> "$LOG_FILE"
    fi
    
    return 0
}

# 9. 下载预编译的flashinfer
download_flashinfer() {
    echo -e "${BLUE}[步骤 10] 安装FlashInfer${NC}" >> "$LOG_FILE"
    log "INFO" "开始安装FlashInfer..." >> "$LOG_FILE"
    
    # 确保CUDA和PyTorch版本信息可用
    if [ -z "$FORMATTED_CUDA_VERSION" ] || [ -z "$FORMATTED_TORCH_VERSION" ]; then
        log "WARN" "CUDA或PyTorch版本信息缺失，尝试重新检测..." >> "$LOG_FILE"
        
        local torch_version=$(python -c "import torch; print(torch.__version__.split('+')[0])" 2>/dev/null)
        if [ -n "$torch_version" ]; then
            TORCH_VERSION="$torch_version"
            FORMATTED_TORCH_VERSION="torch$(echo $torch_version | cut -d '.' -f 1,2)"
            
            local cuda_torch_version=$(python -c "import torch; print(torch.version.cuda)" 2>/dev/null)
            if [ -n "$cuda_torch_version" ]; then
                CUDA_VERSION="$cuda_torch_version"
                FORMATTED_CUDA_VERSION="cu$(echo $cuda_torch_version | sed 's/\.//')"
                log "SUCCESS" "从PyTorch检测到CUDA版本: ${CUDA_VERSION} (${FORMATTED_CUDA_VERSION})" >> "$LOG_FILE"
            fi
        else
            log "ERROR" "无法检测到PyTorch版本，请确保PyTorch已正确安装" >> "$LOG_FILE"
            return 1
        fi
    fi
    
    local actual_cuda_version="$CUDA_VERSION"
    local actual_formatted_cuda="$FORMATTED_CUDA_VERSION"
    
    local cuda_major=$(echo "$CUDA_VERSION" | cut -d. -f1)
    local cuda_minor=$(echo "$CUDA_VERSION" | cut -d. -f2)
    
    FORMATTED_CUDA_VERSION="cu${cuda_major}${cuda_minor}"
    log "INFO" "使用CUDA版本格式: ${FORMATTED_CUDA_VERSION}" >> "$LOG_FILE"
    
    local temp_dir="/tmp/flashinfer_download_$$"
    mkdir -p "$temp_dir"
    
    log "INFO" "方式一：直接从GitHub Releases下载最新版本..." >> "$LOG_FILE"
    
    local latest_version="0.2.5"
    local base_url="https://github.com/flashinfer-ai/flashinfer/releases/download/v${latest_version}"
    local wheel_file_name="flashinfer_python-${latest_version}+${FORMATTED_CUDA_VERSION}${FORMATTED_TORCH_VERSION}-cp38-abi3-linux_x86_64.whl"
    local download_url="${base_url}/${wheel_file_name}"
    
    if [ $USE_GHPROXY -eq 1 ] && [ -n "$GHPROXY_URL" ]; then
        log "INFO" "使用代理 ${GHPROXY_URL} 下载..." >> "$LOG_FILE"
        download_url="${GHPROXY_URL}/${download_url}"
    fi
    
    log "INFO" "尝试下载: ${download_url}" >> "$LOG_FILE"
    local wheel_file="${temp_dir}/${wheel_file_name}"
    
    if wget -q --show-progress -O "$wheel_file" "$download_url" || curl -s -L -o "$wheel_file" "$download_url"; then
        log "SUCCESS" "下载成功，开始安装本地wheel文件" >> "$LOG_FILE"
        
        if pip install "$wheel_file"; then
            log "SUCCESS" "flashinfer安装成功" >> "$LOG_FILE"
            
            if python -c "import flashinfer" &>/dev/null; then
                local version=$(python -c "import flashinfer; print(flashinfer.__version__)" 2>/dev/null || echo "未知")
                log "SUCCESS" "flashinfer导入测试成功，版本: $version" >> "$LOG_FILE"
                rm -rf "$temp_dir"
                FORMATTED_CUDA_VERSION="$actual_formatted_cuda"
                return 0
            else
                log "WARN" "flashinfer安装成功但导入失败" >> "$LOG_FILE"
            fi
        else
            log "WARN" "本地wheel文件安装失败" >> "$LOG_FILE"
        fi
    else
        log "WARN" "直接下载失败，尝试备用方法" >> "$LOG_FILE"
    fi
    
    log "INFO" "方式二：尝试从flashinfer.ai网站下载..." >> "$LOG_FILE"
    
    local flashinfer_url="https://flashinfer.ai/whl/${FORMATTED_CUDA_VERSION}/${FORMATTED_TORCH_VERSION}/flashinfer-python"
    log "INFO" "尝试从 ${flashinfer_url} 安装flashinfer..." >> "$LOG_FILE"
    
    if pip install flashinfer-python -f "$flashinfer_url"; then
        log "SUCCESS" "通过pip -f选项安装flashinfer成功" >> "$LOG_FILE"
        
        if python -c "import flashinfer" &>/dev/null; then
            local version=$(python -c "import flashinfer; print(flashinfer.__version__)" 2>/dev/null || echo "未知")
            log "SUCCESS" "flashinfer导入测试成功，版本: $version" >> "$LOG_FILE"
            rm -rf "$temp_dir"
            FORMATTED_CUDA_VERSION="$actual_formatted_cuda"
            return 0
        fi
    else
        log "WARN" "从flashinfer.ai安装失败" >> "$LOG_FILE"
    fi
    
    rm -rf "$temp_dir"
    
    log "INFO" "方式三：从源代码编译安装..." >> "$LOG_FILE"
    
    local temp_dir="/tmp/flashinfer_build_$$"
    mkdir -p "$temp_dir"
    cd "$temp_dir" || return 1
    
    log "INFO" "克隆flashinfer仓库..." >> "$LOG_FILE"
    local repo_url="https://github.com/flashinfer-ai/flashinfer.git"
    
    if [ $USE_GHPROXY -eq 1 ] && [ -n "$GHPROXY_URL" ]; then
        repo_url="${GHPROXY_URL}/${repo_url}"
        log "INFO" "使用代理URL: $repo_url" >> "$LOG_FILE"
    fi
    
    if git clone --recursive "$repo_url"; then
        cd flashinfer || return 1
        log "INFO" "开始编译安装flashinfer..." >> "$LOG_FILE"
        
        # 设置编译参数
        export MAX_JOBS="$MAX_JOBS"
        if [ $USE_NUMA -eq 1 ]; then
            export USE_NUMA=1
        fi
        
        if pip install -e . -v; then
            log "SUCCESS" "flashinfer从源码安装成功" >> "$LOG_FILE"
            
            if python -c "import flashinfer" &>/dev/null; then
                local version=$(python -c "import flashinfer; print(flashinfer.__version__)" 2>/dev/null || echo "未知")
                log "SUCCESS" "flashinfer导入测试成功，版本: $version" >> "$LOG_FILE"
                cd "$INSTALL_DIR" || return 1
                rm -rf "$temp_dir"
                FORMATTED_CUDA_VERSION="$actual_formatted_cuda"
                return 0
            else
                log "WARN" "flashinfer安装成功但导入失败" >> "$LOG_FILE"
            fi
        else
            log "ERROR" "flashinfer从源码安装失败" >> "$LOG_FILE"
        fi
    else
        log "ERROR" "克隆flashinfer仓库失败" >> "$LOG_FILE"
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
        echo -e "${RED}× 目录 $INSTALL_DIR 不存在${NC}" >> "$LOG_FILE"
        return 1
    fi
    
    if ! cd "$INSTALL_DIR"; then
        log "ERROR" "无法进入目录 $INSTALL_DIR" >> "$LOG_FILE"
        echo -e "${RED}× 无法进入 $INSTALL_DIR 目录${NC}" >> "$LOG_FILE"
        return 1
    fi
                
    if ! command_exists make; then
        echo -e "${RED}× make命令不存在，尝试安装...${NC}" >> "$LOG_FILE"
        DEBIAN_FRONTEND=noninteractive apt-get update -y && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential
        
        if ! command_exists make; then
            echo -e "${RED}× 无法安装make工具，跳过make dev_install步骤${NC}" >> "$LOG_FILE"
            echo -e "${YELLOW}尝试使用pip直接安装...${NC}" >> "$LOG_FILE"
            
            if pip install -e .; then
                echo -e "${GREEN}✓ 使用pip安装成功${NC}" >> "$LOG_FILE"
                return 0
            else
                echo -e "${RED}× 使用pip安装也失败${NC}" >> "$LOG_FILE"
                echo -e "${YELLOW}您可能需要手动执行安装:${NC}" >> "$LOG_FILE"
                echo -e "${YELLOW}1. 安装build-essential${NC}" >> "$LOG_FILE"
                echo -e "${YELLOW}2. 进入 $INSTALL_DIR 目录${NC}" >> "$LOG_FILE"
                echo -e "${YELLOW}3. 执行 make dev_install 或 pip install -e .${NC}" >> "$LOG_FILE"
                return 1
            fi
        fi
    fi
    

    echo -e "${YELLOW}开始执行make dev_install（这可能需要一些时间）...${NC}" >> "$LOG_FILE"
    echo -e "${CYAN}编译过程中可能会显示一些警告，这是正常现象${NC}" >> "$LOG_FILE"
    
    local make_output=""
    local make_error_file="$INSTALL_DIR/make_error.log"
    
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] 开始执行make dev_install..." > "$make_error_file"
    
    if make_output=$(make dev_install 2>&1); then
        echo -e "${GREEN}✓ make dev_install执行成功${NC}" >> "$LOG_FILE"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] make dev_install执行成功" >> "$make_error_file"
        return 0
    else
        local exit_code=$?
        echo -e "${RED}× make dev_install执行失败 (错误码: $exit_code)${NC}" >> "$LOG_FILE"
        echo -e "${YELLOW}编译错误已保存到 $make_error_file${NC}" >> "$LOG_FILE"
        

        echo "[$(date +"%Y-%m-%d %H:%M:%S")] make dev_install执行失败 (错误码: $exit_code)" >> "$make_error_file"
        echo "==================== 错误输出 ====================" >> "$make_error_file"
        echo "$make_output" >> "$make_error_file"
        echo "==================================================" >> "$make_error_file"
        

        echo -e "${YELLOW}错误摘要:${NC}" >> "$LOG_FILE"
        echo "$make_output" | tail -n 15 >> "$LOG_FILE"
        
        echo -e "${YELLOW}尝试使用pip直接安装...${NC}" >> "$LOG_FILE"
        if pip install -e .; then
            echo -e "${GREEN}✓ 使用pip安装成功${NC}" >> "$LOG_FILE"
            return 0
        else
            echo -e "${RED}× 使用pip安装也失败${NC}" >> "$LOG_FILE"
            echo -e "${YELLOW}您可能需要手动执行安装:${NC}" >> "$LOG_FILE"
            echo -e "${YELLOW}1. 安装build-essential${NC}" >> "$LOG_FILE"
            echo -e "${YELLOW}2. 进入 $INSTALL_DIR 目录${NC}" >> "$LOG_FILE"
            echo -e "${YELLOW}3. 执行 make dev_install 或 pip install -e .${NC}" >> "$LOG_FILE"
        fi
                
    fi
}

# 12. 更新libstdc++6
update_libstdcpp6() {
    echo -e "${BLUE}[步骤 13] 更新libstdc++6${NC}" >> "$LOG_FILE"
    

    if ! command_exists add-apt-repository; then
        echo -e "${YELLOW}add-apt-repository命令不存在，尝试安装...${NC}" >> "$LOG_FILE"
        DEBIAN_FRONTEND=noninteractive apt-get update -y && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common
    fi
    
    if command_exists add-apt-repository; then
        if add-apt-repository ppa:ubuntu-toolchain-r/test -y && \
           DEBIAN_FRONTEND=noninteractive apt-get update -y && \
           DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade libstdc++6; then
            echo -e "${GREEN}✓ libstdc++6更新成功${NC}" >> "$LOG_FILE"
            return 0
        else
            echo -e "${RED}× libstdc++6更新失败${NC}" >> "$LOG_FILE"
            echo -e "${YELLOW}将继续安装过程，但可能影响某些运行时功能${NC}" >> "$LOG_FILE"
            return 1
        fi
    else
        echo -e "${RED}× 无法安装add-apt-repository工具，跳过libstdc++6更新${NC}" >> "$LOG_FILE"
        echo -e "${YELLOW}将继续安装过程，但可能影响某些运行时功能${NC}" >> "$LOG_FILE"
        return 1
    fi
}

# 13. 安装libstdcxx-ng
install_libstdcxx_ng() {
    echo -e "${BLUE}[步骤 14] 安装libstdcxx-ng${NC}" >> "$LOG_FILE"
    if retry_command_with_logging "conda install -c conda-forge libstdcxx-ng -y" 300; then
        echo -e "${GREEN}✓ libstdcxx-ng安装成功${NC}" >> "$LOG_FILE"
        return 0
    else
        echo -e "${RED}× libstdcxx-ng安装失败${NC}" >> "$LOG_FILE"
        echo -e "${YELLOW}将继续安装过程，但可能影响某些运行时功能${NC}" >> "$LOG_FILE"
        return 1
    fi
}

# 14. 检测版本信息
check_versions() {
    echo -e "${BLUE}===== 安装组件版本检查 =====${NC}" >> "$LOG_FILE"
    

    cd "$INSTALL_DIR" || return 1
    
    echo -e "${YELLOW}● KTransformers 安装信息${NC}" >> "$LOG_FILE"
    echo -e "  ○ 安装路径: ${GREEN}${INSTALL_DIR}${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}● Conda基础路径: ${GREEN}${CONDA_BASE_DIR:-将在安装时确定}${NC}" # Show placeholder
    echo -e "${BLUE}● Conda环境名称: ${GREEN}${ENV_NAME}${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}● GPU设备: ${GREEN}${gpu_info}${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}● CUDA版本: ${GREEN}${cuda_info}${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}● USE_NUMA: ${GREEN}$([ $USE_NUMA -eq 1 ] && echo "启用" || echo "禁用")${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}● 编译线程: ${GREEN}${MAX_JOBS}${NC}" >> "$LOG_FILE"
    

    if python -c "import ktransformers" &>/dev/null; then
        local ktrans_version=$(python -c "import ktransformers; print(ktransformers.__version__)" 2>/dev/null)
        echo -e "  ○ KTransformers版本: ${GREEN}${ktrans_version:-已安装}${NC}" >> "$LOG_FILE"
    else
        echo -e "  ○ KTransformers版本: ${RED}未安装或无法导入${NC}" >> "$LOG_FILE"
    fi
    

    if python -c "import torch" &>/dev/null; then
        local torch_version=$(python -c "import torch; print(torch.__version__)" 2>/dev/null)
        local cuda_available=$(python -c "import torch; print('可用' if torch.cuda.is_available() else '不可用')" 2>/dev/null)
        echo -e "  ○ PyTorch版本: ${GREEN}${torch_version}${NC} (CUDA: ${GREEN}${cuda_available}${NC})" >> "$LOG_FILE"
        

        if python -c "import torch; exit(0 if torch.cuda.is_available() else 1)" &>/dev/null; then
            local gpu_name=$(python -c "import torch; print(torch.cuda.get_device_name(0))" 2>/dev/null)
            echo -e "  ○ GPU设备: ${GREEN}${gpu_name}${NC}" >> "$LOG_FILE"
            

            local cuda_version=$(python -c "import torch; print(torch.version.cuda)" 2>/dev/null)
            echo -e "  ○ CUDA版本: ${GREEN}${cuda_version}${NC}" >> "$LOG_FILE"
        fi
    else
        echo -e "  ○ PyTorch版本: ${RED}未安装或无法导入${NC}" >> "$LOG_FILE"
    fi
    
    echo -e "${YELLOW}● 加速组件${NC}" >> "$LOG_FILE"
    

    if python -c "import flashinfer" &>/dev/null; then
        local flashinfer_version=$(python -c "import flashinfer; print(flashinfer.__version__)" 2>/dev/null)
        echo -e "  ○ FlashInfer版本: ${GREEN}${flashinfer_version:-已安装}${NC}" >> "$LOG_FILE"
    else
        echo -e "  ○ FlashInfer版本: ${RED}未安装或无法导入${NC}" >> "$LOG_FILE"
    fi
    

    if python -c "import flash_attn" &>/dev/null; then
        local flash_attn_version=$(python -c "import flash_attn; print(flash_attn.__version__)" 2>/dev/null)
        echo -e "  ○ Flash Attention版本: ${GREEN}${flash_attn_version:-已安装}${NC}"
    else
        echo -e "  ○ Flash Attention版本: ${RED}未安装或无法导入${NC}" >> "$LOG_FILE"
    fi
    

    if [ $USE_NUMA -eq 1 ]; then
        echo -e "  ○ USE_NUMA环境变量: ${GREEN}已启用${NC}" >> "$LOG_FILE"
    else
        echo -e "  ○ USE_NUMA环境变量: ${YELLOW}未启用${NC}" >> "$LOG_FILE"
    fi
    

    echo -e "  ○ 编译最大线程数: ${GREEN}${MAX_JOBS}${NC}" >> "$LOG_FILE"
    

    echo -e "\n${GREEN}✓ KTransformers安装完成!${NC}" >> "$LOG_FILE"
    echo -e "${YELLOW}您可以通过以下命令进入环境:${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}  conda activate ${ENV_NAME}${NC}" >> "$LOG_FILE"
    echo -e "${YELLOW}然后运行示例:${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}  cd ${INSTALL_DIR}/examples${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}  python run_demo.py${NC}" >> "$LOG_FILE"
    echo -e "\n${GREEN}祝您使用愉快!${NC}\n" >> "$LOG_FILE"
}

# 5. 激活环境并进入仓库
activate_conda_env() {
    echo -e "${BLUE}[步骤 5] 激活conda环境${NC}" >> "$LOG_FILE"

    # 获取conda基础路径 (确保在之前的步骤中已设置)
    if [ -z "$CONDA_BASE_DIR" ]; then
        log "ERROR" "CONDA_BASE_DIR 未设置，无法激活环境" >> "$LOG_FILE"
        return 1
    fi

    # 使用初始脚本目录
    local original_script_dir="${SCRIPT_DIR:-$(pwd)}"
    local activate_script_path="$original_script_dir/activate_env.sh"

    # 创建激活脚本
    echo -e "${YELLOW}创建环境激活脚本: ${activate_script_path}${NC}" >> "$LOG_FILE"
    cat > "$activate_script_path" << EOF
#!/bin/bash
# KTransformers 环境激活脚本 (由安装程序生成)

# 加载conda
CONDA_BASE_DIR="${CONDA_BASE_DIR}" # 使用安装时确定的路径
if [ -f "\${CONDA_BASE_DIR}/etc/profile.d/conda.sh" ]; then
    . "\${CONDA_BASE_DIR}/etc/profile.d/conda.sh"
else
    export PATH="\${CONDA_BASE_DIR}/bin:\$PATH"
fi

# 设置环境目录
export CONDA_ENVS_PATH="${ENV_INSTALL_DIR}"

# 激活环境
conda activate $ENV_NAME

# 激活后信息
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                       KTransformers 环境已激活                      "
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
env_path=\$(conda info --envs | grep "^${ENV_NAME}[[:space:]]" | awk '{print \$NF}')
echo "➤ 环境名称: ${ENV_NAME}"
if [ -n "\$env_path" ]; then
    echo "➤ 环境路径: \$env_path"
else
    echo "➤ 环境路径: (未能获取，请检查环境是否正确创建)"
fi
echo "➤ Python路径: \$(which python || echo '未找到')"
echo "➤ Conda基础路径: ${CONDA_BASE_DIR}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "提示: 可以直接使用 'conda activate ${ENV_NAME}' 命令激活环境。"
EOF

    chmod +x "$activate_script_path"
    log "INFO" "激活脚本已创建: $activate_script_path" >> "$LOG_FILE"

    # 尝试在当前shell source conda.sh 并激活
    if [ -f "${CONDA_BASE_DIR}/etc/profile.d/conda.sh" ]; then
        log "INFO" "尝试在当前shell中激活环境 $ENV_NAME ..." >> "$LOG_FILE"
        # 使用点号(.)在当前shell执行
        . "${CONDA_BASE_DIR}/etc/profile.d/conda.sh"

        # 激活环境
        if conda activate "$ENV_NAME"; then
            log "SUCCESS" "✓ 成功在当前shell激活环境 $ENV_NAME" >> "$LOG_FILE"
             # 验证激活状态
             if [[ "$CONDA_DEFAULT_ENV" == "$ENV_NAME" ]] || [[ "$CONDA_PREFIX" == *"/envs/$ENV_NAME" ]]; then
                 log "SUCCESS" "✓ 环境激活状态已确认" >> "$LOG_FILE"
                 return 0
             else
                 log "WARN" "conda activate命令执行成功，但环境似乎未完全激活 (CONDA_DEFAULT_ENV='$CONDA_DEFAULT_ENV', CONDA_PREFIX='$CONDA_PREFIX')" >> "$LOG_FILE"
                 log "WARN" "这可能是shell环境问题，但依赖安装应该仍可进行。" >> "$LOG_FILE"
                 return 0
             fi
        else
            log "ERROR" "在当前shell中执行 'conda activate $ENV_NAME' 失败" >> "$LOG_FILE"
            log "INFO" "请尝试手动运行: source ${activate_script_path}" >> "$LOG_FILE"
            return 1 # 激活失败，后续步骤可能出错
        fi
    else
        log "WARN" "找不到 ${CONDA_BASE_DIR}/etc/profile.d/conda.sh，无法自动在当前shell激活环境" >> "$LOG_FILE"
        # 尝试直接使用conda命令路径
        export PATH="${CONDA_BASE_DIR}/bin:$PATH"
        if "$CONDA_BASE_DIR/bin/conda" activate "$ENV_NAME"; then
             log "WARN" "通过直接调用conda activate成功，但这可能不会完全设置环境。" >> "$LOG_FILE"
             return 0 # 认为成功以便继续
        else
             log "ERROR" "无法自动激活环境 $ENV_NAME" >> "$LOG_FILE"
             log "INFO" "请手动运行: source ${activate_script_path}" >> "$LOG_FILE"
             return 1
        fi
    fi
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
    

    echo "$estimated_size" >> "$LOG_FILE"
}

# 更新git子模块
update_git_submodules_with_progress() {
    log "INFO" "更新git子模块，克隆和更新仓库" >> "$LOG_FILE"
    

    if [ $USE_GHPROXY -eq 1 ]; then

        if [ -f ".gitmodules" ] && ! grep -q "$GHPROXY_URL" .gitmodules; then
            log "INFO" "修改.gitmodules使用ghfast.top代理" >> "$LOG_FILE"
            sed -i.bak "s|https://github.com|${GHPROXY_URL}/https://github.com|g" .gitmodules
            log "SUCCESS" "已为子模块添加ghfast.top代理前缀" >> "$LOG_FILE"
            

            git submodule sync
            log "INFO" "已同步子模块配置" >> "$LOG_FILE"
            

            log "INFO" "配置git全局设置，使用ghfast.top代理" >> "$LOG_FILE"
            git config --global url."${GHPROXY_URL}/https://github.com/".insteadOf "https://github.com/"
            log "SUCCESS" "git全局配置已更新" >> "$LOG_FILE"
        fi
    fi
    

    local total_submodules=$(git config --file .gitmodules --get-regexp "^submodule\..*\.path$" | wc -l)
    
    if [ "$total_submodules" -eq 0 ]; then
        log "WARN" "未检测到git子模块" >> "$LOG_FILE"
        return 0
    fi
    
    log "INFO" "检测到 $total_submodules 个git子模块" >> "$LOG_FILE"
    

    if [ $DEBUG_MODE -eq 1 ]; then
        log "DEBUG" "当前.gitmodules内容:" >> "$LOG_FILE"
        cat .gitmodules >> "$LOG_FILE"
    fi
    

    local tmpfile=$(mktemp)
    

    if [ $DEBUG_MODE -eq 1 ] && [ $GIT_DEBUG_MODE -eq 1 ]; then

        export GIT_TRACE=1
        export GIT_CURL_VERBOSE=1
        log "DEBUG" "Git调试模式已启用，将显示详细日志" >> "$LOG_FILE"
    elif [ $DEBUG_MODE -eq 1 ]; then
        log "DEBUG" "Git调试模式已禁用，避免过多日志输出" >> "$LOG_FILE"
    fi
    
    log "INFO" "开始更新子模块，这可能需要一些时间..." >> "$LOG_FILE"
    

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
        log "DEBUG" "Git调试模式已重置" >> "$LOG_FILE"
    elif [ $DEBUG_MODE -eq 1 ]; then
        log "DEBUG" "Git子模块更新完成" >> "$LOG_FILE"
    fi
    
    if [ $exit_code -eq 0 ]; then
        log "SUCCESS" "git子模块克隆和更新成功" >> "$LOG_FILE"

        rm -f "$tmpfile"
        

        if [ -f ".gitmodules.bak" ] && [ $USE_GHPROXY -eq 1 ]; then
            log "INFO" "恢复原始.gitmodules文件" >> "$LOG_FILE"
            mv .gitmodules.bak .gitmodules
            git submodule sync
            

            log "INFO" "恢复git全局配置" >> "$LOG_FILE"
            git config --global --unset url."${GHPROXY_URL}/https://github.com/".insteadOf
        fi
        
        return 0
    else
        log "ERROR" "git子模块更新失败" >> "$LOG_FILE"
        log "DEBUG" "错误详情: $(cat "$tmpfile")" >> "$LOG_FILE"
        

        log "WARN" "尝试使用非并行方式更新子模块..." >> "$LOG_FILE"
        if git submodule update --init --recursive --jobs=1 --progress; then
            log "SUCCESS" "使用非并行方式更新子模块成功" >> "$LOG_FILE"
            rm -f "$tmpfile"
            return 0
        fi
        
        rm -f "$tmpfile"
        return 1
    fi
}

# 安装Flash Attention
install_flash_attn() {
    
    echo -e "${BLUE}[步骤 9] 安装Flash Attention${NC}" >> "$LOG_FILE"

    if [ -z "$FORMATTED_CUDA_VERSION" ] || [ -z "$FORMATTED_TORCH_VERSION" ]; then
        log "WARN" "CUDA或PyTorch版本信息缺失，尝试重新检测..." >> "$LOG_FILE"

        local torch_version=$(python -c "import torch; print(torch.__version__.split('+')[0])" 2>/dev/null)
        if [ -n "$torch_version" ]; then
            TORCH_VERSION="$torch_version"
            FORMATTED_TORCH_VERSION="torch$(echo $torch_version | cut -d. -f1,2 | sed 's/\.//')"

            local cuda_torch_version=$(python -c "import torch; print(torch.version.cuda)" 2>/dev/null)
            if [ -n "$cuda_torch_version" ]; then
                CUDA_VERSION="$cuda_torch_version"
                FORMATTED_CUDA_VERSION="cu$(echo $cuda_torch_version | sed 's/\.//')"
                log "SUCCESS" "从PyTorch检测到CUDA版本: ${CUDA_VERSION} (${FORMATTED_CUDA_VERSION})" >> "$LOG_FILE"
            fi
        else
            log "ERROR" "无法检测到PyTorch版本，请确保PyTorch已正确安装" >> "$LOG_FILE"
            return 1
        fi
    fi

    local python_version=$(python -c "import sys; print(f'cp{sys.version_info.major}{sys.version_info.minor}')" 2>/dev/null)
    if [ -z "$python_version" ]; then
        log "ERROR" "无法检测到Python版本" >> "$LOG_FILE"
        return 1
    fi

    local actual_cuda_version="$CUDA_VERSION"
    local actual_formatted_cuda="$FORMATTED_CUDA_VERSION"
    local cuda_major=$(echo "$CUDA_VERSION" | cut -d. -f1)
    FORMATTED_CUDA_VERSION="cu${cuda_major}"

    log "INFO" "检测到环境信息:" >> "$LOG_FILE"
    log "INFO" "- CUDA版本: ${actual_cuda_version} (${actual_formatted_cuda})" >> "$LOG_FILE"
    log "INFO" "- 将使用CUDA大版本: ${FORMATTED_CUDA_VERSION} 进行安装" >> "$LOG_FILE"
    log "INFO" "- PyTorch版本: ${TORCH_VERSION} (${FORMATTED_TORCH_VERSION})" >> "$LOG_FILE"
    log "INFO" "- Python版本: ${python_version}" >> "$LOG_FILE"

    log "INFO" "尝试安装预编译的Flash Attention..." >> "$LOG_FILE"

    local flash_attn_version="2.7.4.post1"
    local base_url="https://github.com/Dao-AILab/flash-attention/releases/download/v${flash_attn_version}"
    local package_name="flash_attn-${flash_attn_version}+${FORMATTED_CUDA_VERSION}${FORMATTED_TORCH_VERSION}cxx11abiFALSE-${python_version}-${python_version}-linux_x86_64.whl"

    local flash_attn_url
    if [ $USE_GHPROXY -eq 1 ] && [ -n "$GHPROXY_URL" ]; then
        flash_attn_url="${GHPROXY_URL}/https://github.com/Dao-AILab/flash-attention/releases/download/v${flash_attn_version}/${package_name}"
        log "INFO" "使用代理下载Flash Attention: ${flash_attn_url}" >> "$LOG_FILE"
    else
        flash_attn_url="${base_url}/${package_name}"
        log "INFO" "直接从GitHub下载Flash Attention: ${flash_attn_url}" >> "$LOG_FILE"
    fi

    log "INFO" "尝试下载: ${flash_attn_url}" >> "$LOG_FILE"

    if pip install "${flash_attn_url}"; then
        log "SUCCESS" "Flash Attention预编译包安装成功"

        if python -c "import flash_attn; print('Flash Attention版本:', flash_attn.__version__)" 2>/dev/null; then
            log "SUCCESS" "Flash Attention导入测试成功" >> "$LOG_FILE"
            FORMATTED_CUDA_VERSION="$actual_formatted_cuda"
            return 0
        else
            log "WARN" "Flash Attention安装成功但导入失败，尝试从源码安装..." >> "$LOG_FILE"
        fi
    else
        log "WARN" "预编译包安装失败，尝试从源码安装..." >> "$LOG_FILE"
    fi

    log "INFO" "准备从源码安装Flash Attention..." >> "$LOG_FILE"

    log "INFO" "安装ninja构建工具..." >> "$LOG_FILE"
    pip uninstall -y ninja && pip install ninja

    log "INFO" "设置编译环境变量，使用${MAX_JOBS}个编译线程..." >> "$LOG_FILE"
    export MAX_JOBS="$MAX_JOBS"

    # 克隆并编译
    local temp_dir=$(mktemp -d)
    cd "$temp_dir" || {
        log "ERROR" "无法创建临时目录" >> "$LOG_FILE"
        return 1
    }

    if git clone https://github.com/Dao-AILab/flash-attention.git; then
        cd flash-attention || {
            log "ERROR" "无法进入flash-attention目录" >> "$LOG_FILE"
            return 1
        }

        log "INFO" "使用ninja编译并安装..." >> "$LOG_FILE"
        if python setup.py install --use_ninja; then
            log "SUCCESS" "Flash Attention从源码编译安装成功" >> "$LOG_FILE"
            return 0
        else
            log "ERROR" "Flash Attention从源码编译安装失败" >> "$LOG_FILE"
            return 1
        fi
    else
        log "ERROR" "克隆Flash Attention仓库失败" >> "$LOG_FILE"
        return 1
    fi
}

# 验证conda安装路径并修复环境
validate_conda_path() {
    local expected_path="$1"
    local detected_path=$(which conda 2>/dev/null)
    
    echo -e "${YELLOW}验证conda安装路径...${NC}" >> "$LOG_FILE"
    echo -e "${YELLOW}预期路径: $expected_path/bin/conda${NC}" >> "$LOG_FILE"
    
    if [ -z "$detected_path" ]; then
        echo -e "${RED}× 无法在PATH中找到conda${NC}" >> "$LOG_FILE"
        # 添加到当前PATH
        export PATH="$expected_path/bin:$PATH"
        echo -e "${YELLOW}已添加 $expected_path/bin 到当前PATH${NC}" >> "$LOG_FILE"
    elif [ "$detected_path" != "$expected_path/bin/conda" ]; then
        echo -e "${YELLOW}检测到的conda路径与预期不符: $detected_path${NC}" >> "$LOG_FILE"
        
        # 修复bashrc中的路径
        for bashrc in "/root/.bashrc" "/home/$non_root_user/.bashrc"; do
            if [ -f "$bashrc" ]; then
                echo -e "${YELLOW}修正 $bashrc 中的conda路径引用${NC}" >> "$LOG_FILE"
                sed -i -E "s|^export PATH=.*conda.*:|export PATH=$expected_path/bin:\$PATH:|g" "$bashrc"
                sed -i -E "s|^[.] \".*conda/etc/profile.d/conda.sh\"$|. \"$expected_path/etc/profile.d/conda.sh\"|g" "$bashrc"
            fi
        done
        
        # 重新添加到PATH
        export PATH="$expected_path/bin:$PATH"
        echo -e "${GREEN}✓ conda路径已修正${NC}" >> "$LOG_FILE"
    else
        echo -e "${GREEN}✓ conda路径正确: $detected_path${NC}" >> "$LOG_FILE"
    fi
}


# 检查Git镜像站点
check_best_github_site() {
    log "INFO" "检查GitHub连接配置..." >> "$LOG_FILE"
    
    # 根据用户选择设置代理
    if [ $USE_GHPROXY -eq 1 ]; then
        log "INFO" "使用国内代理服务加速GitHub访问" >> "$LOG_FILE"
        log "SUCCESS" "已配置代理服务器: $GHPROXY_URL" >> "$LOG_FILE"
        
        # 如果存在.gitmodules文件，则修改其中的URL
        if [ -f ".gitmodules" ]; then
            log "INFO" "为git子模块添加代理前缀" >> "$LOG_FILE"
            sed -i.bak "s|https://github.com|${GHPROXY_URL}/https://github.com|g" .gitmodules
            log "SUCCESS" "已为子模块添加代理前缀" >> "$LOG_FILE"
        fi
        
        # 配置git全局代理
        log "DEBUG" "配置git全局代理设置" >> "$LOG_FILE"
        git config --global url."${GHPROXY_URL}/https://github.com/".insteadOf "https://github.com/"
    else
        log "INFO" "将直接连接GitHub，不使用代理" >> "$LOG_FILE"
    fi
    
    return 0
}

# 安装Python依赖
install_python_deps() {
    echo -e "${BLUE}[步骤 11] 安装Python依赖${NC}" >> "$LOG_FILE"
    
    cd "$INSTALL_DIR" || {
        echo -e "${RED}× 无法进入 $INSTALL_DIR 目录${NC}" >> "$LOG_FILE"
        return 1
    }
    
    echo -e "${YELLOW}在 $INSTALL_DIR 中递归查找 requirements.txt 文件...${NC}" >> "$LOG_FILE"
    
    # 递归查找所有 requirements.txt 文件，排除 /third_party 目录
    local req_files=($(find . -name "requirements.txt" -type f -not -path "*/third_party/*"))
    
    if [ ${#req_files[@]} -gt 0 ]; then
        echo -e "${GREEN}✓ 找到 ${#req_files[@]} 个 requirements.txt 文件${NC}" >> "$LOG_FILE"
        

        IFS=$'\n' req_files=($(sort <<<"${req_files[*]}"))
        unset IFS
        

        if [ $DEBUG_MODE -eq 1 ]; then
            echo -e "${CYAN}[DEBUG] 找到的 requirements.txt 文件:${NC}" >> "$LOG_FILE"
            for req_file in "${req_files[@]}"; do
                echo -e "${CYAN}[DEBUG]   - $req_file${NC}" >> "$LOG_FILE"
            done
        fi
        
        #忽略 torch 相关依赖
        for req_file in "${req_files[@]}"; do
            echo -e "${YELLOW}安装依赖: $req_file (忽略torch)${NC}" >> "$LOG_FILE"

            local temp_req=$(mktemp)
            grep -v "torch\|pytorch" "$req_file" > "$temp_req"
            
            if pip install -r "$temp_req"; then
                echo -e "${GREEN}✓ $req_file 中的依赖安装成功 (排除torch)${NC}" >> "$LOG_FILE"
                rm -f "$temp_req"  # 删除临时文件
            else
                echo -e "${RED}× $req_file 中的依赖安装失败${NC}" >> "$LOG_FILE"
                rm -f "$temp_req"  # 删除临时文件
                return 1
            fi
        done
        
        echo -e "${GREEN}✓ 所有 Python 依赖安装成功${NC}" >> "$LOG_FILE"
        return 0
    else
        echo -e "${YELLOW}未找到 requirements.txt 文件，尝试安装基本依赖...${NC}" >> "$LOG_FILE"
        
        # 安装基本依赖（不包含torch）
        if pip install numpy requests tqdm transformers huggingface_hub; then
            echo -e "${GREEN}✓ 基本 Python 依赖安装成功${NC}" >> "$LOG_FILE"
            return 0
        else
            echo -e "${RED}× 基本 Python 依赖安装失败${NC}" >> "$LOG_FILE"
            return 1
        fi
    fi

    log "INFO" "更新libstdc++6" >> "$LOG_FILE"
    
    if ! command_exists add-apt-repository; then
        log "WARN" "add-apt-repository命令不存在，尝试安装..." >> "$LOG_FILE"
        DEBIAN_FRONTEND=noninteractive apt-get update -y && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common
    fi
    
    if command_exists add-apt-repository; then
        if add-apt-repository ppa:ubuntu-toolchain-r/test -y && \
           DEBIAN_FRONTEND=noninteractive apt-get update -y && \
           DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade libstdc++6; then
            log "SUCCESS" "libstdc++6更新成功" >> "$LOG_FILE"
        else
            log "ERROR" "libstdc++6更新失败" >> "$LOG_FILE"
            log "WARN" "将继续安装过程，但可能影响某些运行时功能" >> "$LOG_FILE"
        fi
    else
        log "ERROR" "无法安装add-apt-repository工具，跳过libstdc++6更新" >> "$LOG_FILE"
        log "WARN" "将继续安装过程，但可能影响某些运行时功能" >> "$LOG_FILE"
    fi
    
    log "INFO" "安装libstdcxx-ng" >> "$LOG_FILE"
    if retry_command_with_logging "conda install -c conda-forge libstdcxx-ng -y" 300; then
        log "SUCCESS" "libstdcxx-ng安装成功" >> "$LOG_FILE"
    else
        log "ERROR" "libstdcxx-ng安装失败" >> "$LOG_FILE"
        log "WARN" "将继续安装过程，但可能影响某些运行时功能" >> "$LOG_FILE"
    fi
    
    return 0
}

# 安装KTransformers
install_ktransformers() {
    echo -e "${BLUE}[步骤 12] 安装KTransformers${NC}" >> "$LOG_FILE"
    
    if [ ! -d "$INSTALL_DIR" ]; then
        log "ERROR" "目录 $INSTALL_DIR 不存在" >> "$LOG_FILE"
        return 1
    fi
    
    cd "$INSTALL_DIR" || {
        log "ERROR" "无法进入 $INSTALL_DIR 目录" >> "$LOG_FILE"
        return 1
    }
    
    # 首先尝试使用make
    if ! command_exists make; then
        log "ERROR" "make命令不存在，尝试安装..." >> "$LOG_FILE"
        DEBIAN_FRONTEND=noninteractive apt-get update -y && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential
        
        if ! command_exists make; then
            log "ERROR" "无法安装make工具，跳过make dev_install步骤" >> "$LOG_FILE"
            log "WARN" "尝试使用pip直接安装..." >> "$LOG_FILE"
            
            if pip install -e .; then
                log "SUCCESS" "使用pip安装成功" >> "$LOG_FILE"
                return 1
            else
                log "ERROR" "使用pip安装也失败" >> "$LOG_FILE"
                log "WARN" "您可能需要手动执行安装:" >> "$LOG_FILE"
                log "WARN" "1. 安装build-essential" >> "$LOG_FILE"
                log "WARN" "2. 进入 $INSTALL_DIR 目录" >> "$LOG_FILE"
                log "WARN" "3. 执行 make dev_install 或 pip install -e ." >> "$LOG_FILE"
                return 1
            fi
        fi
    fi
    
    log "INFO" "开始执行make dev_install（这可能需要一些时间）..." >> "$LOG_FILE"
    log "INFO" "编译过程中可能会显示一些警告，这是正常现象" >> "$LOG_FILE"
    
    local make_output=""
    local make_log_file="$INSTALL_DIR/make_build.log"
    
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] 开始执行make dev_install..." > "$make_log_file"
    
    if make_output=$(make dev_install 2>&1); then
        log "SUCCESS" "make dev_install执行成功" >> "$LOG_FILE"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] make dev_install执行成功" >> "$make_log_file"
        return 0
    else
        local exit_code=$?
        log "ERROR" "make dev_install执行失败 (错误码: $exit_code)" >> "$LOG_FILE"
        # 在失败时重命名为错误日志
        local make_error_file="$INSTALL_DIR/make_build_error.log"
        mv "$make_log_file" "$make_error_file"
        log "WARN" "编译错误已保存到 $make_error_file" >> "$LOG_FILE"
        
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] make dev_install执行失败 (错误码: $exit_code)" >> "$make_error_file"
        echo "==================== 错误输出 ====================" >> "$make_error_file"
        echo "$make_output" >> "$make_error_file"
        echo "==================================================" >> "$make_error_file"
        
        log "WARN" "错误摘要:" >> "$LOG_FILE"
        echo "$make_output" | tail -n 15 >> "$LOG_FILE"
        
        log "WARN" "尝试使用pip直接安装..." >> "$LOG_FILE"
        if pip install -e .; then
            log "SUCCESS" "使用pip安装成功" >> "$LOG_FILE"
            return 0
        else
            log "ERROR" "使用pip安装也失败" >> "$LOG_FILE"
            log "WARN" "将继续安装过程，但功能可能不完整" >> "$LOG_FILE"
            return 1
        fi
    fi
}

# 处理工作区所有权的函数
handle_workspace_ownership() {

    echo -e "${BLUE}[步骤 13] 处理工作区所有权${NC}" >> "$LOG_FILE"

    local install_dir_abs=$(readlink -f "$INSTALL_DIR")
    local current_dir_abs=$(readlink -f "$SCRIPT_DIR")

    # 确定目标用户和组
    local target_user=""
    local target_group=""

    if [ -n "$INSTALL_USER" ] && [ "$INSTALL_USER" != "root" ]; then
        target_user="$INSTALL_USER"
    elif [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        target_user="$SUDO_USER"
    else
        target_user=$(whoami)
    fi

    # 获取用户的主组
    target_group=$(id -gn "$target_user" 2>/dev/null || echo "$target_user")

    echo -e "${YELLOW}将使用目标用户和组: $target_user:$target_group${NC}" >> "$LOG_FILE"

    # 检查当前用户权限
    local use_sudo=0
    if [ "$(id -u)" -ne 0 ]; then
        use_sudo=1
    fi

    # 查找所有可能的workspace路径
    local workspace_paths=(
        "$install_dir_abs/workspace"
        "$current_dir_abs/workspace"
        "$(dirname "$install_dir_abs")/workspace"
    )

    # 处理所有找到的workspace目录
    local unique_workspace_paths=($(echo "${workspace_paths[@]}" | tr ' ' '\n' | sort -u | grep .))
    for ws_path in "${unique_workspace_paths[@]}"; do
        ws_path=$(readlink -f "$ws_path" 2>/dev/null || echo "$ws_path")
        if [ -d "$ws_path" ]; then
            echo -e "${YELLOW}处理 workspace 目录: $ws_path${NC}" >> "$LOG_FILE"
            local cmd_prefix=""
            local success=1

            if [ $use_sudo -eq 1 ]; then
                cmd_prefix="sudo "
                echo -e "${YELLOW}使用 sudo 更改所有权和权限: $ws_path${NC}" >> "$LOG_FILE"
            else
                echo -e "${YELLOW}更改所有权和权限: $ws_path${NC}" >> "$LOG_FILE"
            fi

            # 1. 更改 workspace 目录本身的所有权
            if ! ${cmd_prefix}chown "$target_user:$target_group" "$ws_path"; then
                echo -e "${RED}× 设置 workspace 目录 '$ws_path' 所有权失败 (chown)${NC}" >> "$LOG_FILE"
                success=0
            fi

            # 2. 更改 workspace 目录本身的权限
            if [ $success -eq 1 ] && ! ${cmd_prefix}chmod 755 "$ws_path"; then
                echo -e "${RED}× 设置 workspace 目录 '$ws_path' 权限失败 (chmod 755)${NC}" >> "$LOG_FILE"
                success=0
            fi

            # 3. 递归更改内部文件/目录的所有权
            if [ $success -eq 1 ] && ! ${cmd_prefix}chown -R "$target_user:$target_group" "$ws_path"; then
                 echo -e "${RED}× 递归设置 workspace 内容所有权失败 (chown -R)${NC}" >> "$LOG_FILE"
                 success=0
            fi

            # 4. 递归更改内部文件/目录的权限
             if [ $success -eq 1 ] && ! ${cmd_prefix}chmod -R 755 "$ws_path"; then
                 echo -e "${RED}× 递归设置 workspace 内容权限失败 (chmod -R 755)${NC}" >> "$LOG_FILE"
                 success=0
             fi

            if [ $success -eq 1 ]; then
                 echo -e "${GREEN}✓ 成功设置 workspace 目录及内容的所有权和权限${NC}" >> "$LOG_FILE"
            else
                 echo -e "${RED}× 处理 workspace 目录 '$ws_path' 时遇到错误${NC}" >> "$LOG_FILE"
            fi
        fi
    done

    # 处理原始目录中的 activate_env.sh
    local orig_dirs=("$install_dir_abs" "$current_dir_abs")
    local unique_orig_dirs=($(echo "${orig_dirs[@]}" | tr ' ' '\n' | sort -u | grep .))

    for dir in "${unique_orig_dirs[@]}"; do
        if [ -d "$dir" ] && [ "$dir" != "/" ]; then
            local activate_script="$dir/activate_env.sh"
            if [ -f "$activate_script" ]; then
                echo -e "${YELLOW}设置激活脚本所有权: $activate_script${NC}" >> "$LOG_FILE"
                local cmd_prefix=""
                if [ $use_sudo -eq 1 ]; then
                    cmd_prefix="sudo "
                fi

                if ${cmd_prefix}chown "$target_user:$target_group" "$activate_script" && \
                   ${cmd_prefix}chmod 755 "$activate_script"; then
                     echo -e "${GREEN}✓ 成功设置激活脚本所有权和权限${NC}" >> "$LOG_FILE"
                else
                     echo -e "${RED}× 设置激活脚本 '$activate_script' 所有权或权限失败${NC}" >> "$LOG_FILE"
                fi
            fi
        fi
    done

    # 处理日志文件 (移出循环)
    if [ -n "$LOG_FILE" ]; then
        local log_file_path="$LOG_FILE"

        if [[ "$log_file_path" != /* && -f "$(pwd)/$log_file_path" ]]; then
             log_file_path="$(pwd)/$log_file_path"
        fi
        log_file_path=$(readlink -f "$log_file_path" 2>/dev/null || echo "$LOG_FILE")

        if [ -f "$log_file_path" ]; then
            echo -e "${YELLOW}设置日志文件所有权: $log_file_path${NC}" >> "$LOG_FILE"
            local cmd_prefix=""
            if [ $use_sudo -eq 1 ]; then
                cmd_prefix="sudo "
            fi

            if ! ${cmd_prefix}chown "$target_user:$target_group" "$log_file_path"; then
                 echo -e "${RED}× 设置日志文件 '$log_file_path' 所有权失败${NC}" >> "$LOG_FILE"
            fi
        fi
    fi

    echo -e "${GREEN}✓ 目录所有权设置检查完成${NC}" >> "$LOG_FILE"
    sleep 1
}

# 完成消息
completion_message() {

    
    show_ktransformers_logo
    

    border="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "\n${BLUE}$border${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}                ► KTransformers 安装报告 ◄${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}$border${NC}\n" >> "$LOG_FILE"
    

    echo -e "${GREEN}[系统环境检查]${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}┌────────────────────────────────────────────────────┐${NC}" >> "$LOG_FILE"
    
    echo -e "${BLUE}│${NC} > 安装目录:     ${GREEN}${INSTALL_DIR}${NC}" >> "$LOG_FILE"
    
    if command_exists python; then
        echo -e "${BLUE}│${NC} > Ktransformers版本:   ${GREEN}${KTRANS_VERSION}${NC}" >> "$LOG_FILE"
    else
        echo -e "${BLUE}│${NC} > Ktransformers版本:   ${YELLOW}未找到${NC}" >> "$LOG_FILE"
    fi

    if command_exists python; then
        python_version=$(python --version 2>&1)
        echo -e "${BLUE}│${NC} > Python版本:   ${GREEN}$python_version${NC}" >> "$LOG_FILE"
    else
        echo -e "${BLUE}│${NC} > Python版本:   ${YELLOW}未找到${NC}" >> "$LOG_FILE"
    fi
    
    if command_exists conda; then
        conda_version=$(conda --version 2>&1)
        echo -e "${BLUE}│${NC} > Conda版本:    ${GREEN}${conda_version}${NC}" >> "$LOG_FILE"
    else
        echo -e "${BLUE}│${NC} > Conda版本:    ${YELLOW}未找到${NC}" >> "$LOG_FILE"
    fi
    
    if command_exists nvcc; then
        cuda_version=$(nvcc --version | grep "release" | awk '{print $6}' | sed 's/,//')
        echo -e "${BLUE}│${NC} > CUDA版本:     ${GREEN}${cuda_version}${NC}" >> "$LOG_FILE"
    else
        echo -e "${BLUE}│${NC} > CUDA版本:     ${YELLOW}未找到${NC}" >> "$LOG_FILE"
    fi
    
    if [ $USE_NUMA -eq 1 ]; then
        echo -e "${BLUE}│${NC} > NUMA支持:     ${GREEN}已启用${NC}" >> "$LOG_FILE"
    else
        echo -e "${BLUE}│${NC} > NUMA支持:     ${YELLOW}未启用${NC}" >> "$LOG_FILE"
    fi
    
    echo -e "${BLUE}│${NC} > 编译线程数:   ${GREEN}${MAX_JOBS}${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}└────────────────────────────────────────────────────┘${NC}" >> "$LOG_FILE"
    

    echo -e "\n${GREEN}[SUCCESS] KTransformers 安装成功!${NC}" >> "$LOG_FILE"
    
    echo -e "\n${YELLOW}[使用指南]${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}┌────────────────────────────────────────────────────┐${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}│${NC} 1. 激活环境:                                     ${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}│${NC}    ${GREEN}source ${SCRIPT_DIR}/activate_env.sh ${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}│${NC}                                                ${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}│${NC} 2. 运行示例:                                     ${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}│${NC}    ${GREEN}请访问Ktransformers官方文档:${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}│${NC}    ${GREEN}https://kvcache-ai.github.io/ktransformers/en/DeepseekR1_V3_tutorial.html${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}│${NC}                                                ${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}│${NC}    ${GREEN}或者使用本地脚本:${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}│${NC}    ${GREEN}${SCRIPT_DIR}/start.sh${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}└────────────────────────────────────────────────────┘${NC}" >> "$LOG_FILE"
    
    echo -e "\n${BLUE}$border${NC}" >> "$LOG_FILE"
    echo -e "${GREEN}               感谢使用 KTransformers!${NC}" >> "$LOG_FILE"
    echo -e "${BLUE}$border${NC}\n" >> "$LOG_FILE"
}


# 主函数
main() {
    # 用户配置安装选项
    configure_installation

    # 设置日志文件
    setup_log_file

    # 显示开始安装标题
    show_ktransformers_logo
    echo -e "${BLUE}===== KTransformers 安装开始 =====${NC}\n" >> "$LOG_FILE"


    # 在调试模式下收集系统信息
    if [ $DEBUG_MODE -eq 1 ]; then
        collect_system_info
    fi

    # 显示安装脚本版本信息
    echo -e "${PURPLE}KTransformers 安装脚本${NC}" >> "$LOG_FILE"
    echo -e "${PURPLE}当前时间: $(date)${NC}\n" >> "$LOG_FILE"

    # 检查并安装所有依赖和工具
    setup_dependencies || exit 1

    # 测试GitHub连通性
    test_github_connectivity

    # 检查并设置pip源
    check_and_set_pip_mirror

    # 检测CUDA版本
    detect_pytorch_cuda_version

    # 用于跟踪安装状态的变量
    local install_status=0

    # 检查是否以root用户运行
    check_root || exit 1

    # 克隆仓库
    if ! clone_repo; then
        echo -e "${RED}× 仓库克隆失败，请检查网络连接和目录权限${NC}" >> "$LOG_FILE"
        echo -e "${YELLOW}您可以尝试手动克隆仓库:${NC}" >> "$LOG_FILE"
        echo -e "  ${BLUE}git clone https://github.com/kvcache-ai/ktransformers.git $INSTALL_DIR${NC}" >> "$LOG_FILE"
        if [ $USE_GHPROXY -eq 1 ]; then
            echo -e "或者使用ghfast.top代理:" >> "$LOG_FILE"
            echo -e "  ${BLUE}git clone ${GHPROXY_URL}/https://github.com/kvcache-ai/ktransformers.git $INSTALL_DIR${NC}"
        fi
        exit 1
    fi

    # 安装conda和创建环境 - 关键步骤，失败直接退出
    install_conda || { echo -e "${RED}× Conda安装失败，无法继续安装${NC}"; exit 1; }

    # 创建conda环境
    create_conda_env || { echo -e "${RED}× Conda环境创建失败，无法继续安装${NC}"; exit 1; }

    # 激活conda环境
    activate_conda_env || { echo -e "${RED}× Conda环境激活失败，无法继续安装${NC}"; exit 1; }

    # 安装PyTorch
    install_pytorch || { echo -e "${RED}× PyTorch安装失败，可能导致功能受限${NC}"; install_status=1; }

    # 初始化git子模块
    init_git_submodules || install_status=1

    # 安装libnuma  
    install_libnuma || install_status=1

    # 设置使用numa
    set_use_numa || install_status=1

    # 安装 Flash Attention
    install_flash_attn || install_status=1

    # 安装 FlashInfer
    download_flashinfer || install_status=1

    # 安装Python依赖
    install_python_deps || install_status=1

    # 安装KTransformers
    install_ktransformers || install_status=1

    # 安装完成
    if [ $install_status -eq 0 ]; then
        echo -e "${GREEN}✓ 安装完成！${NC}"
        
        # 处理工作区所有权
        handle_workspace_ownership
        
        completion_message
    else
        echo -e "${YELLOW}[WARN] 安装过程中有部分步骤失败，请查看详细日志${NC}"
        echo -e "${YELLOW}[INFO] 你可以尝试修复问题后重新运行脚本${NC}"
    fi
}

# 运行主函数
main "$@"