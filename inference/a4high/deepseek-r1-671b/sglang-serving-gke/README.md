# Serving DeepSeek R1 671B Model with SGLang on A4 GKE Node Pool

This recipe demonstrates how to deploy and serve the DeepSeek R1 671B model using [SGLang](https://github.com/sgl-project/sglang) on an [A4 GKE Node pool](https://cloud.google.com/kubernetes-engine) with a single node.

## Note: Currently under development, awaiting SGLang support for B200 release.

## Orchestration and deployment tools

For this recipe, the following setup is used:

- Orchestration - [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine)
- Job configuration and deployment - Helm chart is used to configure and deploy the
  [Kubernetes Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).
  This deployment encapsulates the serving of the DeepSeek R1 671B model using SGLang.
  The chart generates the deployment's manifest, which adheres to best practices for using RDMA Over Ethernet (RoCE) with Google Kubernetes Engine (GKE).

## Prerequisites

To prepare the required environment, see
[GKE environment setup guide](../../../../docs/configuring-environment-gke-a4-high.md).

Before running this recipe, ensure your environment is configured as follows:

- A GKE cluster with the following setup:
  - An A4 node pool (1 node, 8 B200 GPUs)
  - Topology-aware scheduling enabled
- An Artifact Registry repository to store the Docker image.
- A Google Cloud Storage (GCS) bucket to store results.
  *Important: This bucket must be in the same region as the GKE cluster*.
- A client workstation with the following pre-installed:
  - Google Cloud SDK
  - Helm
  - kubectl
  - git
- To access the [DeepSeek R1 671B model](https://huggingface.co/deepseek-ai/DeepSeek-R1) through Hugging Face, you'll need a Hugging Face token. Follow these steps to generate a new token if you don't have one already:
  - Create a [Hugging Face account](https://huggingface.co/), if you don't already have one.
  - Click Your **Profile > Settings > Access Tokens**.
  - Select **New Token**.
  - Specify a Name and a Role of at least `Read`.
  - Select **Generate a token**.
  - Copy the generated token to your clipboard.

## Run the recipe

### Using the command.sh script

The `command.sh` script simplifies the entire deployment process by providing automation for deployment, testing, and cleanup.

#### Script options

```bash
Usage: ./command.sh [options]

Options:
  -p, --project-id PROJECT_ID    Set the project ID
  -r, --region REGION            Set the build region
  -c, --cluster-region REGION    Set the cluster region
  -n, --cluster-name NAME        Set the cluster name
  -b, --gcs-bucket BUCKET        Set the GCS bucket name (without gs:// prefix)
  -a, --artifact-registry REGISTRY Set the Artifact Registry name
  -t, --hf-token TOKEN           Set the Hugging Face API token
  -h, --help                     Display this help message and exit
  --build-only                   Only build the Docker image
  --deploy-only                  Only deploy the model service
  --test-only                    Only test the deployed service
  --cleanup                      Clean up resources
```

#### Example 1: Complete process (build, deploy, and test)

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

#### Example 2: Build Docker image only

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

#### Example 3: Deploy model service only (assuming Docker image is already built)

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

#### Example 4: Test deployed service only

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

#### Example 5: Clean up resources

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

### Manual deployment steps

If you want to understand the detailed steps behind the `command.sh` script, here's the manual deployment process:

### Configure environment settings

From your client, complete the following steps:

1. Set the environment variables to match your environment:

   ```bash
   export PROJECT_ID=<PROJECT_ID>
   export REGION=<REGION>
   export CLUSTER_REGION=<CLUSTER_REGION>
   export CLUSTER_NAME=<CLUSTER_NAME>
   export GCS_BUCKET=<GCS_BUCKET>
   export ARTIFACT_REGISTRY=<ARTIFACT_REGISTRY>
   export SGLANG_IMAGE=sglang
   export SGLANG_VERSION=v0.4.2.post1-cu125
   export HF_TOKEN=<YOUR_HUGGINGFACE_TOKEN>
   ```

   Replace the following values:

   - `<PROJECT_ID>`: your Google Cloud project ID
   - `<REGION>`: the region where you want to run Cloud Build
   - `<CLUSTER_REGION>`: the region where your cluster is located
   - `<CLUSTER_NAME>`: the name of your GKE cluster
   - `<GCS_BUCKET>`: the name of your Cloud Storage bucket. Do not include the `gs://` prefix
   - `<ARTIFACT_REGISTRY>`: the full name of your Artifact
     Registry in the following format: *LOCATION*-docker.pkg.dev/*PROJECT_ID*/*REPOSITORY*
   - `<SGLANG_IMAGE>`: the name of the SGLang image
   - `<SGLANG_VERSION>`: the version of the SGLang image
   - `<YOUR_HUGGINGFACE_TOKEN>`: your Hugging Face token to access the model

2. Set the default project:

   ```bash
   gcloud config set project $PROJECT_ID
   ```

### Get the recipe

From your client, clone the `gpu-recipes` repository and set a reference to the recipe folder.

```bash
git clone -b a4-early-access https://github.com/yangwhale/gpu-recipes.git
cd gpu-recipes
export REPO_ROOT=`git rev-parse --show-toplevel`
export RECIPE_ROOT=$REPO_ROOT/inference/a4high/deepseek-r1-671b/sglang-serving-gke
```

### Get cluster credentials

From your client, get the credentials for your cluster.

```bash
gcloud container clusters get-credentials $CLUSTER_NAME --region $CLUSTER_REGION
```

### Build and push a docker container image to Artifact Registry

To build the container, complete the following steps from your client:

1. Use Cloud Build to build and push the container image.

    ```bash
    cd $REPO_ROOT/src/docker/sglang
    gcloud builds submit --region=${REGION} \
        --config cloudbuild.yml \
        --substitutions _ARTIFACT_REGISTRY=$ARTIFACT_REGISTRY,_SGLANG_IMAGE=$SGLANG_IMAGE,_SGLANG_VERSION=$SGLANG_VERSION \
        --timeout "2h" \
        --machine-type=e2-highcpu-32 \
        --disk-size=1000
    ```

## Single A4 Node Serving of DeepSeek R1 671B

The recipe serves DeepSeek R1 671B model using SGLang on a single A4 node.

To start the serving, the recipe launches SGLang server that does the following steps:
1. Downloads the DeepSeek R1 671B model checkpoints from [Hugging Face](https://huggingface.co/deepseek-ai/DeepSeek-R1).
2. Loads the model checkpoints and applies SGLang optimizations.
3. Serves the model via an API endpoint.

The recipe uses the Helm chart to run the above steps.

1. Create Kubernetes Secret with a Hugging Face token to enable the deployment to download the model checkpoints.

    ```bash
    kubectl create secret generic hf-secret \
      --from-literal=hf_api_token=${HF_TOKEN} \
      --dry-run=client -o yaml | kubectl apply -f -
    ```

2. Install the Helm chart to deploy the model service.

    ```bash
    cd $RECIPE_ROOT
    helm install -f values.yaml \
      --set volumes.gcsMounts[0].bucketName=${GCS_BUCKET} \
      --set clusterName=$CLUSTER_NAME \
      --set job.image.repository=${ARTIFACT_REGISTRY}/${SGLANG_IMAGE} \
      --set job.image.tag=${SGLANG_VERSION} \
      $USER-serving-deepseek-r1-model \
      $REPO_ROOT/src/helm-charts/a4high/sglang-inference
    ```

3. To view the logs for the deployment, run
    ```bash
    kubectl logs -f deployment/$USER-serving-deepseek-r1-model
    ```

4. Verify if the deployment has started by running
    ```bash
    kubectl get deployment/$USER-serving-deepseek-r1-model
    ```

## Testing the deployment

### Setting up port forwarding

To make API requests to the service, you can port forward the service to your local machine.

```bash
kubectl port-forward svc/$USER-serving-deepseek-r1-model-svc 30000:30000
```

### Making API requests

You can test the deployment by sending requests using curl:

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

### Using the streaming chat script

You can also use the provided streaming chat script for a more interactive experience:

```bash
./stream_chat.sh "Tell me a short joke"
```

## Performance benchmarking

To benchmark the model's performance using SGLang's benchmarking tool:

```bash
# Get the Pod name
POD_NAME=$(kubectl get pods -l app=$USER-serving-deepseek-r1-model -o jsonpath='{.items[0].metadata.name}')

# Run the benchmark
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

## Cleanup

To clean up the resources created by this recipe, complete the following steps:

1. Uninstall the Helm chart.

    ```bash
    helm uninstall $USER-serving-deepseek-r1-model
    ```

2. Delete the Kubernetes Secret.

    ```bash
    kubectl delete secret hf-secret
    ```

## Troubleshooting

### If the model deployment takes too long

Check if the GPU drivers and CUDA version are compatible:

```bash
POD_NAME=$(kubectl get pods -l app=$USER-serving-deepseek-r1-model -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD_NAME -- nvidia-smi
```

### If you cannot access the API

Check if the service is running correctly and verify port forwarding:

```bash
kubectl get svc/$USER-serving-deepseek-r1-model-svc
kubectl port-forward svc/$USER-serving-deepseek-r1-model-svc 30000:30000
```

## Running the recipe on clusters with non-default configuration

For clusters that use non-default network configurations, you need to provide the network configuration when installing the Helm chart:

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
  $REPO_ROOT/src/helm-charts/a4high/sglang-inference
```

## Summary

This guide demonstrates how to deploy and serve the DeepSeek R1 671B model using SGLang on A4 GKE, covering deployment options, testing methods, and performance evaluation. The included `command.sh` script significantly simplifies the deployment process, making it easier to run large language model inference services on Google Cloud.
