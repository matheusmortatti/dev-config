# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal development configuration repository that manages:
- Claude Code configuration files (agents, commands, and claude.md)
- Terminal/editor configurations (tmux, ghostty)
- Synchronization tooling to keep configs in sync across systems

## Key Commands

### Configuration Sync
- `./sync-configs.sh pull` - Copy configs from system to repository
- `./sync-configs.sh push` - Copy configs from repository to system

### Managed Configurations
- **Claude configs**: `~/.claude/claude.md`, `~/.claude/agents/`, `~/.claude/commands/`
- **Tmux config**: `~/.tmux.conf`
- **Ghostty config**: `~/Library/Application Support/com.mitchellh.ghostty/config`

## Architecture

The sync script creates automatic backups in `~/.config-backups` before any changes and handles both files and directories. Each configuration has a defined mapping between system location and repository location.

The `claude/` directory contains:
- `claude.md` - Main Claude configuration
- `agents/` - Specialized Claude agents
- `commands/` - Custom Claude commands

## Important Notes

- Always test sync operations in safe environments first
- Backups are automatically created with timestamps
- The script handles both individual files and entire directories
- Configuration changes should be committed to track evolution over time