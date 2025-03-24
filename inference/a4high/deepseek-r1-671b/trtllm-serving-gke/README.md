# Single Node Inference Benchmark of DeepSeek R1 671B with TensorRT-LLM on A4 High GKE Node Pool

English | [简体中文](README_CN.md)

This recipe outlines the steps to benchmark the inference of a DeepSeek R1 671B model using [TensorRT-LLM](https://github.com/NVIDIA/TensorRT-LLM) on an [A4 High GKE Node pool](https://cloud.google.com/kubernetes-engine) with a single node.

## Orchestration and Deployment Tools

For this recipe, the following setup is used:

- **Orchestration** - [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine)
- **Job Configuration and Deployment** - Helm charts are used to configure and deploy the necessary Kubernetes resources
  - The deployment encapsulates the inference of the DeepSeek R1 671B model using TensorRT-LLM
  - Generated manifests adhere to best practices for using RDMA Over Ethernet (RoCE) on GKE
  - Optimized for high-performance inference on A4 High nodes with B200 GPUs

## Prerequisites

To prepare the required environment, see
[GKE environment setup guide](../../../../docs/configuring-environment-gke-a4-high.md).

Before running this recipe, ensure your environment is configured as follows:

- **GKE Cluster Requirements**:
    - An A4 High node pool (1 node with 8× B200 GPUs)
    - Topology-aware scheduling enabled
    - NVIDIA drivers and GPU operators properly installed

- **Storage and Registry**:
    - An Artifact Registry repository to store the Docker image
    - A Google Cloud Storage (GCS) bucket to store results
      *Important: This bucket must be in the same region as the GKE cluster*

- **Client Tooling**:
    - Google Cloud SDK (latest version)
    - Helm v3+
    - kubectl

- **Model Access**:
    - A Hugging Face token to access the [DeepSeek R1 671B model](https://huggingface.co/deepseek-ai/DeepSeek-R1)
    - To generate a token:
      1. Create/login to your [Hugging Face account](https://huggingface.co/)
      2. Navigate to Profile > Settings > Access Tokens
      3. Select "New Token"
      4. Choose a name and at least "Read" permissions
      5. Generate and copy the token

## Run the recipe

### Launch Cloud Shell

In the Google Cloud console, start a [Cloud Shell Instance](https://console.cloud.google.com/?cloudshell=true).

### Configure Environment Settings

From your client, complete the following steps:

1. Set environment variables to match your environment:

  ```bash
  export PROJECT_ID=<PROJECT_ID>               # Your Google Cloud project ID
  export REGION=<REGION>                       # Region for Cloud Build
  export CLUSTER_REGION=<CLUSTER_REGION>       # Region where your cluster is located
  export CLUSTER_NAME=<CLUSTER_NAME>           # Name of your GKE cluster
  export GCS_BUCKET=<GCS_BUCKET>               # Cloud Storage bucket name (without gs:// prefix)
  export ARTIFACT_REGISTRY=<ARTIFACT_REGISTRY> # Format: LOCATION-docker.pkg.dev/PROJECT_ID/REPOSITORY
  export TRTLLM_IMAGE=trtllm-serving           # Name for the TensorRT-LLM image
  export TRTLLM_VERSION=latest                 # Version tag for the TensorRT-LLM image
  ```

2. Set the default project:

  ```bash
  gcloud config set project $PROJECT_ID
  ```

### Get the Recipe

From your client, clone the `gpu-recipes` repository and set references to key directories:

```bash
git clone https://github.com/yangwhale/gpu-recipes.git
cd gpu-recipes
export REPO_ROOT=`git rev-parse --show-toplevel`
export RECIPE_ROOT=$REPO_ROOT/inference/a4high/deepseek-r1-671b/trtllm-serving-gke
```

### Get Cluster Credentials

From your client, authenticate with your GKE cluster:

```bash
gcloud container clusters get-credentials $CLUSTER_NAME --region $CLUSTER_REGION
```

### Build and Push the TensorRT-LLM Container Image

Follow these steps to build and push the TensorRT-LLM container:

1. Use Cloud Build to build and push the container image:

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
    This command will output a `build ID` for tracking purposes.

2. Monitor the build progress by streaming the logs for the `build ID`:

    ```bash
    BUILD_ID=<BUILD_ID>  # Replace with your actual build ID
    gcloud beta builds log $BUILD_ID --region=$REGION
    ```

## Single A4 High Node Serving of DeepSeek R1 671B with TensorRT-LLM

This recipe serves the DeepSeek R1 671B model using TensorRT-LLM on a single A4 High node, optimized for high-performance inference with FP8 precision.

To start the serving, the recipe launches a TensorRT-LLM server that performs the following steps:
1. Downloads the full DeepSeek R1 671B model checkpoints from [Hugging Face](https://huggingface.co/deepseek-ai/DeepSeek-R1)
2. Loads the model checkpoints and applies TensorRT-LLM optimizations including tensor parallelism and FP8 quantization
3. Builds optimized TensorRT engines for each GPU
4. Starts the inference server with the optimized model ready to respond to requests

The process is orchestrated using a Helm chart that configures all necessary Kubernetes resources.

1. Create a Kubernetes Secret with your Hugging Face token to enable model downloads:

    ```bash
    export HF_TOKEN=<YOUR_HUGGINGFACE_TOKEN>
    
    kubectl create secret generic hf-secret \
    --from-literal=hf_api_token=${HF_TOKEN} \
    --dry-run=client -o yaml | kubectl apply -f -
    ```

2. Install the Helm chart to deploy the TensorRT-LLM server:

    ```bash
    cd $RECIPE_ROOT
    helm install -f values.yaml \
    --set "volumes.gcsMounts[0].bucketName"=${GCS_BUCKET} \
    --set job.image.repository=${ARTIFACT_REGISTRY}/${TRTLLM_IMAGE} \
    --set job.image.tag=${TRTLLM_VERSION} \
    $USER-serving-deepseek-r1-model \
    $REPO_ROOT/src/helm-charts/a4high/trtllm-inference
    ```

3. View the logs for the deployment to monitor model loading and engine building:
    ```bash
    kubectl logs -f deployment/$USER-serving-deepseek-r1-model
    ```

4. Verify the deployment status:
    ```bash
    kubectl get deployment/$USER-serving-deepseek-r1-model
    ```

5. During initialization, you'll see logs showing the model loading and TensorRT engine building process. Once the server is ready, you'll see log output similar to:
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

6. To make API requests to the service, you can port forward the service to your local machine:

    ```bash
    kubectl port-forward svc/$USER-serving-deepseek-r1-model-svc 8000:8000
    ```

7. Make API requests to the service using the OpenAI-compatible API:

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
          "content": "How many r are there in strawberry?"
        }
      ],
      "temperature": 0.6,
      "top_p": 0.95,
      "max_tokens": 128
    }'
    ```

    You should receive a response similar to this:
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
            "content": "The word \"strawberry\" contains 3 instances of the letter 'r'. They are located at positions 3, 8, and 9 in the word (S-T-R-A-W-B-E-R-R-Y)."
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

8. For a more interactive experience, use the provided utility script to stream responses in real-time:
    ```bash
    ./stream_chat.sh "Which is bigger 9.9 or 9.11?"
    ```

9. To run benchmarks for inference, use the TensorRT-LLM benchmarking utility:

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

    Once the benchmark is complete, you'll see results similar to:

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

### Cleanup

To clean up the resources created by this recipe, complete the following steps:

1. Uninstall the helm chart:

    ```bash
    helm uninstall $USER-serving-deepseek-r1-model
    ```

2. Delete the Kubernetes Secret:

    ```bash
    kubectl delete secret hf-secret
    ```

### Running the recipe on a cluster that doesn't use the default configuration

If you created your cluster using the [GKE environment setup guide](../../../../docs/configuring-environment-gke-a4-high.md), it's configured with default settings that include the names for networks and subnetworks used for communication between:

- The host to external services
- GPU-to-GPU communication

For clusters with this default configuration, the Helm chart can automatically generate the [required networking annotations in a Pod's metadata](https://cloud.google.com/ai-hypercomputer/docs/create/gke-ai-hypercompute-custom#configure-pod-manifests-rdma). Therefore, you can use the streamlined command to install the chart, as described earlier in this guide.

To configure the correct networking annotations for a cluster that uses non-default names for GKE Network resources, you must provide the names of the GKE Network resources in your cluster when installing the chart. Use the following example command, remembering to replace the example values with the actual names of your cluster's GKE Network resources:

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
