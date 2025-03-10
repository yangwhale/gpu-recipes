#!/bin/bash

# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e  # Exit immediately if a command exits with a non-zero status
set -o pipefail  # Pipeline fails on the first command with a non-zero status

# Display help information
show_help() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -p, --project-id PROJECT_ID    Set the project ID"
  echo "  -r, --region REGION            Set the build region"
  echo "  -c, --cluster-region REGION    Set the cluster region"
  echo "  -n, --cluster-name NAME        Set the cluster name"
  echo "  -b, --gcs-bucket BUCKET        Set the GCS bucket name (without gs:// prefix)"
  echo "  -a, --artifact-registry REGISTRY Set the Artifact Registry name"
  echo "  -t, --hf-token TOKEN           Set the Hugging Face API token"
  echo "  -N, --networks NETWORKS        Set custom network configuration (comma-separated list)"
  echo "  -h, --help                     Display this help and exit"
  echo "  --build-only                   Only build the Docker image"
  echo "  --deploy-only                  Only deploy the model service"
  echo "  --test-only                    Only test the deployed service"
  echo "  --cleanup                      Clean up resources"
  echo
}

# Default values
SGLANG_IMAGE="sglang"
SGLANG_VERSION="v0.4.2.post1-cu125"
BUILD_ONLY=false
DEPLOY_ONLY=false
TEST_ONLY=false
CLEANUP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    -r|--region)
      REGION="$2"
      shift 2
      ;;
    -c|--cluster-region)
      CLUSTER_REGION="$2"
      shift 2
      ;;
    -n|--cluster-name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    -b|--gcs-bucket)
      GCS_BUCKET="$2"
      shift 2
      ;;
    -a|--artifact-registry)
      ARTIFACT_REGISTRY="$2"
      shift 2
      ;;
    -t|--hf-token)
      HF_TOKEN="$2"
      shift 2
      ;;
    -N|--networks)
      CUSTOM_NETWORKS="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    --build-only)
      BUILD_ONLY=true
      shift
      ;;
    --deploy-only)
      DEPLOY_ONLY=true
      shift
      ;;
    --test-only)
      TEST_ONLY=true
      shift
      ;;
    --cleanup)
      CLEANUP=true
      shift
      ;;
    *)
      echo "Error: Unknown option $1" >&2
      show_help
      exit 1
      ;;
  esac
done

# Validate required parameters
if [[ -z "$PROJECT_ID" || -z "$REGION" || -z "$CLUSTER_REGION" || -z "$CLUSTER_NAME" || -z "$GCS_BUCKET" || -z "$ARTIFACT_REGISTRY" ]]; then
  echo "Error: Missing required parameters" >&2
  show_help
  exit 1
fi

# If deployment is requested but HF_TOKEN is not provided, prompt for input
if [[ "$DEPLOY_ONLY" == "true" && -z "$HF_TOKEN" ]]; then
  echo "Deployment requires a Hugging Face token. Please enter your HF_TOKEN:"
  read -s HF_TOKEN
  if [[ -z "$HF_TOKEN" ]]; then
    echo "Error: HF_TOKEN not provided" >&2
    exit 1
  fi
fi

# Output current configuration
echo "Configuration:"
echo "PROJECT_ID: $PROJECT_ID"
echo "REGION: $REGION"
echo "CLUSTER_REGION: $CLUSTER_REGION"
echo "CLUSTER_NAME: $CLUSTER_NAME"
echo "GCS_BUCKET: $GCS_BUCKET"
echo "ARTIFACT_REGISTRY: $ARTIFACT_REGISTRY"
echo "SGLANG_IMAGE: $SGLANG_IMAGE"
echo "SGLANG_VERSION: $SGLANG_VERSION"
echo "HF_TOKEN: ${HF_TOKEN:0:3}...${HF_TOKEN: -3}" # Only display the first 3 and last 3 characters of the token

# Set the default project
gcloud config set project $PROJECT_ID

# Get the repository root path
if ! command -v git &> /dev/null; then
  echo "Error: git is not installed" >&2
  exit 1
fi

# Determine the repository root directory
# If not in a git repository, try using the relative path
if git rev-parse --git-dir &> /dev/null; then
  REPO_ROOT=$(git rev-parse --show-toplevel)
else
  # Try to infer from the current script path
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
  # Assuming the script is located in inference/a4/deepseek-r1-671b/sglang-serving-gke/
  REPO_ROOT="${SCRIPT_DIR}/../../../.."
fi

if [[ ! -d "$REPO_ROOT" ]]; then
  echo "Error: Unable to determine repository root directory" >&2
  exit 1
fi

echo "Repository root directory: $REPO_ROOT"

# Set the recipe root directory
RECIPE_ROOT="$REPO_ROOT/inference/a4/deepseek-r1-671b/sglang-serving-gke"
echo "Recipe root directory: $RECIPE_ROOT"

# Get cluster credentials
echo "Getting cluster credentials..."
gcloud container clusters get-credentials $CLUSTER_NAME --region $CLUSTER_REGION

# If only cleaning up resources
if [[ "$CLEANUP" == "true" ]]; then
  echo "Cleaning up resources..."
  helm uninstall $USER-serving-deepseek-r1-model
  kubectl delete secret hf-secret
  echo "Cleanup completed"
  exit 0
fi

# Build and push Docker image to Artifact Registry
if [[ "$DEPLOY_ONLY" == "false" && "$TEST_ONLY" == "false" ]]; then
  echo "Building and pushing Docker image to Artifact Registry..."
  cd $REPO_ROOT/src/docker/sglang
  echo "Starting build..."
  BUILD_ID=$(gcloud builds submit --region=${REGION} \
      --config cloudbuild.yml \
      --substitutions _ARTIFACT_REGISTRY=$ARTIFACT_REGISTRY,_SGLANG_IMAGE=$SGLANG_IMAGE,_SGLANG_VERSION=$SGLANG_VERSION \
      --timeout "2h" \
      --machine-type=e2-highcpu-32 \
      --disk-size=1000 \
      --quiet \
      --async | grep "ID:" | awk '{print $2}')
  
  echo "Build ID: $BUILD_ID"
  echo "Monitoring build progress..."
  gcloud beta builds log $BUILD_ID --region=$REGION --stream
  
  if [[ "$BUILD_ONLY" == "true" ]]; then
    echo "Build-only mode, completed"
    exit 0
  fi
fi

# If only testing, skip to the test section
if [[ "$TEST_ONLY" == "true" ]]; then
  echo "Test-only mode..."
  goto_test=true
else
  goto_test=false
fi

# Deploy DeepSeek R1 671B model
if [[ "$goto_test" == "false" ]]; then
  # Create Kubernetes Secret
  echo "Creating Kubernetes Secret..."
  kubectl create secret generic hf-secret \
    --from-literal=hf_api_token=${HF_TOKEN} \
    --dry-run=client -o yaml | kubectl apply -f -
  
  # Install Helm chart
  echo "Installing Helm chart..."
  cd $RECIPE_ROOT
  
  # 检查是否指定了自定义网络配置
  if [[ -z "$CUSTOM_NETWORKS" ]]; then
    echo "使用默认网络配置安装..."
    helm install -f values.yaml \
      --set volumes.gcsMounts[0].bucketName=${GCS_BUCKET} \
      --set clusterName=$CLUSTER_NAME \
      --set job.image.repository=${ARTIFACT_REGISTRY}/${SGLANG_IMAGE} \
      --set job.image.tag=${SGLANG_VERSION} \
      $USER-serving-deepseek-r1-model \
      $REPO_ROOT/src/helm-charts/a4/sglang-inference
  else
    echo "使用自定义网络配置安装..."
    # 假设CUSTOM_NETWORKS格式为"default,gke-a4-high-sub-1,rdma-0,rdma-1,..."
    IFS=',' read -r -a NETWORK_ARRAY <<< "$CUSTOM_NETWORKS"
    
    NETWORK_ARGS=""
    for i in "${!NETWORK_ARRAY[@]}"; do
      NETWORK_ARGS="$NETWORK_ARGS --set network.subnetworks[$i]=${NETWORK_ARRAY[$i]}"
    done
    
    helm install -f values.yaml \
      --set volumes.gcsMounts[0].bucketName=${GCS_BUCKET} \
      --set clusterName=$CLUSTER_NAME \
      --set job.image.repository=${ARTIFACT_REGISTRY}/${SGLANG_IMAGE} \
      --set job.image.tag=${SGLANG_VERSION} \
      $NETWORK_ARGS \
      $USER-serving-deepseek-r1-model \
      $REPO_ROOT/src/helm-charts/a4/sglang-inference
  fi
  
  echo "Waiting for deployment to start..."
  sleep 10
  
  echo "Checking deployment status..."
  kubectl get deployment/$USER-serving-deepseek-r1-model-serving
  
  echo "Viewing logs..."
  kubectl logs -f deployment/$USER-serving-deepseek-r1-model-serving &
  LOG_PID=$!
  
  # Wait for service to be ready
  echo "Waiting for service to be ready..."
  READY=false
  TIMEOUT=600  # Timeout in seconds
  START_TIME=$(date +%s)
  
  while [[ "$READY" == "false" ]]; do
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
    
    if [[ $ELAPSED_TIME -gt $TIMEOUT ]]; then
      echo "Timeout waiting for service to be ready"
      kill $LOG_PID
      exit 1
    fi
    
    # Check if deployment is ready
    DEPLOYMENT_STATUS=$(kubectl get deployment/$USER-serving-deepseek-r1-model-serving -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$DEPLOYMENT_STATUS" != "0" ]]; then
      echo "Service is ready!"
      READY=true
    else
      echo "Waiting for service to be ready... Elapsed time: $ELAPSED_TIME seconds"
      sleep 10
    fi
  done
  
  # Terminate the log viewing process
  kill $LOG_PID 2>/dev/null || true
  wait $LOG_PID 2>/dev/null || true
fi

# Test the deployment
echo "Setting up port forwarding..."
kubectl port-forward svc/$USER-serving-deepseek-r1-model-svc 30000:30000 &
PORT_FORWARD_PID=$!

# Wait for port forwarding to be ready
echo "Waiting for port forwarding to be ready..."
sleep 5

# Send test request
echo "Sending test request..."
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

echo "Testing with streaming chat script..."
$RECIPE_ROOT/stream_chat.sh "Tell me a short joke"

# Prompt user if they want to run benchmarks
echo "Do you want to run benchmarks? [y/N]"
read -r RUN_BENCHMARK
if [[ "$RUN_BENCHMARK" =~ ^[Yy]$ ]]; then
  # Get pod name
  POD_NAME=$(kubectl get pods -l app=$USER-serving-deepseek-r1-model -o jsonpath='{.items[0].metadata.name}')
  echo "Running benchmarks on Pod: $POD_NAME"
  kubectl exec -it $POD_NAME -- python3 -m sglang.bench_serving --backend sglang --dataset-name random --random-range-ratio 1 --num-prompt 1100 --random-input 1000 --random-output 1000 --host 0.0.0.0 --port 30000 --output-file /gcs/benchmark_logs/sglang/ds_1000_1000_1100_output.jsonl
fi

# Prompt user if they want to end port forwarding
echo "Do you want to end port forwarding? [y/N]"
read -r END_PORT_FORWARD
if [[ "$END_PORT_FORWARD" =~ ^[Yy]$ ]]; then
  echo "Ending port forwarding..."
  kill $PORT_FORWARD_PID
fi

# Prompt user if they want to clean up resources
echo "Do you want to clean up resources? [y/N]"
read -r DO_CLEANUP
if [[ "$DO_CLEANUP" =~ ^[Yy]$ ]]; then
  echo "Cleaning up resources..."
  helm uninstall $USER-serving-deepseek-r1-model
  kubectl delete secret hf-secret
  echo "Cleanup completed"
fi

echo "Script execution completed"