# KTransformers 一键部署脚本

<div align="center">
  <img src="https://img.shields.io/badge/CUDA-支持-brightgreen" alt="CUDA支持">
  <img src="https://img.shields.io/badge/PyTorch-兼容-blue" alt="PyTorch兼容">
  <img src="https://img.shields.io/badge/平台-Linux-orange" alt="平台">
  <img src="https://img.shields.io/badge/语言-Bash-yellow" alt="语言">
</div>

## 📋 简介

KTransformers 是一个高性能的 Transformer 模型加速框架，专为混合推理优化设计。本安装脚本提供了自动化的安装流程，帮助您快速部署 KTransformers 环境，包括所有必要的依赖项和配置。

## ✨ 功能特点

- **全自动安装**：一键完成从环境检测到依赖安装的全过程
- **智能检测**：自动检测 CUDA、GPU 驱动和系统环境
- **多站点支持**：智能选择最佳 GitHub 镜像站点，加速下载
- **环境兼容性**：支持 sudo 和非 sudo 环境，保留用户环境变量
- **详细日志**：提供完整的安装日志，便于故障排除
- **调试模式**：提供详细的调试信息和系统环境报告
- **自动修复**：遇到常见问题时尝试自动修复

## 🖥️ 系统要求

- **操作系统**：Ubuntu 或其他基于 Debian 的 Linux 发行版
- **硬件**：
  - NVIDIA GPU (推荐 16GB+ 显存)
  - 512GB+ 系统内存
- **软件**：
  - NVIDIA 驱动 (与 CUDA 兼容的版本)
  - Git
  - Python 3.11+

## 🚀 安装步骤

### 1. 下载安装脚本

```bash
wget https://raw.githubusercontent.com/kvcache-ai/ktransformers/main/run.sh
chmod +x run.sh
```

### 2. 运行安装脚本

```bash
sudo ./run.sh
```

> **注意**：脚本会在开始时提供 5 秒钟的时间让您选择是否启用调试模式。

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
10. 安装 flashinfer 加速库
11. 编译和安装 KTransformers
12. 更新系统库
13. 验证安装

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

## 🔍 调试模式

调试模式提供更详细的安装信息和日志：

- 在脚本启动后 5 秒内按下回车键可启用调试模式
- 调试模式会收集系统硬件和软件环境信息
- 记录详细的安装过程日志
- 捕获并记录所有命令执行情况

## ❓ 常见问题

### Q: 如何选择安装目录？
**A**: 脚本会提示您输入安装目录，默认为当前目录下的 `ktransformers` 文件夹。

### Q: 如何选择 conda 环境名称？
**A**: 脚本会提示您输入环境名称，默认为 `ktrans_main`。

### Q: 安装过程中断了怎么办？
**A**: 您可以重新运行脚本，它会检测已完成的步骤并继续安装。

### Q: 如何查看安装日志？
**A**: 安装日志保存在当前目录，格式为 `ktransformers_install_日期时间.log`。

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
pip install flashinfer-python -f https://flashinfer.ai/whl/cu118/torch2.0

# 手动安装 PyTorch
pip install torch torchvision torchaudio -f https://download.pytorch.org/whl/cu118
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

<div align="center">
  <p>© 2023 KVCache AI. 保留所有权利。</p>
  <p>如有问题，请提交 <a href="https://github.com/kvcache-ai/ktransformers/issues">GitHub Issue</a></p>
</div>
