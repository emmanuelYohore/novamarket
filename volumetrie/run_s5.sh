#!/usr/bin/env bash
# Rejoue la S5 depuis novamarket/ : bash volumetrie/run_s5.sh <essai> [--secours]
# Exemple : bash volumetrie/run_s5.sh g01-distant02          (streaming réel, réseau requis)
#           bash volumetrie/run_s5.sh g01-secours02 --secours (hors ligne)
set -euo pipefail
RUN=${1:?usage : bash volumetrie/run_s5.sh ESSAI [--secours]}; MODE=${2:-}
export JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"
export SPARK_LOCAL_IP=127.0.0.1 PYSPARK_PYTHON="$(command -v python)" PYSPARK_SUBMIT_ARGS="--driver-memory 1g pyspark-shell"
python volumetrie/spark/verifier.py
HF_HUB_DISABLE_XET=1 python volumetrie/streaming/extraire_trajets.py --run "$RUN" $MODE
python volumetrie/streaming/controler_extraction.py --run "$RUN"
python volumetrie/spark/pipeline_trajets.py --run "$RUN" --sortie "volumetrie/sorties/$RUN-essai1"
python volumetrie/hub/preparer_publication.py --version 1 --parquet "volumetrie/sorties/$RUN-essai1"
echo "Publication : hf auth login, puis python volumetrie/hub/publier.py --repo COMPTE/novamarket-s5-exercice --parquet volumetrie/sorties/$RUN-essai1"
