# 1. Connect to cluster
export PROJECT=supercomputer-testing
export REGION=us-central1
export ZONE=us-central1-b
export CLUSTER_NAME=map-a4-gke

gcloud config set project ${PROJECT}
gcloud config set compute/zone ${ZONE}
gcloud container clusters get-credentials $CLUSTER_NAME --region $REGION

# 2. Pick a recipe
export RECIPE_ROOT=/google/src/cloud/tonyjohnchen/a4_recipe/google3/experimental/users/tonyjohnchen/A4
# export RECIPE_NAME=llama3_8b_bf16
export RECIPE_NAME=llama3_8b_fp8
# export RECIPE_NAME=mixtral8x7b_bf16
# export RECIPE_NAME=mixtral8x7b_fp8
cp $RECIPE_ROOT/recipe/$RECIPE_NAME.yaml selected-configuration.yaml


# 3. Start a workload
RECIPE_NAME_UPDATE=${RECIPE_NAME//_/-}
echo $RECIPE_NAME_UPDATE
export WORKLOAD_NAME=$USER-$RECIPE_NAME_UPDATE-16gpu
echo $WORKLOAD_NAME
cd $RECIPE_ROOT
helm install $WORKLOAD_NAME helm-context/

# 4. Check the workload logs
kubectl get pods | grep $WORKLOAD_NAME

kubectl logs tonyjohnchen-llama3-8b-fp8-16gpu-0-9gb7g
kubectl logs tonyjohnchen-llama3-8b-fp8-16gpu-1-5mjm2 

# 5. Uninstall the workload
helm uninstall $WORKLOAD_NAME