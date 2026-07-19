#!/bin/bash

# 1
## 初始化：下載 google provider（第一次或改過 provider 才需要）
## Initialize: Download the Google provider (only needed for the first time or after changing providers)
tofu init

# 2 
## 驗證語法正確
## Validate syntax correctness
tofu validate

# 3. 
## 預覽即將建立的資源，不會動到真實環境
## Preview upcoming resource changes without affecting the live environment
tofu plan

# 4
## 實際部署相關環境
## Deploy the environment
# tofu apply -auto-approve

# 5
## 清理環境
## Clean up the environment
# tofu destroy -auto-approve
