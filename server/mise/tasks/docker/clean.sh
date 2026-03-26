#!/usr/bin/env bash
#MISE description="Clean the Docker images"

set -euo pipefail

# Remove all Docker images
docker_images=$(docker images -aq)
if [ -n "$docker_images" ]; then
    docker rmi -f $docker_images
else
    echo "No Docker images to remove."
fi

# Remove all Docker containers
docker_containers=$(docker ps -qa)
if [ -n "$docker_containers" ]; then
    docker rm -v -f $docker_containers
else
    echo "No Docker containers to remove."
fi
