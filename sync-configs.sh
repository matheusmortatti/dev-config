#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.config-backups"

CONFIG_MAPPINGS=(
    "claude-md:$HOME/.claude/claude.md:$SCRIPT_DIR/claude/claude.md:file"
    "claude-agents:$HOME/.claude/agents:$SCRIPT_DIR/claude/agents:dir"
    "claude-commands:$HOME/.claude/commands:$SCRIPT_DIR/claude/commands:dir"
    "tmux:$HOME/.tmux.conf:$SCRIPT_DIR/tmux.conf:file"
    "ghostty:$HOME/Library/Application Support/com.mitchellh.ghostty/config:$SCRIPT_DIR/ghostty-config:file"
)

usage() {
    echo "Usage: $0 {pull|push}"
    echo ""
    echo "  pull  - Copy configs from system to repository"
    echo "  push  - Copy configs from repository to system"
    echo ""
    echo "Configurations managed:"
    echo "  - Claude config (claude.md, agents/, commands/ from ~/.claude/)"
    echo "  - Tmux config (~/.tmux.conf)"
    echo "  - Ghostty config (~/Library/Application Support/com.mitchellh.ghostty/config)"
}

create_backup() {
    local target="$1"
    local backup_name="$2"
    
    if [[ -e "$target" ]]; then
        mkdir -p "$BACKUP_DIR"
        local timestamp=$(date +"%Y%m%d_%H%M%S")
        local backup_path="$BACKUP_DIR/${backup_name}_${timestamp}"
        
        echo "  Creating backup: $backup_path"
        if [[ -d "$target" ]]; then
            cp -r "$target" "$backup_path"
        else
            cp "$target" "$backup_path"
        fi
    fi
}

sync_config() {
    local name="$1"
    local system_path="$2"
    local repo_path="$3"
    local type="$4"
    local mode="$5"
    
    echo "Syncing $name config..."
    
    if [[ "$mode" == "pull" ]]; then
        if [[ ! -e "$system_path" ]]; then
            echo "  Warning: $system_path does not exist, skipping"
            return
        fi
        
        if [[ -e "$repo_path" ]]; then
            create_backup "$repo_path" "${name}_repo"
        fi
        
        if [[ "$type" == "dir" ]]; then
            echo "  Copying directory: $system_path -> $repo_path"
            rm -rf "$repo_path"
            cp -r "$system_path" "$repo_path"
        else
            echo "  Copying file: $system_path -> $repo_path"
            mkdir -p "$(dirname "$repo_path")"
            cp "$system_path" "$repo_path"
        fi
        
    elif [[ "$mode" == "push" ]]; then
        if [[ ! -e "$repo_path" ]]; then
            echo "  Warning: $repo_path does not exist, skipping"
            return
        fi
        
        if [[ -e "$system_path" ]]; then
            create_backup "$system_path" "${name}_system"
        fi
        
        if [[ "$type" == "dir" ]]; then
            echo "  Copying directory: $repo_path -> $system_path"
            rm -rf "$system_path"
            mkdir -p "$(dirname "$system_path")"
            cp -r "$repo_path" "$system_path"
        else
            echo "  Copying file: $repo_path -> $system_path"
            mkdir -p "$(dirname "$system_path")"
            cp "$repo_path" "$system_path"
        fi
    fi
    
    echo "  ✓ $name config synced"
    echo ""
}

main() {
    if [[ $# -ne 1 ]]; then
        usage
        exit 1
    fi
    
    local mode="$1"
    
    if [[ "$mode" != "pull" && "$mode" != "push" ]]; then
        echo "Error: Invalid mode '$mode'"
        usage
        exit 1
    fi
    
    echo "=== Config Sync Tool ==="
    echo "Mode: $mode"
    echo "Repository: $SCRIPT_DIR"
    echo ""
    
    for mapping in "${CONFIG_MAPPINGS[@]}"; do
        IFS=':' read -r name system_path repo_path type <<< "$mapping"
        sync_config "$name" "$system_path" "$repo_path" "$type" "$mode"
    done
    
    echo "All configurations synced successfully!"
    
    if [[ -d "$BACKUP_DIR" ]]; then
        echo "Backups created in: $BACKUP_DIR"
    fi
}

main "$@"