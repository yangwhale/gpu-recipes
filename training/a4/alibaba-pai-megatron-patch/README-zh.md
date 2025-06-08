# 在 A4 GKE 节点池上使用 Pai-Megatron-Patch 框架预训练 Qwen3-30B 模型

本指南详细介绍了如何在 [A4 GKE 节点池](https://cloud.google.com/kubernetes-engine) 上使用 [Alibaba Pai-Megatron-Patch 框架](https://github.com/alibaba/Pai-Megatron-Patch) 运行 Qwen3-30B 预训练工作负载。

## 编排和部署工具

本指南使用以下技术栈：

- **编排平台** - [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine)
- **预训练作业配置和部署** - 使用 Helm Chart 配置和部署 [Kubernetes JobSet](https://kubernetes.io/blog/2025/03/23/introducing-jobset) 资源，该资源管理 [Pai-Megatron-Patch 预训练工作负载](https://github.com/alibaba/Pai-Megatron-Patch) 的执行。

## 测试环境

本指南已在以下配置下进行优化和测试：

### GKE 集群要求
- [区域标准集群](https://cloud.google.com/kubernetes-engine/docs/concepts/configuration-overview)，版本：1.31.7-gke.1265000 或更高版本
- GPU 节点池：2 个 [a4-highgpu-8g](https://cloud.google.com/compute/docs/accelerator-optimized-machines#a4-high-vms) 节点，使用 DENSE 部署类型
- 启用 [GKE 工作负载身份联合](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity)
- 启用 [GKE Cloud Storage FUSE CSI 驱动程序](https://cloud.google.com/kubernetes-engine/docs/concepts/cloud-storage-fuse-csi-driver)
- 启用 [DCGM 指标](https://cloud.google.com/kubernetes-engine/docs/how-to/dcgm-metrics)
- 安装 [Kueue](https://kueue.sigs.k8s.io/docs/reference/kueue.v1beta1/) 和 [JobSet](https://jobset.sigs.k8s.io/docs/overview/) API
- 配置 Kueue 支持[拓扑感知调度](https://kueue.sigs.k8s.io/docs/concepts/topology_aware_scheduling/)

### 存储要求
- 区域性 Google Cloud Storage (GCS) 存储桶，用于存储运行日志
- NFS 存储，用于共享数据和模型文件

要准备所需环境，请参阅 [GKE 环境设置指南](../../../../docs/configuring-environment-gke-a4.md)。

## 训练数据集

本指南使用 Qwen3 官方训练数据集，包括：
- Qwen3 预训练数据集（mmap 格式）
- Alpaca 中文数据集（用于微调）

## Docker 容器镜像

本指南使用专门为 Pai-Megatron-Patch 构建的 Docker 镜像：
`us-central1-docker.pkg.dev/[PROJECT_ID]/[REPO]/pai_megatron_patch_a4:25.04`

### 镜像构建

该镜像通过 Google Cloud Build 构建，包含以下组件：
- **基础镜像**：`dsw-registry.cn-wulanchabu.cr.aliyuncs.com/pai/pai-megatron-patch:25.04`
- **Pai-Megatron-Patch 框架**：Alibaba 开源的分布式训练框架
- **NCCL gIB 插件**：优化 A4 GPU 网络通信性能
- **依赖库**：PyTorch、HuggingFace Transformers 等

### 镜像特性
- 专门针对 A4 GPU 优化
- 包含完整的 Pai-Megatron-Patch 运行环境
- 支持分布式训练和模型并行
- 预装所有必要的依赖和工具

### 自定义镜像构建

如果需要自定义镜像，可以使用 Google Cloud Build 进行构建：

1. **准备构建环境**

   确保您有适当的权限和配置：
   ```bash
   # 启用必要的 API
   gcloud services enable cloudbuild.googleapis.com
   gcloud services enable artifactregistry.googleapis.com
   
   # 配置 Artifact Registry
   gcloud artifacts repositories create your-repo-name \
       --repository-format=docker \
       --location=us-central1
   ```

2. **构建自定义镜像**

   ```bash
   # 使用 Cloud Build 构建镜像
   gcloud builds submit --config cloudbuild.yaml \
       --substitutions=_IMAGE_NAME=pai_megatron_patch_a4,_IMAGE_TAG=custom
   ```

3. **更新部署配置**

   在 Helm 命令中指定自定义镜像（如果需要）：
   ```bash
   --set "workload.image"=us-central1-docker.pkg.dev/[PROJECT_ID]/[REPO]/pai_megatron_patch_a4:25.04
   ```

### 镜像版本说明

本项目使用阿里云 PAI 提供的基础镜像：

- **基础镜像**：`dsw-registry.cn-wulanchabu.cr.aliyuncs.com/pai/pai-megatron-patch:25.04`
- **25.04**：基于 Pai-Megatron-Patch 25.04 的稳定版本，包含完整的分布式训练环境
- **latest**：最新开发版本（不推荐生产使用）
- **custom**：根据特定需求定制的版本

## 架构特性

本配方实现了以下关键特性：

### 模块化设计
训练流程分为 4 个独立的功能模块，每个模块都可以通过环境变量独立控制：

1. **代码库克隆** (`SKIP_CLONE_REPO`)
   - 自动克隆 Pai-Megatron-Patch 代码库
   - 仅在 rank 0 节点执行，避免重复操作

2. **数据下载** (`SKIP_DOWNLOAD_DATA`)
   - 下载 Qwen3-30B 模型文件
   - 下载训练数据集
   - 仅在 rank 0 节点执行，节省带宽

3. **检查点转换** (`SKIP_CHECKPOINT_CONVERSION`)
   - 将 HuggingFace 格式模型转换为 Megatron 格式
   - 支持并行执行

4. **模型训练** (`SKIP_TRAINING`)
   - 执行实际的分布式训练
   - 支持多节点并行训练

### 环境变量配置
所有关键配置都通过环境变量管理，提供最大的灵活性：

- `PAI_WORKSPACE_ROOT`: 工作目录根路径（默认：`/mnt`）
- `SSH_PUBLIC_KEY`: SSH 公钥，用于kubectl portforward 后的 ssh 访问，用于 vscode + remote-ssh + pod 模式。
- `SLEEP_INFINITY`: 控制容器是否保持运行状态
- `SKIP_*`: 控制各个功能模块的执行

### 分布式训练优化
- 自动节点发现和物理拓扑优化
- SSH 服务配置，支持节点间通信
- MPI hostfile 生成，优化通信效率
- 支持多节点同步和协调

## 运行指南

在客户端工作站上完成以下步骤：

### 配置环境变量

设置环境变量以匹配您的环境：

```bash
export PROJECT_ID=<PROJECT_ID>
export CLUSTER_REGION=<CLUSTER_REGION>
export CLUSTER_NAME=<CLUSTER_NAME>
export GCS_BUCKET=<GCS_BUCKET>
export KUEUE_NAME=<KUEUE_NAME>
```

替换以下值：

- `<PROJECT_ID>`：您的 Google Cloud 项目 ID
- `<CLUSTER_REGION>`：集群所在的区域
- `<CLUSTER_NAME>`：GKE 集群的名称
- `<GCS_BUCKET>`：Cloud Storage 存储桶的名称（不包含 `gs://` 前缀）
- `<KUEUE_NAME>`：Kueue 本地队列的名称。集群工具包创建的默认队列是 `a4`。请确保验证集群中本地队列的名称

设置默认项目：

```bash
gcloud config set project $PROJECT_ID
```

### 获取代码仓库

克隆 `gpu-recipes` 仓库并设置指向配方文件夹的引用：

```bash
git clone https://github.com/ai-hypercomputer/gpu-recipes.git
cd gpu-recipes
export REPO_ROOT=`git rev-parse --show-toplevel`
export RECIPE_ROOT=$REPO_ROOT/training/a4/alibaba-pai-megatron-patch
cd $RECIPE_ROOT
```

### 获取集群凭据

```bash
gcloud container clusters get-credentials $CLUSTER_NAME --region $CLUSTER_REGION
```

## 部署训练作业

### 配置和提交预训练作业

#### 完整的 Helm 部署命令

以下是部署训练作业的完整 Helm 命令：

```bash
helm install -f $RECIPE_ROOT/values.yaml \
    --set-file workload_launcher=$REPO_ROOT/training/a4/alibaba-pai-megatron-patch/gke-runtime/launchers/torchrun-stratup.sh \
    --set-file pai_training_script=$REPO_ROOT/training/a4/alibaba-pai-megatron-patch/examples/qwen3.sh \
    --set "workload.image"=dsw-registry.cn-wulanchabu.cr.aliyuncs.com/pai/pai-megatron-patch:25.04 \
    --set queue=${KUEUE_NAME} \
    --set "volumes.gcsMounts[0].bucketName"=${GCS_BUCKET} \
    $USER-pai-megatron \
    $RECIPE_ROOT/gke-runtime/jobset
```

### 监控作业

要检查作业中 Pod 的状态，请运行以下命令：

```bash
kubectl get pods | grep $USER-qwen3-30b-pai-megatron
```

要获取某个 Pod 的日志，请运行以下命令：

```bash
kubectl logs POD_NAME
```

有关训练作业进度的信息（包括损失、步骤计数和步骤时间等关键详细信息）由 rank 0 进程生成。此进程在名称以 `$USER-qwen3-30b-pai-megatron-workload-0-0` 开头的 Pod 上运行。

### 结果分析

作业完成后，会创建多个工件（包括日志和跟踪），并将它们放置在配置的 Google Cloud Storage 存储桶中，结构如下：

```
gs://${GCS_BUCKET}/logs/output_mcore_qwen3_pretrain/
├── checkpoints/
├── logs/
└── tensorboard/
```

以及 NFS 存储中的模型文件：

```
/mnt/
├── Pai-Megatron-Patch-GCP/
├── qwen-ckpts/
│   ├── Qwen3-30B-A3B/
│   └── Qwen3-30B-A3B-to-mcore/
├── qwen-datasets/
└── logs/
```

### 环境变量配置说明

本配方支持以下环境变量配置：

| 环境变量 | 默认值 | 说明 |
|---------|--------|------|
| `SKIP_CLONE_REPO` | `false` | 设置为 `true` 跳过代码库克隆 |
| `SKIP_DOWNLOAD_DATA` | `false` | 设置为 `true` 跳过数据下载 |
| `SKIP_CHECKPOINT_CONVERSION` | `false` | 设置为 `true` 跳过检查点转换 |
| `SKIP_TRAINING` | `false` | 设置为 `true` 跳过训练执行 |
| `SSH_PUBLIC_KEY` | 预设值 | SSH 公钥，用于节点间通信 |
| `SLEEP_INFINITY` | `true` | 控制容器是否保持运行 |
| `PAI_WORKSPACE_ROOT` | `/mnt` | 工作目录根路径 |
| `HF_TOKEN` | 预设值 | HuggingFace 访问令牌 |

### 故障排除

本节提供训练作业问题的故障排除指导。

要检查作业 Pod 的状态，请使用以下命令：

```bash
kubectl get pods | grep $USER-qwen3-30b-pai-megatron
```

要从特定 Pod 获取日志，请使用以下命令：

```bash
kubectl logs POD_NAME
```

**常见问题：**

1. **SSH 连接失败**
   - 检查 `SSH_PUBLIC_KEY` 环境变量是否正确设置
   - 确保所有节点的 SSH 服务正常启动

2. **数据下载失败**
   - 检查 `HF_TOKEN` 是否有效
   - 确保网络连接正常

3. **存储空间不足**
   - 检查 NFS 存储空间
   - 清理不需要的临时文件

4. **训练进程卡住**
   - 检查节点间网络连通性
   - 查看 NCCL 通信日志

### 卸载 Helm 发布

您可以删除 Helm Chart 创建的作业和其他资源。要卸载 Helm，请从客户端运行以下命令：

```bash
helm uninstall $USER-qwen3-30b-pai-megatron
```

## 技术特性

### 分布式训练架构
- 基于 Pai-Megatron-Patch 框架的分布式训练
- 支持数据并行和模型并行
- 自动负载均衡和故障恢复

### 性能优化
- NCCL gIB 插件优化网络通信
- 物理拓扑感知的节点调度
- 内存和计算资源优化

### 可扩展性
- 支持从 2 节点扩展到更大规模
- 模块化设计便于功能扩展
- 灵活的配置管理

## 总结

本指南提供了在 A4 GKE 节点池上使用 Pai-Megatron-Patch 框架预训练 Qwen3-30B 模型的完整流程。通过遵循这些步骤，您可以：

1. 设置适当的 GKE 环境
2. 配置和部署预训练作业
3. 监控训练进度
4. 管理分布式训练流程
5. 排除常见问题

本配方的模块化设计和灵活的环境变量配置使其易于定制和扩展，适合各种训练场景和需求。

如需更多信息和支持，请参考相关的配置文件和文档链接。