#! /bin/bash

nvprof --query-events
nvprof --query-metrics

nvprof $1

nvprof --print-api-trace $1
nvprof --print-gpu-trace $1

nvprof --events warps_launched --metrics ipc $1

nvprof --aggregate-mode off --events local_load --print-gpu-trace $1

nvprof --log-file profile-data.txt $1
nvprof -o profile-data.nvprof $1
