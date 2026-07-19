#!/bin/bash

# DO note that your account will need a billing accout in order to able compute api

PROJECT_ID='__your_project_id__'
ACCOUNT='__your_user_account__'

# 1. Authenticate the core gcloud CLI (Fixes the error)
gcloud auth login --no-launch-browser

# 2. Authenticate the Application Default Credentials (For OpenTofu/Terraform)
gcloud auth application-default login --no-launch-browser --quiet

# 3. Target the correct project configuration
gcloud config set project ${PROJECT_ID}
gcloud config set account ${ACCOUNT}

# 4. This will now succeed because step 1 gave the CLI valid tokens
gcloud services enable compute.googleapis.com
