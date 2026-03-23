#!/bin/bash

# APK信息更新脚本
# 用法: ./update_apk_info.sh [APK文件名]

# 检查是否提供了APK文件名参数
if [ $# -eq 0 ]; then
    echo "用法: $0 <APK文件名>"
    echo "例如: $0 1d8e610218e7b3af52c6e928685a19bc.apk"
    exit 1
fi

APK_FILE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APK_PATH="$SCRIPT_DIR/$APK_FILE"
YAML_PATH="$SCRIPT_DIR/update.yaml"

# 检查APK文件是否存在
if [ ! -f "$APK_PATH" ]; then
    echo "[ERROR] APK文件不存在 - $APK_PATH"
    exit 1
fi

# 检查YAML文件是否存在
if [ ! -f "$YAML_PATH" ]; then
    echo "[ERROR] YAML文件不存在 - $YAML_PATH"
    exit 1
fi

echo "[INFO] 正在更新APK信息..."
echo "APK文件: $APK_FILE"
echo "YAML文件: update.yaml"
echo ""

# 运行Python脚本（默认使用 python，可通过 PYTHON_BIN 覆盖）
PYTHON_BIN="${PYTHON_BIN:-python}"

"$PYTHON_BIN" "$SCRIPT_DIR/generate_file_info.py" "$APK_PATH" --yaml "$YAML_PATH"

if [ $? -eq 0 ]; then
    echo ""
    echo "[OK] APK信息更新完成！"
    echo "[TIP] 记得同步更新version和version_code字段"
else
    echo ""
    echo "[ERROR] APK信息更新失败！"
    exit 1
fi 