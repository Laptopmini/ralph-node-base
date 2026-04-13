# Configuration
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# ANSI Color Codes
RED='\033[1;31m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date +%Y-%m-%d\ %H:%M:%S)
    local caller_script=$(basename "${BASH_SOURCE[1]}")
    
    case $level in
        ERROR) echo -e "${RED}[$timestamp] [$caller_script] [$level]${NC} ${message}" ;;
        WARN)  echo -e "${YELLOW}[$timestamp] [$caller_script] [$level]${NC} ${message}" ;;
        INFO)  echo -e "${BLUE}[$timestamp] [$caller_script] [$level]${NC} ${message}" ;;
        SUCCESS) echo -e "${GREEN}[$timestamp] [$caller_script] [$level]${NC} ${message}" ;;
    esac
}