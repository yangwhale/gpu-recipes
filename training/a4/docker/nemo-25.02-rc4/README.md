# NeMo 25.02-rc4 for A4 GPU

This is the Dockerfile for building a container image based on NVIDIA NeMo 25.02-rc4 for running large language model training workloads on Google A4 GPUs.

## Features

- Based on NVIDIA NeMo Framework 25.02-rc4 release candidate
- Optimized for A4 GPU architecture with CUDA 13 support
- Includes GCSfuse components for Google Cloud Storage integration
- Contains Google Cloud CLI tools for cloud resource management
- NVIDIA NCCL v2.25.1-1 with network support for distributed training
- Pre-configured SSH on port 222 for multi-node communication
- Support for compute capabilities 100 (A100) and 120 (H200/A200)
- Includes dllogger for training metrics logging

## Usage

This container is used as the base image for A4 training recipes in this repository. See the main A4 [README.md](../../README.md) for instructions on how to use the training recipes.

### Building the Image

Use the following command to build the Docker image:

```bash
cd $REPO_ROOT/training/a4/docker/nemo-25.02-rc4
gcloud builds submit --region=${REGION} \
    --config cloudbuild.yml \
    --substitutions _ARTIFACT_REGISTRY=$ARTIFACT_REGISTRY \
    --timeout "2h" \
    --machine-type=e2-highcpu-32 \
    --quiet \
    --async
```

Make sure to set the following environment variables first:
- `REGION`: Google Cloud region (e.g., us-central1)
- `ARTIFACT_REGISTRY`: Artifact Registry path (e.g., us-central1-docker.pkg.dev/your-project-id/your-repo)

---

# 用于 A4 GPU 的 NeMo 25.02-rc4

这是基于 NVIDIA NeMo 25.02-rc4 构建的容器镜像，用于在 Google A4 GPU 上运行大型语言模型训练工作负载。

## 特性

- 基于 NVIDIA NeMo 框架 25.02-rc4 候选版本
- 为 A4 GPU 架构优化，支持 CUDA 13
- 包含 GCSfuse 组件，用于 Google Cloud Storage 集成
- 包含 Google Cloud CLI 工具，用于云资源管理
- 包含 NVIDIA NCCL v2.25.1-1 及网络支持，用于分布式训练
- 预配置了 222 端口的 SSH，用于多节点通信
- 支持计算能力 100 (A100) 和 120 (H200/A200)
- 包含 dllogger，用于记录训练指标

## 使用方法

此容器作为本仓库中 A4 训练配方的基础镜像。有关如何使用训练配方的说明，请参阅主要的 A4 [README.md](../../README.md)。

### 构建镜像

使用以下命令构建Docker镜像：

```bash
cd $REPO_ROOT/training/a4/docker/nemo-25.02-rc4
gcloud builds submit --region=${REGION} \
    --config cloudbuild.yml \
    --substitutions _ARTIFACT_REGISTRY=$ARTIFACT_REGISTRY \
    --timeout "2h" \
    --machine-type=e2-highcpu-32 \
    --quiet \
    --async
```

请确保先设置以下环境变量：
- `REGION`：Google Cloud区域（例如：us-central1）
- `ARTIFACT_REGISTRY`：Artifact Registry路径（例如：us-central1-docker.pkg.dev/your-project-id/your-repo）