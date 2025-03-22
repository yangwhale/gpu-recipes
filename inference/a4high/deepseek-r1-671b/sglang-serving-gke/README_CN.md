# 在A4 GKE上使用SGL Lang部署DeepSeek R1 671B模型指南

本文档介绍如何在Google Kubernetes Engine (GKE) A4节点池上使用SGLang部署和运行DeepSeek R1 671B大型语言模型，包含完整的部署流程、测试方法和性能评估。

## 1. 概述

本指南将帮助您：
- 在A4 GKE集群上部署DeepSeek R1 671B模型
- 使用SGLang优化模型推理性能
- 通过API接口测试模型功能
- 进行性能基准测试

## 2. 环境要求

在开始部署前，确保您的环境满足以下条件：

- 已配置好的GKE集群，包含：
  - A4节点池(1个节点，8个GPU)
  - 已启用拓扑感知调度
- Google Artifact Registry存储库(用于存储Docker镜像)
- Google Cloud Storage (GCS)存储桶(存储结果数据)
  - **重要**：存储桶必须与GKE集群位于同一区域
- 客户端工作站已安装：
  - Google Cloud SDK
  - Helm
  - kubectl
  - git
- Hugging Face账户和API令牌(用于下载模型)

## 3. 使用command.sh脚本

`command.sh`脚本简化了整个部署流程，提供自动化部署、测试和清理功能。

### 3.1 脚本参数说明

```bash
Usage: ./command.sh [options]

Options:
  -p, --project-id PROJECT_ID    设置项目ID
  -r, --region REGION            设置构建区域
  -c, --cluster-region REGION    设置集群区域
  -n, --cluster-name NAME        设置集群名称
  -b, --gcs-bucket BUCKET        设置GCS存储桶名称(不包含gs://前缀)
  -a, --artifact-registry REGISTRY 设置Artifact Registry名称
  -t, --hf-token TOKEN           设置Hugging Face API令牌
  -h, --help                     显示帮助信息并退出
  --build-only                   仅构建Docker镜像
  --deploy-only                  仅部署模型服务
  --test-only                    仅测试已部署的服务
  --cleanup                      清理资源
```

### 3.2 部署示例

以下是几个使用`command.sh`的实际例子：

#### 示例1: 完整流程（构建、部署和测试）

```bash
./command.sh \
  --project-id your-project-id \
  --region us-central1 \
  --cluster-region us-central1 \
  --cluster-name a4-cluster \
  --gcs-bucket your-bucket-name \
  --artifact-registry us-central1-docker.pkg.dev/your-project-id/your-repo \
  --hf-token your-huggingface-token
```

#### 示例2: 仅构建Docker镜像

```bash
./command.sh \
  --project-id your-project-id \
  --region us-central1 \
  --cluster-region us-central1 \
  --cluster-name a4-cluster \
  --gcs-bucket your-bucket-name \
  --artifact-registry us-central1-docker.pkg.dev/your-project-id/your-repo \
  --build-only
```

#### 示例3: 仅部署模型服务（假设Docker镜像已构建）

```bash
./command.sh \
  --project-id your-project-id \
  --region us-central1 \
  --cluster-region us-central1 \
  --cluster-name a4-cluster \
  --gcs-bucket your-bucket-name \
  --artifact-registry us-central1-docker.pkg.dev/your-project-id/your-repo \
  --hf-token your-huggingface-token \
  --deploy-only
```

#### 示例4: 仅测试已部署的服务

```bash
./command.sh \
  --project-id your-project-id \
  --region us-central1 \
  --cluster-region us-central1 \
  --cluster-name a4-cluster \
  --gcs-bucket your-bucket-name \
  --artifact-registry us-central1-docker.pkg.dev/your-project-id/your-repo \
  --test-only
```

#### 示例5: 清理资源

```bash
./command.sh \
  --project-id your-project-id \
  --region us-central1 \
  --cluster-region us-central1 \
  --cluster-name a4-cluster \
  --gcs-bucket your-bucket-name \
  --artifact-registry us-central1-docker.pkg.dev/your-project-id/your-repo \
  --cleanup
```

## 4. 手动部署步骤

如果您想了解`command.sh`背后的详细步骤，以下是手动部署流程：

### 4.1 设置环境变量

```bash
export PROJECT_ID=your-project-id
export REGION=us-central1
export CLUSTER_REGION=us-central1
export CLUSTER_NAME=a4-cluster
export GCS_BUCKET=your-bucket-name
export ARTIFACT_REGISTRY=us-central1-docker.pkg.dev/your-project-id/your-repo
export SGLANG_IMAGE=sglang
export SGLANG_VERSION=v0.4.2.post1-cu125
export HF_TOKEN=your-huggingface-token
```

### 4.2 获取集群凭证

```bash
gcloud container clusters get-credentials $CLUSTER_NAME --region $CLUSTER_REGION
```

### 4.3 构建和推送Docker镜像

```bash
cd $REPO_ROOT/src/docker/sglang
gcloud builds submit --region=${REGION} \
    --config cloudbuild.yml \
    --substitutions _ARTIFACT_REGISTRY=$ARTIFACT_REGISTRY,_SGLANG_IMAGE=$SGLANG_IMAGE,_SGLANG_VERSION=$SGLANG_VERSION \
    --timeout "2h" \
    --machine-type=e2-highcpu-32 \
    --disk-size=1000
```

### 4.4 创建Kubernetes Secret

```bash
kubectl create secret generic hf-secret \
  --from-literal=hf_api_token=${HF_TOKEN} \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 4.5 部署模型服务

```bash
cd $RECIPE_ROOT
helm install -f values.yaml \
  --set volumes.gcsMounts[0].bucketName=${GCS_BUCKET} \
  --set clusterName=$CLUSTER_NAME \
  --set job.image.repository=${ARTIFACT_REGISTRY}/${SGLANG_IMAGE} \
  --set job.image.tag=${SGLANG_VERSION} \
  $USER-serving-deepseek-r1-model \
  $REPO_ROOT/src/helm-charts/a4/sglang-inference
```

## 5. 测试部署

### 5.1 验证部署状态

```bash
kubectl get deployment/$USER-serving-deepseek-r1-model
```

### 5.2 查看日志

```bash
kubectl logs -f deployment/$USER-serving-deepseek-r1-model
```

### 5.3 设置端口转发

```bash
kubectl port-forward svc/$USER-serving-deepseek-r1-model-svc 30000:30000
```

### 5.4 发送测试请求

```bash
curl -s http://localhost:30000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model":"default",
    "messages":[
        {
          "role":"system",
          "content":"You are a helpful AI assistant"
        },
        {
          "role":"user",
          "content":"How many r are there in strawberry ?"
        }
    ],
    "temperature":0.6,
    "top_p":0.95,
    "max_tokens":2048
  }' | jq '.'
```

### 5.5 使用流式聊天脚本

```bash
./stream_chat.sh "Tell me a short joke"
```

## 6. 性能基准测试

使用SGLang提供的基准测试工具评估模型性能：

```bash
# 获取Pod名称
POD_NAME=$(kubectl get pods -l app=$USER-serving-deepseek-r1-model -o jsonpath='{.items[0].metadata.name}')

# 运行基准测试
kubectl exec -it $POD_NAME -- python3 -m sglang.bench_serving \
  --backend sglang \
  --dataset-name random \
  --random-range-ratio 1 \
  --num-prompt 1100 \
  --random-input 1000 \
  --random-output 1000 \
  --host 0.0.0.0 \
  --port 30000 \
  --output-file /gcs/benchmark_logs/sglang/ds_1000_1000_1100_output.jsonl
```

## 7. 清理资源

完成测试后，清理已创建的资源：

```bash
# 卸载Helm图表
helm uninstall $USER-serving-deepseek-r1-model

# 删除Kubernetes Secret
kubectl delete secret hf-secret
```

## 8. 故障排除

### 8.1 如果模型部署时间过长

检查GPU驱动程序和CUDA版本是否兼容：

```bash
POD_NAME=$(kubectl get pods -l app=$USER-serving-deepseek-r1-model -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD_NAME -- nvidia-smi
```

### 8.2 如果无法访问API

检查服务是否正常运行，并验证端口转发：

```bash
kubectl get svc/$USER-serving-deepseek-r1-model-svc
kubectl port-forward svc/$USER-serving-deepseek-r1-model-svc 30000:30000
```

## 9. 自定义网络配置

对于使用非默认网络配置的集群，需要在安装Helm图表时提供网络配置：

```bash
helm install -f values.yaml \
  --set volumes.gcsMounts[0].bucketName=${GCS_BUCKET} \
  --set clusterName=$CLUSTER_NAME \
  --set job.image.repository=${ARTIFACT_REGISTRY}/${SGLANG_IMAGE} \
  --set job.image.tag=${SGLANG_VERSION} \
  --set network.subnetworks[0]=default \
  --set network.subnetworks[1]=gvnic-1 \
  --set network.subnetworks[2]=rdma-0 \
  --set network.subnetworks[3]=rdma-1 \
  --set network.subnetworks[4]=rdma-2 \
  --set network.subnetworks[5]=rdma-3 \
  --set network.subnetworks[6]=rdma-4 \
  --set network.subnetworks[7]=rdma-5 \
  --set network.subnetworks[8]=rdma-6 \
  --set network.subnetworks[9]=rdma-7 \
  $USER-serving-deepseek-r1-model \
  $REPO_ROOT/src/helm-charts/a4/sglang-inference
```

## 10. 总结

通过本指南，您已了解如何使用`command.sh`脚本在A4 GKE上部署DeepSeek R1 671B模型，包括各种部署选项、测试方法和性能评估。该脚本大大简化了部署流程，使您能够更轻松地在Google Cloud上运行大型语言模型推理服务。