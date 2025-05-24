#!/bin/bash

# VPN Environment Manager - Entry Script
# Simplified environment management tool entry point
# Version: 1.0
# Date: 2025-05-24

# Set script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_MANAGER="$SCRIPT_DIR/lib/env_manager.sh"

# Check if environment manager exists
if [[ ! -f "$ENV_MANAGER" ]]; then
    echo "Error: Environment manager not found at $ENV_MANAGER"
    exit 1
fi

# Load environment manager
source "$ENV_MANAGER"

# Color definitions
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Show welcome message
show_welcome() {
    echo -e "${BLUE}=== AWS Client VPN Environment Manager ===${NC}"
    echo -e "${GREEN}Welcome to Multi-Environment VPN Management System${NC}"
    echo ""
}

# Show usage instructions
show_usage() {
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Available commands:"
    echo "  status          Show current environment status"
    echo "  switch <env>    Switch to specified environment (staging/production)"
    echo "  list            List all available environments"
    echo "  selector        Launch interactive environment selector"
    echo "  health [env]    Check environment health status"
    echo "  init            Initialize environment manager"
    echo ""
    echo "Examples:"
    echo "  $0 status                    # Show current environment"
    echo "  $0 switch staging           # Switch to staging environment"
    echo "  $0 switch production        # Switch to production environment"
    echo "  $0 selector                 # Launch interactive selector"
    echo ""
}

# Main program logic
main() {
    local command="${1:-status}"
    
    case "$command" in
        status|current)
            show_welcome
            env_current
            ;;
        switch)
            if [[ -z "$2" ]]; then
                echo "Error: Please specify environment to switch to"
                echo "Available environments: staging, production"
                exit 1
            fi
            show_welcome
            env_switch "$2"
            ;;
        list)
            show_welcome
            env_list
            ;;
        selector|menu)
            env_selector
            ;;
        health|check)
            show_welcome
            if [[ -n "$2" ]]; then
                if env_health_check "$2"; then
                    echo -e "$2: ${GREEN}🟢 Healthy${NC}"
                else
                    echo -e "$2: ${YELLOW}🟡 Warning${NC}"
                fi
            else
                echo "Checking all environment health status..."
                for env_dir in "$PROJECT_ROOT/configs"/*; do
                    if [[ -d "$env_dir" ]]; then
                        local env_name=$(basename "$env_dir")
                        local env_file="$env_dir/${env_name}.env"
                        if [[ -f "$env_file" ]]; then
                            if env_health_check "$env_name"; then
                                echo -e "${env_name}: ${GREEN}🟢 Healthy${NC}"
                            else
                                echo -e "${env_name}: ${YELLOW}🟡 Warning${NC}"
                            fi
                        fi
                    fi
                done
            fi
            ;;
        init)
            show_welcome
            env_init
            ;;
        help|--help|-h)
            show_welcome
            show_usage
            ;;
        *)
            show_welcome
            echo "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Execute main program
main "$@"
