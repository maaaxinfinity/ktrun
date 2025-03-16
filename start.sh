#!/bin/bash

# 默认参数
MODEL_PATH="deepseek-ai/DeepSeek-R1"
GGUF_PATH="~/model"
CPU_INFER=32
MAX_NEW_TOKENS=16384
CACHE_LENS=1536

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
    echo ""
    echo "示例: start.sh -m custom-model -g /path/to/model -c 16 -t 8192 -l 2048"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
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
        *)
            echo "未知参数: $1"
            show_help
            ;;
    esac
done

# 激活conda环境
eval "$(conda shell.bash hook)"
conda activate ktrans_main

# 打印当前参数
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                       ktransformers 启动参数                       "
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "➤ 模型路径:       $MODEL_PATH"
echo "➤ GGUF路径:       $GGUF_PATH"
echo "➤ CPU推理:        $CPU_INFER"
echo "➤ 最大新token数:  $MAX_NEW_TOKENS"
echo "➤ 缓存长度:       $CACHE_LENS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "正在启动模型，请稍候..."
echo ""

# 运行命令
python -m ktransformers.local_chat --model_path "$MODEL_PATH" --gguf_path "$GGUF_PATH" --cpu_infer "$CPU_INFER" --max_new_tokens "$MAX_NEW_TOKENS" --cache_lens "$CACHE_LENS"
