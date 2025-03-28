
# KTransformers 一键部署及启动脚本

<div align="center">
  <img src="https://img.shields.io/badge/CUDA-支持-brightgreen" alt="CUDA支持">
  <img src="https://img.shields.io/badge/PyTorch-兼容-blue" alt="PyTorch兼容">
  <img src="https://img.shields.io/badge/平台-Linux-orange" alt="平台">
  <img src="https://img.shields.io/badge/语言-Bash-yellow" alt="语言">
</div>

## 💡QQ交流群 

- [点击加入群聊](https://qm.qq.com/q/zBzV5CkDSM)  
- QQ群号 1028429001

## 🤗 最佳实践

  目前已经测试成功一键部署的环境：

- EPYC 9334QS*2 + NVIDIA 4090
- EPYC 9375F + NVIDIA 4070tis
- EPYC 9965*2 + NVIDIA 4090
- EPYC 7532 + NVIDIA 3070

 一键部署并不是万能的，因为每个系统的环境都不一样，我们均在Cuda 12.4 下测试通过，其他版本可能存在兼容性问题，请根据实际情况进行测试。

## 📋 简介

KTransformers 是一个高性能的 Transformer 模型加速框架，专为混合推理优化设计。本项目提供了完整的自动化安装和启动流程，帮助您快速部署 KTransformers 环境并启动模型，包括所有必要的依赖项和配置。

## ✨ 功能特点

- **全自动安装**：一键完成从环境检测到依赖安装的全过程
- **智能检测**：自动检测 CUDA、GPU 驱动和系统环境
- **多站点支持**：智能选择最佳 GitHub 镜像站点，加速下载
- **环境兼容性**：支持 sudo 和非 sudo 环境，保留用户环境变量
- **一键启动**：简化的模型启动脚本，支持丰富的参数配置
- **详细日志**：提供完整的安装和运行日志，便于故障排除
- **调试模式**：提供详细的调试信息和系统环境报告
- **自动修复**：遇到常见问题时尝试自动修复

## 🖥️ 系统要求

- **操作系统**：Ubuntu 或其他基于 Debian 的 Linux 发行版
- **硬件**：
  - NVIDIA GPU (推荐 16GB+ 显存)
  - 384GB+ 系统内存
- **软件**：
  - NVIDIA 驱动 (与 CUDA 兼容的版本)
  - Git
  - Python 3.11+
  - **Cuda 12.4**

## 🚀 安装步骤

### 1. 获取安装脚本

#### 方式〇：直接git clone吧（推荐）
 
 ```bash
 git clone https://github.com/maaaxinfinity/ktrun.git (github)
 git clone https://gitcode.com/Limitee/ktrun.git (gitcode)
 cd ./ktrun
 sudo bash run.sh
 ```

#### 方式一：从GitHub下载

```bash
wget https://raw.githubusercontent.com/maaaxinfinity/ktrun/refs/heads/main/run.sh
chmod +x run.sh
```

#### 方式二：从国内镜像仓库下载

```bash
wget https://gitcode.com/Limitee/ktrun/raw/main/run.sh
chmod +x run.sh
```

### 2. 运行安装脚本

```bash
sudo ./run.sh
```

#### 脚本参数选项

```
选项:
  -d, --debug           启用调试模式，记录详细日志
  -f, --fast            快速模式，使用默认配置无需用户确认
  -g, --git-debug       启用git详细日志输出（需要与-d一起使用）
  -h, --help            显示帮助信息
```

> **注意**：脚本开始时会提供选项让您配置安装目录、Conda环境名称、是否启用NUMA环境变量、编译线程数等参数。

### 3. 安装过程

安装过程包括以下主要步骤：

1. 检测系统环境和必要工具
2. 安装缺失的依赖项
3. 测试 GitHub 连通性并选择最佳镜像
4. 克隆 KTransformers 代码库
5. 安装/配置 Miniconda 环境
6. 创建并激活 conda 环境
7. 初始化和更新 git 子模块
8. 安装 NUMA 支持
9. 安装 GPU 版本的 PyTorch
10. 安装 Flash Attention 和 FlashInfer 加速库
11. 编译和安装 KTransformers
12. 更新系统库
13. 验证安装

## 🚀 启动模型

### 1. 获取启动脚本

#### 方式〇：直接git clone吧

```bash
git clone https://github.com/maaaxinfinity/ktrun.git (github)
git clone https://gitcode.com/Limitee/ktrun.git (gitcode)

sudo bash run.sh
```

#### 方式一：从GitHub下载

```bash
wget https://raw.githubusercontent.com/maaaxinfinity/ktrun/refs/heads/main/run.sh
chmod +x start.sh
```

#### 方式二：从国内镜像仓库下载（推荐）

```bash
wget https://gitcode.com/Limitee/ktrun/raw/main/start.sh
chmod +x start.sh
```

### 2. 运行启动脚本

```bash
./start.sh
```

### 3. 启动脚本参数

```
选项:
  -h, --help                显示帮助信息
  -m, --model_path PATH     设置模型路径 (默认: deepseek-ai/DeepSeek-R1)
  -g, --gguf_path PATH      设置GGUF路径 (默认: ~/model)
  -c, --cpu_infer NUM       设置CPU推理数量 (默认: 380)
  -t, --max_new_tokens NUM  设置最大新token数 (默认: 16384)
  -l, --cache_lens NUM      设置缓存长度 (默认: 8192)
  -o, --optimize_config_path PATH  设置优化配置文件 (默认: DeepSeek-V3-Chat.yaml)
```

### 4. 示例用法

```bash
# 使用默认参数启动
./start.sh

# 指定模型路径和其他参数
./start.sh -m custom-model -g /path/to/model -c 16 -t 8192 -l 2048

# 使用特定的优化配置文件
./start.sh -o DeepSeek-V3-Chat.yaml
```

## 📝 使用方法

### 安装完成后激活环境

安装完成后，您需要激活创建的 conda 环境：

```bash
source /path/to/activate_env.sh
```

> 脚本会在安装结束时显示确切的激活命令路径。

### 验证安装

激活环境后，您可以验证安装：

```bash
python -c "import ktransformers; print(ktransformers.__version__)"
python -c "import torch; print('CUDA可用:', torch.cuda.is_available())"
```

## ❓ 常见问题

### Q: 如何选择安装目录？

**A**: 脚本会提示您输入安装目录，默认为当前目录下的 `ktransformers` 文件夹。

### Q: 如何选择 conda 环境名称？

**A**: 脚本会提示您输入环境名称，默认为 `ktrans_main`。

### Q: 如何使用国内镜像加速安装？

**A**: 在安装配置中选择"是否使用国内代理和镜像站点?"选项为"是"。

### Q: 安装过程中断了怎么办？

**A**: 您可以重新运行脚本，它会检测已完成的步骤并继续安装。

### Q: 如何查看安装日志？

**A**: 安装日志保存在当前目录，格式为 `ktransformers_install_日期时间.log`。

### Q: 如何更改模型的默认参数？

**A**: 可以通过start.sh脚本的命令行参数进行设置，如`-m`指定模型路径，`-c`指定CPU推理数量等。

## 🛠️ 故障排除

### CUDA 相关问题

如果遇到 CUDA 相关问题：

```bash
# 检查 NVIDIA 驱动
nvidia-smi

# 检查 CUDA 版本
nvcc --version

# 检查 PyTorch CUDA 支持
python -c "import torch; print(torch.cuda.is_available())"
```

### 依赖项问题

如果某些依赖项安装失败：

```bash
# 手动安装 flashinfer
pip install flashinfer-python -f https://flashinfer.ai/whl/cu124/torch2.6

# 手动安装 PyTorch
pip install torch torchvision torchaudio -f https://download.pytorch.org/whl/cu124
```

### 环境激活问题

如果环境激活失败：

```bash
# 重新初始化 conda
conda init bash
source ~/.bashrc

# 手动激活环境
conda activate ktrans_main
```

---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=maaaxinfinity/ktrun&type=Date)](https://www.star-history.com/#maaaxinfinity/ktrun&Date)

<div align="center">
  <p>© 2024-2025 Limitee. 保留所有权利。</p>
  <p>如有问题，请提交 <a href="https://github.com/kvcache-ai/ktransformers/issues">GitHub Issue</a></p>
  <p>国内镜像仓库: <a href="https://gitcode.com/Limitee/ktrun">https://gitcode.com/Limitee/ktrun</a></p>
</div>
