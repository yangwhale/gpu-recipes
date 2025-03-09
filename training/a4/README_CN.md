# A4 GPU 训练指南

本目录包含在 Google A4 GPU 上训练大型语言模型的配置和工具。

## 支持的模型

- ✅ Llama3-8B - 已准备就绪
- 🚧 Mixtral-8x7B - 开发中

## 可用配置

我们提供了以下训练配置：

| 模型 | 数据类型 | 配置文件 |
|------|---------|---------|
| Llama3-8B | BF16 | `recipe/llama3_8b_bf16.yaml` |
| Llama3-8B | FP8 | `recipe/llama3_8b_fp8.yaml` |
| Mixtral-8x7B | BF16 | `recipe/mixtral8x7B_bf16.yaml` |
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

### 2. 选择训练配置

```bash
# 选择一个配置（取消注释您想使用的配置）
# export RECIPE_NAME=llama3_8b_bf16
export RECIPE_NAME=llama3_8b_fp8
# export RECIPE_NAME=mixtral8x7b_bf16
# export RECIPE_NAME=mixtral8x7b_fp8

# 复制所选配置
cp recipe/$RECIPE_NAME.yaml selected-configuration.yaml
```

### 3. 启动工作负载

```bash
RECIPE_NAME_UPDATE=${RECIPE_NAME//_/-}
export WORKLOAD_NAME=$USER-$RECIPE_NAME_UPDATE-16gpu
helm install $WORKLOAD_NAME helm-context/
```

### 4. 检查工作负载状态

```bash
kubectl get pods | grep $WORKLOAD_NAME
kubectl logs <pod-name>
```

### 5. 卸载工作负载

```bash
helm uninstall $WORKLOAD_NAME
```

## 自定义配置

您可以通过修改 `selected-configuration.yaml` 文件来自定义训练参数，或者在 `recipe/` 目录中创建新的配置模板。

## 文件结构

- `command.sh` - 运行训练的主要脚本
- `docker/` - 包含 Docker 配置
- `helm-context/` - Helm chart 配置
- `recipe/` - 模型训练配置文件
- `selected-configuration.yaml` - 当前选定的配置