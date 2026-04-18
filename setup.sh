#!/bin/bash

echo "========================================="
echo " QR Attendance System - Setup Script"
echo "========================================="

echo "[1/3] Checking Node.js installation..."
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed! Please install Node.js from https://nodejs.org/"
    exit 1
fi
echo "✅ Node.js is installed."

echo "[2/3] Installing Backend Dependencies..."
cd backend || exit
npm install
echo "✅ Dependencies installed successfully."

echo "[3/3] Setup complete!"
echo "To start the application, make sure your MySQL database is running and the schema is loaded."
echo "Then, run: npm start"
echo "========================================="
