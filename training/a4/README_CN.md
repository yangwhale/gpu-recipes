# A4 GPU 训练指南

本目录包含在 Google A4 GPU 上训练大型语言模型的配置和工具。

[English Document](./README.md)

## 支持的模型

- ✅ Llama3-8B FP8 - 已准备就绪
- ✅ Mixtral-8x7B FP8 - 已准备就绪
- ✅ Llama-3.1-70B FP8 - 已准备就绪
- ✅ Llama3-8B BF16 - 已准备就绪
- 🚧 Mixtral-8x7B BF16 - 开发中
- ✅ Llama-3.1-70B 256 GPUs FP8 - 已准备就绪

## 可用配置

我们提供了以下训练配置：

| 模型 | 数据类型 | 配置文件 |
|------|---------|---------|
| Llama3-8B | BF16 | `recipe/llama3_8b_bf16.yaml` |
| Llama3-8B | FP8 | `recipe/llama3_8b_fp8.yaml` |
| Llama-3.1-70B | FP8 | `recipe/llama-3.1-70b-fp8.yaml` |
| Llama-3.1-70B (256 GPUs) | FP8 | `recipe/llama-3.1-70b-256gpus-fp8.yaml` |
| Mixtral-8x7B | BF16 | `recipe/mixtral8x7b_bf16.yaml` |
| Mixtral-8x7B | FP8 | `recipe/mixtral8x7b_fp8.yaml` |

## 使用方法

### 1. 连接到 GKE 集群

```bash
export PROJECT=your-project-id
export REGION=us-central1
export ZONE=us-central1-b
export CLUSTER_NAME=your-gke-cluster

gcloud config set project ${PROJECT}
gcloud config set compute/zone ${ZONE}
gcloud container clusters get-credentials $CLUSTER_NAME --region $REGION
```

### 2. 创建并配置 GCS 存储桶

训练作业需要访问 GCS 存储桶来存储和读取数据。请按照以下步骤操作：

1. 创建一个 GCS 存储桶（如果尚未创建）：
   ```bash
   export GCS_BUCKET=your-bucket-name
   gsutil mb -l us-central1 gs://${GCS_BUCKET}
   ```

2. 编辑 `helm-context/values.yaml` 文件，配置 GCS 存储桶挂载：
   ```yaml
   # <GCS_BUCKET>: 您的 Cloud Storage 存储桶名称，不要包含 gs:// 前缀，不要漏掉双引号
   jitGcsMount:
     bucketName: "<GCS_BUCKET>"
     mountPath: "/gcs"
   ```

### 3. 选择训练配置

```bash
# 选择一个配置（取消注释您想使用的配置）
# export RECIPE_NAME=llama3_8b_bf16
# export RECIPE_NAME=llama3_8b_fp8
# export RECIPE_NAME=llama-3.1-70b-fp8
export RECIPE_NAME=llama-3.1-70b-256gpus-fp8
# export RECIPE_NAME=mixtral8x7b_bf16
# export RECIPE_NAME=mixtral8x7b_fp8

# 复制所选配置
cp recipe/$RECIPE_NAME.yaml helm-context/selected-configuration.yaml
```

### 4. 启动工作负载

```bash
RECIPE_NAME_UPDATE=${RECIPE_NAME//_/-}
RECIPE_NAME_UPDATE=${RECIPE_NAME_UPDATE//./-}
export WORKLOAD_NAME=$USER-$RECIPE_NAME_UPDATE-16gpu
helm install $WORKLOAD_NAME helm-context/
```

### 5. 检查工作负载状态

```bash
kubectl get pods | grep $WORKLOAD_NAME
kubectl logs <pod-name>
```

如需持续查看日志，可以使用 `-f` 参数：
```bash
kubectl logs -f <pod-name>
```

### 6. 卸载工作负载

```bash
helm uninstall $WORKLOAD_NAME
```

## 自定义配置

您可以通过修改 `selected-configuration.yaml` 文件来自定义训练参数，或者在 `recipe/` 目录中创建新的配置模板。

## 文件结构

- `command.sh` - 训练演示脚本
- `docker/` - 包含 Docker 配置
- `helm-context/` - Helm chart 配置
- `recipe/` - 模型训练配置文件
- `results/` - 训练日志文件和性能指标