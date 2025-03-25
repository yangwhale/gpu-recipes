# 在A4 High GKE节点池上使用TensorRT-LLM对DeepSeek R1 671B模型进行单节点推理

[English](README.md) | 简体中文

本指南概述了如何在[A4 High GKE节点池](https://cloud.google.com/kubernetes-engine)单节点上使用[TensorRT-LLM](https://github.com/NVIDIA/TensorRT-LLM)对DeepSeek R1 671B模型进行推理基准测试。

## 编排和部署工具

在本指南中，使用了以下设置：

- **编排工具** - [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine)
- **作业配置和部署** - 使用Helm charts配置和部署必要的Kubernetes资源
  - 部署封装了使用TensorRT-LLM对DeepSeek R1 671B模型进行推理的过程
  - 生成的清单遵循GKE上使用RDMA Over Ethernet (RoCE)的最佳实践
  - 针对A4 High节点上的B200 GPU进行了高性能推理优化

## 前提条件

要准备所需的环境，请参阅
[GKE环境设置指南](../../../../docs/configuring-environment-gke-a4-high.md)。

在运行此指南之前，请确保您的环境配置如下：

- **GKE集群要求**：
    - 一个A4 High节点池（1个节点，配备8个B200 GPU）
    - 启用拓扑感知调度
    - 正确安装NVIDIA驱动程序和GPU操作员

- **存储和注册表**：
    - 一个用于存储Docker镜像的Artifact Registry仓库
    - 一个用于存储结果的Google Cloud Storage (GCS)存储桶
      *重要：此存储桶必须与GKE集群位于同一区域*

- **客户端工具**：
    - Google Cloud SDK（最新版本）
    - Helm v3+
    - kubectl

- **模型访问**：
    - 需要一个Hugging Face令牌来访问[DeepSeek R1 671B模型](https://huggingface.co/deepseek-ai/DeepSeek-R1)
    - 生成令牌的步骤：
      1. 创建/登录您的[Hugging Face账户](https://huggingface.co/)
      2. 导航至Profile > Settings > Access Tokens
      3. 选择"New Token"
      4. 选择一个名称并至少设置"Read"权限
      5. 生成并复制令牌

## 运行指南

### 启动Cloud Shell

在Google Cloud控制台中，启动[Cloud Shell实例](https://console.cloud.google.com/?cloudshell=true)。

### 配置环境设置

从您的客户端，完成以下步骤：

1. 设置环境变量以匹配您的环境：

  ```bash
  export PROJECT_ID=<PROJECT_ID>               # 您的Google Cloud项目ID
  export REGION=<REGION>                       # 用于Cloud Build的区域
  export CLUSTER_REGION=<CLUSTER_REGION>       # 集群所在的区域
  export CLUSTER_NAME=<CLUSTER_NAME>           # GKE集群的名称
  export GCS_BUCKET=<GCS_BUCKET>               # Cloud Storage存储桶名称（不包含gs://前缀）
  export ARTIFACT_REGISTRY=<ARTIFACT_REGISTRY> # 格式：LOCATION-docker.pkg.dev/PROJECT_ID/REPOSITORY
  export TRTLLM_IMAGE=trtllm                   # TensorRT-LLM镜像的名称
  export TRTLLM_VERSION=latest                 # TensorRT-LLM镜像的版本标签
  ```

2. 设置默认项目：

  ```bash
  gcloud config set project $PROJECT_ID
  ```

### 获取指南

从您的客户端，克隆`gpu-recipes`仓库并设置关键目录的引用：

```bash
git clone -b a4-early-access https://github.com/yangwhale/gpu-recipes.git
cd gpu-recipes
export REPO_ROOT=`git rev-parse --show-toplevel`
export RECIPE_ROOT=$REPO_ROOT/inference/a4high/deepseek-r1-671b/trtllm-serving-gke
```

### 获取集群凭据

从您的客户端，通过以下命令验证GKE集群：

```bash
gcloud container clusters get-credentials $CLUSTER_NAME --region $CLUSTER_REGION
```

### 构建并推送TensorRT-LLM容器镜像

按照以下步骤构建并推送TensorRT-LLM容器：

1. 使用Cloud Build构建并推送容器镜像：

    ```bash
    cd $REPO_ROOT/src/docker/trtllm-0.17.0
    gcloud builds submit --region=${REGION} \
        --config cloudbuild.yml \
        --substitutions _ARTIFACT_REGISTRY=$ARTIFACT_REGISTRY,_TRTLLM_IMAGE=$TRTLLM_IMAGE,_TRTLLM_VERSION=$TRTLLM_VERSION \
        --timeout "2h" \
        --machine-type=e2-highcpu-32 \
        --disk-size=1000 \
        --quiet \
        --async
    ```
    此命令将输出一个`构建ID`，用于跟踪目的。

2. 通过流式传输`构建ID`的日志来监控构建进度：

    ```bash
    BUILD_ID=<BUILD_ID>  # 替换为您的实际构建ID
    gcloud beta builds log $BUILD_ID --region=$REGION
    ```

## 使用TensorRT-LLM在单个A4 High节点上部署DeepSeek R1 671B模型

本指南使用TensorRT-LLM在单个A4 High节点上部署DeepSeek R1 671B模型，针对FP8精度进行了高性能推理优化。

要启动服务，本指南启动一个TensorRT-LLM服务器，该服务器执行以下步骤：
1. 从[Hugging Face](https://huggingface.co/deepseek-ai/DeepSeek-R1)下载完整的DeepSeek R1 671B模型检查点
2. 加载模型检查点并应用TensorRT-LLM优化，包括张量并行和FP8量化
3. 为每个GPU构建优化的TensorRT引擎
4. 启动推理服务器，准备响应请求

整个过程通过Helm chart配置所有必要的Kubernetes资源来编排。

1. 创建一个包含Hugging Face令牌的Kubernetes Secret，以启用模型下载：

    ```bash
    export HF_TOKEN=<YOUR_HUGGINGFACE_TOKEN>
    
    kubectl create secret generic hf-secret \
    --from-literal=hf_api_token=${HF_TOKEN} \
    --dry-run=client -o yaml | kubectl apply -f -
    ```

2. 安装Helm chart来部署TensorRT-LLM服务器：

    ```bash
    cd $RECIPE_ROOT
    helm install -f values.yaml \
    --set "volumes.gcsMounts[0].bucketName"=${GCS_BUCKET} \
    --set job.image.repository=${ARTIFACT_REGISTRY}/${TRTLLM_IMAGE} \
    --set job.image.tag=${TRTLLM_VERSION} \
    $USER-serving-deepseek-r1-model \
    $REPO_ROOT/src/helm-charts/a4high/trtllm-inference
    ```

3. 查看部署的日志，监控模型加载和引擎构建进度：
    ```bash
    kubectl logs -f deployment/$USER-serving-deepseek-r1-model
    ```

4. 验证部署状态：
    ```bash
    kubectl get deployment/$USER-serving-deepseek-r1-model
    ```

5. 在初始化过程中，您将看到显示模型加载和TensorRT引擎构建过程的日志。服务器准备就绪后，您将看到类似以下内容的日志输出：
    ```
    [INFO] TensorRT-LLM build engine done!
    [INFO] Engine(s) loaded
    [INFO] Model initialized successfully
    [INFO] Starting server on http://0.0.0.0:8000
    [INFO] Server routes initialized:
    [INFO] - GET     /v1/models
    [INFO] - POST    /v1/chat/completions
    [INFO] - POST    /v1/completions
    [INFO] - GET     /health
    [INFO] - GET     /ready
    [INFO] Server listening on port 8000
    ```

6. 要向服务发送API请求，您可以将服务端口转发到本地机器：

    ```bash
    kubectl port-forward svc/$USER-serving-deepseek-r1-model-svc 8000:8000
    ```

7. 使用OpenAI兼容API向服务发送API请求：

    ```bash
    curl http://localhost:8000/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{
      "model": "deepseek-ai/DeepSeek-R1",
      "messages": [
        {
          "role": "system",
          "content": "You are a helpful AI assistant"
        },
        {
          "role": "user",
          "content": "草莓单词中有几个字母r？"
        }
      ],
      "temperature": 0.6,
      "top_p": 0.95,
      "max_tokens": 128
    }'
    ```

    如果一切设置正确，您应该会收到类似以下的响应：
    ```json
    {
      "id": "trtllm-fe5a9d3b7c",
      "object": "chat.completion",
      "created": 1742011687,
      "model": "deepseek-ai/DeepSeek-R1",
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "content": "英文单词"strawberry"（草莓）中有3个字母'r'。它们位于单词的第3、第8和第9位置(S-T-R-A-W-B-E-R-R-Y)。"
          },
          "finish_reason": "stop"
        }
      ],
      "usage": {
        "prompt_tokens": 19,
        "completion_tokens": 34,
        "total_tokens": 53
      }
    }
    ```

8. 要获得更交互式的体验，使用提供的工具脚本实时流式传输响应：
    ```bash
    ./stream_chat.sh "9.9和9.11哪个更大？"
    ```

9. 要运行推理基准测试，使用TensorRT-LLM基准测试工具：

    ```bash
    kubectl exec -it deployments/$USER-serving-deepseek-r1-model -- python3 -m tensorrt_llm.tools.benchmark \
      --engine-dir /tmp/tensorrt_llm_models/deepseek-ai/DeepSeek-R1 \
      --mode generation \
      --input-tokens 512 \
      --output-tokens 128 \
      --batch-size 8 \
      --iterations 10 \
      --num-beams 1
    ```

    基准测试完成后，您将看到类似以下的结果：

    ```
    ======================= Benchmark Result =======================
    Engine Information:
      Model name: deepseek-ai/DeepSeek-R1
      Engine precision: float8
      Tensor parallelism: 8
      Pipeline parallelism: 1
    
    Performance Summary:
      Input length: 512 tokens
      Output length: 128 tokens
      Batch size: 8
      Number of iterations: 10
      
      Throughput metrics:
        Average generation throughput: 172.4 tokens/sec
        Average end-to-end throughput: 101.8 tokens/sec
      
      Latency metrics:
        Average time to first token: 752 ms
        Average inter-token latency: 5.8 ms
      
      Memory metrics:
        GPU memory used: 62.3 GB
        GPU memory utilization: 93.4%
    
    Detailed breakdown:
      Average prompt processing time: 325 ms
      Average token generation time: 743 ms
      Total e2e processing time: 1068 ms
    =================================================================
    ```

### 清理

要清理此指南创建的资源，完成以下步骤：

1. 卸载helm chart：

    ```bash
    helm uninstall $USER-serving-deepseek-r1-model
    ```

2. 删除Kubernetes Secret：

    ```bash
    kubectl delete secret hf-secret
    ```

### 在不使用默认配置的集群上运行此指南

如果您使用[GKE环境设置指南](../../../../docs/configuring-environment-gke-a4-high.md)创建集群，它将配置为默认设置，包括用于以下通信的网络和子网名称：

- 主机到外部服务
- GPU到GPU通信

对于使用此默认配置的集群，Helm chart可以自动生成[Pod元数据中所需的网络注释](https://cloud.google.com/ai-hypercomputer/docs/create/gke-ai-hypercompute-custom#configure-pod-manifests-rdma)。因此，您可以使用本指南前面描述的简化命令来安装chart。

要为使用非默认GKE网络资源名称的集群配置正确的网络注释，您必须在安装chart时提供集群中GKE网络资源的名称。使用以下示例命令，记得将示例值替换为集群的GKE网络资源的实际名称：

```bash
cd $RECIPE_ROOT
helm install -f values.yaml \
    --set job.image.repository=${ARTIFACT_REGISTRY}/${TRTLLM_IMAGE} \
    --set job.image.tag=${TRTLLM_VERSION} \
    --set volumes.gcsMounts[0].bucketName=${GCS_BUCKET} \
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
    $REPO_ROOT/src/helm-charts/a4high/trtllm-inference