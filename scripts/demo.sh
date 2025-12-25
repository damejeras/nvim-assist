#!/bin/bash

set -e

HOST="${NVIM_ASSIST_HOST:-127.0.0.1}"
PORT="${NVIM_ASSIST_PORT:-9999}"

echo "========================================="
echo "nvim-assist Demo Script"
echo "========================================="
echo ""
echo "Make sure you have:"
echo "1. Started Neovim"
echo "2. Loaded the nvim-assist plugin"
echo "3. Opened at least one buffer (server auto-starts)"
echo ""
echo "Press Enter to continue..."
read

echo ""
echo "Step 1: Testing connection (ping)..."
echo "----------------------------------------"
./scripts/ping.sh
echo ""

echo "Press Enter to continue..."
read

echo ""
echo "Step 2: Getting current buffer content..."
echo "----------------------------------------"
./scripts/get_buffer.sh
echo ""

echo "Press Enter to continue..."
read

echo ""
echo "Step 3: Applying example content to buffer..."
echo "----------------------------------------"
./scripts/apply_diff.sh full_replace scripts/example_content.txt
echo ""

echo "Press Enter to continue..."
read

echo ""
echo "Step 4: Getting updated buffer content..."
echo "----------------------------------------"
./scripts/get_buffer.sh
echo ""

echo "Press Enter to continue..."
read

echo ""
echo "Step 5: Applying text directly..."
echo "----------------------------------------"
./scripts/apply_diff.sh text "Hello from nvim-assist demo!"
echo ""

echo ""
echo "========================================="
echo "Demo completed!"
echo "Check your Neovim buffer to see the changes."
echo "========================================="
