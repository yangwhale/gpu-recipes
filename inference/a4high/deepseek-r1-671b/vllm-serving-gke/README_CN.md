# 在A4 High GKE节点池上使用vLLM对DeepSeek R1 671B模型进行单节点推理

[English](README.md) | 简体中文

本指南概述了如何在[A4 High GKE节点池](https://cloud.google.com/kubernetes-engine)单节点上使用[vLLM](https://github.com/vllm-project/vllm)对DeepSeek R1 671B模型进行推理基准测试。

## 编排和部署工具

在本指南中，使用了以下设置：

- **编排工具** - [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine)
- **作业配置和部署** - 使用Helm charts配置和部署
  [Kubernetes Indexed Job](https://kubernetes.io/blog/2021/04/19/introducing-indexed-jobs)
  - 部署封装了使用vLLM对DeepSeek R1 671B模型进行推理的过程
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
  export ARTIFACT_REGISTRY=vllm                # Artifact Registry仓库名称
  export VLLM_IMAGE=vllm-openai                # vLLM镜像的名称
  export VLLM_VERSION=v0.9.0                   # vLLM镜像的版本标签
  ```

  替换以下值：

  - `<PROJECT_ID>`: 您的Google Cloud项目ID
  - `<REGION>`: 您希望运行Cloud Build的区域
  - `<CLUSTER_REGION>`: 您的集群所在的区域
  - `<CLUSTER_NAME>`: 您的GKE集群名称
  - `<GCS_BUCKET>`: 您的Cloud Storage存储桶名称，不包含`gs://`前缀

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
export RECIPE_ROOT=$REPO_ROOT/inference/a4high/deepseek-r1-671b/vllm-serving-gke
```

### 获取集群凭据

从您的客户端，通过以下命令验证GKE集群：

```bash
gcloud container clusters get-credentials $CLUSTER_NAME --region $CLUSTER_REGION
```

## 使用vLLM在单个A4 High节点上部署DeepSeek R1 671B模型

本指南使用vLLM在单个A4 High节点上以原生FP8模式部署DeepSeek R1 671B模型。

要启动服务，本指南启动一个vLLM服务器，该服务器执行以下步骤：
1. 从[Hugging Face](https://huggingface.co/deepseek-ai/DeepSeek-R1)下载完整的DeepSeek R1 671B模型检查点
2. 加载模型检查点并应用vLLM优化
3. 服务器准备响应请求

整个过程通过Helm chart配置所有必要的Kubernetes资源来编排。

1. 创建一个包含Hugging Face令牌的Kubernetes Secret，以启用作业下载模型检查点：

    ```bash
    export HF_TOKEN=<YOUR_HUGGINGFACE_TOKEN>
    ```

    ```bash
    kubectl create secret generic hf-secret \
    --from-literal=hf_api_token=${HF_TOKEN} \
    --dry-run=client -o yaml | kubectl apply -f -
    ```

2. 安装Helm chart来准备模型：

    ```bash
    cd $RECIPE_ROOT
    helm install -f values.yaml \
    --set "volumes.gcsMounts[0].bucketName"=${GCS_BUCKET} \
    --set job.image.repository=${ARTIFACT_REGISTRY}/${VLLM_IMAGE} \
    --set job.image.tag=${VLLM_VERSION} \
    $USER-serving-deepseek-r1-model \
    $REPO_ROOT/src/helm-charts/a4high/vllm-inference
    ```

3. 查看部署的日志：
    ```bash
    kubectl logs -f deployment/$USER-serving-deepseek-r1-model
    ```

4. 验证部署是否已启动：
    ```bash
    kubectl get deployment/$USER-serving-deepseek-r1-model
    ```

5. 部署启动后，您将看到类似以下的日志：
    ```bash
    INFO 03-12 21:33:59 [api_server.py:958] Starting vLLM API server on http://0.0.0.0:8000
    INFO 03-12 21:33:59 [launcher.py:26] Available routes are:
    INFO 03-12 21:33:59 [launcher.py:34] Route: /openapi.json, Methods: HEAD, GET
    INFO 03-12 21:33:59 [launcher.py:34] Route: /docs, Methods: HEAD, GET
    INFO 03-12 21:33:59 [launcher.py:34] Route: /docs/oauth2-redirect, Methods: HEAD, GET
    INFO 03-12 21:33:59 [launcher.py:34] Route: /redoc, Methods: HEAD, GET
    INFO 03-12 21:33:59 [launcher.py:34] Route: /health, Methods: GET
    INFO 03-12 21:33:59 [launcher.py:34] Route: /ping, Methods: GET, POST
    INFO 03-12 21:33:59 [launcher.py:34] Route: /tokenize, Methods: POST
    INFO 03-12 21:33:59 [launcher.py:34] Route: /detokenize, Methods: POST
    INFO 03-12 21:33:59 [launcher.py:34] Route: /v1/models, Methods: GET
    INFO 03-12 21:33:59 [launcher.py:34] Route: /version, Methods: GET
    INFO 03-12 21:33:59 [launcher.py:34] Route: /v1/chat/completions, Methods: POST
    INFO 03-12 21:33:59 [launcher.py:34] Route: /v1/completions, Methods: POST
    INFO 03-12 21:33:59 [launcher.py:34] Route: /v1/embeddings, Methods: POST
    INFO 03-12 21:33:59 [launcher.py:34] Route: /pooling, Methods: POST
    INFO 03-12 21:33:59 [launcher.py:34] Route: /score, Methods: POST
    INFO 03-12 21:33:59 [launcher.py:34] Route: /v1/score, Methods: POST
    INFO 03-12 21:33:59 [launcher.py:34] Route: /v1/audio/transcriptions, Methods: POST
    INFO 03-12 21:33:59 [launcher.py:34] Route: /rerank, Methods: POST
    INFO 03-12 21:33:59 [launcher.py:34] Route: /v1/rerank, Methods: POST
    INFO 03-12 21:33:59 [launcher.py:34] Route: /v2/rerank, Methods: POST
    INFO 03-12 21:33:59 [launcher.py:34] Route: /invocations, Methods: POST
    INFO:     Started server process [148427]
    INFO:     Waiting for application startup.
    INFO:     Application startup complete.
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
      "model":"deepseek-ai/DeepSeek-R1",
      "messages":[
          {
            "role":"system",
            "content":"你是一个有用的AI助手"
          },
          {
            "role":"user",
            "content":"草莓这个英文单词中有几个字母r？"
          }
      ],
      "temperature":0.6,
      "top_p":0.95,
      "max_tokens":128
    }'
    ```

    如果一切设置正确，您应该会收到类似以下的响应：
    ```json
    {
      "id":"chatcmpl-cb53f9c2200c47399698d7f3ac2512b7",
      "object":"chat.completion",
      "created":1741031403,
      "model":"deepseek-ai/DeepSeek-R1",
      "choices":[
          {
            "index":0,
            "message":{
                "role":"assistant",
                "reasoning_content":null,
                "content":"<think>\n用户问的是\"草莓\"这个英文单词中有几个字母\"r\"。草莓的英文是\"strawberry\"。让我来数一下这个单词中有几个字母\"r\"。\n\nstrawberry的拼写是：s-t-r-a-w-b-e-r-r-y\n\n让我逐个字母检查：\n1. s\n2. t\n3. r (第一个r)\n4. a\n5. w\n6. b\n7. e\n8. r (第二个r)\n9. r (第三个r)\n10. y\n\n所以总共有3个字母\"r\"。\n</think>\n\n\"草莓\"的英文单词是\"strawberry\"。让我来数一下其中有几个字母\"r\"：\n\nstrawberry的拼写是：s-t-r-a-w-b-e-r-r-y\n\n其中字母\"r\"出现在：\n- 第3位：r\n- 第8位：r  \n- 第9位：r\n\n所以\"strawberry\"这个单词中总共有**3个字母r**。",
                "tool_calls":[]
            },
            "logprobs":null,
            "finish_reason":"stop",
            "stop_reason":null
          }
      ],
      "usage":{
          "prompt_tokens":19,
          "total_tokens":247,
          "completion_tokens":228,
          "prompt_tokens_details":null
      },
      "prompt_logprobs":null
    }
    ```
    模型的思考过程包含在`<think>`标签中，可以解析出来获取模型的推理过程。

8. 您也可以使用工具脚本`stream_chat.sh`来实时流式传输响应：
    ```bash
    ./stream_chat.sh "9.9和9.11哪个更大？"
    ```

9. 要运行推理基准测试，首先安装所需依赖，然后使用vLLM的默认基准测试工具：

    ```bash
    # 安装基准测试所需的依赖
    kubectl exec -it deployments/$USER-serving-deepseek-r1-model -- pip install datasets
    
    # 运行基准测试
    kubectl exec -it deployments/$USER-serving-deepseek-r1-model -- python3 benchmarks/benchmark_serving.py --model deepseek-ai/DeepSeek-R1 --dataset-name random --ignore-eos --num-prompts 1100 --random-input-len 1000 --random-output-len 1000 --port 8000 --backend vllm
    ```

    基准测试完成后，您可以在GCS存储桶中找到结果。您应该会看到类似以下的日志：

    ```bash
    ============ Serving Benchmark Result ============
    Successful requests:                     xxxx
    Benchmark duration (s):                  xxx.xx
    Total input tokens:                      xxxxxxx
    Total generated tokens:                  xxxxxxx
    Request throughput (req/s):              x.xx
    Output token throughput (tok/s):         xxxx.xx
    Total Token throughput (tok/s):          xxxx.xx
    ---------------Time to First Token----------------
    Mean TTFT (ms):                          xxxx.xx
    Median TTFT (ms):                        xxxx.xx
    P99 TTFT (ms):                           xxxx.xx
    -----Time per Output Token (excl. 1st token)------
    Mean TPOT (ms):                          xxx.xx
    Median TPOT (ms):                        xxx.xx
    P99 TPOT (ms):                           xxx.xx
    ---------------Inter-token Latency----------------
    Mean ITL (ms):                           xxx.xx
    Median ITL (ms):                         xxx.xx
    P99 ITL (ms):                            xxx.xx
    ==================================================
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