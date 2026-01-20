#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_DIR="docs/docs/public/server/self-host"
MAX_WAIT_TIME=300  # 5 minutes
CHECK_INTERVAL=5   # Check every 5 seconds

echo -e "${YELLOW}Testing Tuist Server Docker Compose Configuration${NC}"
echo "=================================================="
echo ""

# Check if docker compose is available
if ! command -v docker &> /dev/null && ! command -v podman &> /dev/null; then
    echo -e "${RED}Error: Neither docker nor podman is installed${NC}"
    exit 1
fi

# Determine which container tool to use
if command -v docker &> /dev/null; then
    DOCKER_CMD="docker compose"
elif command -v podman &> /dev/null; then
    DOCKER_CMD="podman compose"
fi

echo -e "${GREEN}✓${NC} Using: $DOCKER_CMD"
echo ""

# Change to project root
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up...${NC}"
    cd "$PROJECT_ROOT/$COMPOSE_DIR"
    $DOCKER_CMD down -v --remove-orphans 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Cleanup complete"
}

# Set trap to cleanup on exit
trap cleanup EXIT INT TERM

# Change to docker-compose directory for validation
cd "$COMPOSE_DIR"

# Validate docker-compose file
echo "Validating docker-compose file..."
if $DOCKER_CMD config > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Docker Compose file is valid"
else
    echo -e "${RED}✗${NC} Docker Compose file is invalid"
    $DOCKER_CMD config
    exit 1
fi
echo ""

# Create a minimal .env file for testing (if it doesn't exist)
ENV_FILE=".env"
if [ ! -f "$ENV_FILE" ]; then
    echo "Creating minimal .env file for testing..."
    cat > "$ENV_FILE" << 'ENVEOF'
# Minimal configuration for CI testing
TUIST_LICENSE=test-license-for-ci
TUIST_GITHUB_APP_CLIENT_ID=test-client-id
TUIST_GITHUB_APP_CLIENT_SECRET=test-client-secret
ENVEOF
    echo -e "${GREEN}✓${NC} Created test .env file"
    echo ""
fi

# Start services
echo "Starting services..."
if $DOCKER_CMD up -d; then
    echo -e "${GREEN}✓${NC} Services started"
else
    echo -e "${RED}✗${NC} Failed to start services"
    echo ""
    echo "Service status:"
    $DOCKER_CMD ps -a
    echo ""
    echo "Recent logs:"
    $DOCKER_CMD logs --tail=100
    exit 1
fi
echo ""

# Function to check service health
check_service_health() {
    local service=$1
    local status=$($DOCKER_CMD ps --format json "$service" 2>/dev/null | grep -o '"Health":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$status" ]; then
        # If no health check is defined, check if the service is running
        local state=$($DOCKER_CMD ps --format json "$service" 2>/dev/null | grep -o '"State":"[^"]*"' | cut -d'"' -f4)
        if [ "$state" = "running" ]; then
            echo "running"
        else
            echo "unhealthy"
        fi
    else
        echo "$status"
    fi
}

# Wait for all services to be healthy
echo "Waiting for services to be healthy..."
echo "This may take a few minutes..."
echo ""

SERVICES=("postgres" "clickhouse-keeper" "clickhouse" "minio" "redis")
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT_TIME ]; do
    ALL_HEALTHY=true
    
    for service in "${SERVICES[@]}"; do
        health=$(check_service_health "$service")
        
        if [ "$health" = "healthy" ] || [ "$health" = "running" ]; then
            echo -e "${GREEN}✓${NC} $service is healthy"
        else
            echo -e "${YELLOW}⏳${NC} $service is $health"
            ALL_HEALTHY=false
        fi
    done
    
    if [ "$ALL_HEALTHY" = true ]; then
        echo ""
        echo -e "${GREEN}✓${NC} All services are healthy!"
        break
    fi
    
    if [ $ELAPSED -ge $MAX_WAIT_TIME ]; then
        echo ""
        echo -e "${RED}✗${NC} Timeout waiting for services to be healthy"
        echo ""
        echo "Service status:"
        $DOCKER_CMD ps -a
        echo ""
        echo "Logs from unhealthy services:"
        for service in "${SERVICES[@]}"; do
            health=$(check_service_health "$service")
            if [ "$health" != "healthy" ] && [ "$health" != "running" ]; then
                echo ""
                echo "=== Logs for $service ==="
                $DOCKER_CMD logs --tail=50 "$service" 2>&1 || echo "No logs available"
            fi
        done
        exit 1
    fi
    
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
    echo ""
done

# Note: We don't test the Tuist server itself because it requires a valid license
# The purpose of this test is to ensure the docker-compose infrastructure is valid
echo ""
echo -e "${YELLOW}Note:${NC} Skipping Tuist server health check (requires valid license)"
echo "This test validates that all infrastructure services can start successfully."

echo ""
echo -e "${GREEN}=================================================="
echo "✓ All tests passed!"
echo "==================================================${NC}"
echo ""

# Show running services
echo "Running services:"
$DOCKER_CMD ps

exit 0
