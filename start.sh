#!/bin/bash

export HF_ENDPOINT=https://hf-mirror.com

# 默认参数
MODEL_PATH="deepseek-ai/DeepSeek-R1"
GGUF_PATH="~/model"
CPU_INFER=380
MAX_NEW_TOKENS=16384
CACHE_LENS=8192
OPTIMIZE_CONFIG_PATH="DeepSeek-V3-Chat.yaml"
RULES_DIR="./workspace/ktransformers/optimize/optimize_rules"

# 显示帮助信息
show_help() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                       ktransformers 启动工具                       "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "用法: start.sh [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help                显示帮助信息"
    echo "  -m, --model_path PATH     设置模型路径 (默认: $MODEL_PATH)"
    echo "  -g, --gguf_path PATH      设置GGUF路径 (默认: $GGUF_PATH)"
    echo "  -c, --cpu_infer NUM       设置CPU推理数量 (默认: $CPU_INFER)"
    echo "  -t, --max_new_tokens NUM  设置最大新token数 (默认: $MAX_NEW_TOKENS)"
    echo "  -l, --cache_lens NUM      设置缓存长度 (默认: $CACHE_LENS)"
    echo "  -o, --optimize_config_path PATH  设置优化配置文件 (默认: $OPTIMIZE_CONFIG_PATH)"
    echo ""
    echo "示例: start.sh -m custom-model -g /path/to/model -c 16 -t 8192 -l 2048 -o DeepSeek-V3-Chat.yaml"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
}

# 选择配置文件
select_config() {
    echo "请选择优化配置文件:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    

    configs=($(find "$RULES_DIR" -name "DeepSeek-V3-*.yaml" 2>/dev/null))
    
    if [ ${#configs[@]} -eq 0 ]; then
        echo "未找到可用的配置文件，使用默认配置: $OPTIMIZE_CONFIG_PATH"

        OPTIMIZE_CONFIG_PATH="$RULES_DIR/$OPTIMIZE_CONFIG_PATH"
        return
    fi
    

    options=()
    for config in "${configs[@]}"; do
        options+=("$(basename $config)")
    done
    

    select opt in "${options[@]}"; do
        if [ -n "$opt" ]; then
径
            for config in "${configs[@]}"; do
                if [[ "$config" == *"$opt" ]]; then
                    OPTIMIZE_CONFIG_PATH="$config"
                    break
                fi
            done
            break
        else
            echo "无效的选择，请重试"
        fi
    done
    
    echo "已选择配置文件: $OPTIMIZE_CONFIG_PATH"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -m|--model_path)
            MODEL_PATH="$2"
            shift 2
            ;;
        -g|--gguf_path)
            GGUF_PATH="$2"
            shift 2
            ;;
        -c|--cpu_infer)
            CPU_INFER="$2"
            shift 2
            ;;
        -t|--max_new_tokens)
            MAX_NEW_TOKENS="$2"
            shift 2
            ;;
        -l|--cache_lens)
            CACHE_LENS="$2"
            shift 2
            ;;
        -o|--optimize_config_path)

            if [[ "$2" == /* ]] || [[ "$2" == ./* ]]; then
                OPTIMIZE_CONFIG_PATH="$2"
            else
                OPTIMIZE_CONFIG_PATH="$RULES_DIR/$2"
            fi
            shift 2
            ;;
        *)
            echo "未知参数: $1"
            show_help
            ;;
    esac
done


if [ "$OPTIMIZE_CONFIG_PATH" = "DeepSeek-V3-Chat.yaml" ]; then
    OPTIMIZE_CONFIG_PATH="$RULES_DIR/$OPTIMIZE_CONFIG_PATH"

    if [ ! -f "$OPTIMIZE_CONFIG_PATH" ]; then
        select_config
    fi
fi

GGUF_PATH="${GGUF_PATH/#\~/$HOME}"


eval "$(conda shell.bash hook)"
conda activate ktrans_main


echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                       ktransformers 启动参数                       "
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "➤ 模型路径:       $MODEL_PATH"
echo "➤ GGUF路径:       $GGUF_PATH"
echo "➤ CPU推理:        $CPU_INFER"
echo "➤ 最大新token数:  $MAX_NEW_TOKENS"
echo "➤ 缓存长度:       $CACHE_LENS"
echo "➤ 优化配置文件:   $OPTIMIZE_CONFIG_PATH"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "正在启动模型，请稍候..."
echo ""


python -m ktransformers.local_chat --model_path "$MODEL_PATH" --gguf_path "$GGUF_PATH" --cpu_infer "$CPU_INFER" --max_new_tokens "$MAX_NEW_TOKENS" --cache_lens "$CACHE_LENS" --optimize_config_path "$OPTIMIZE_CONFIG_PATH"
