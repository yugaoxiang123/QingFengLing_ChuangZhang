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
    echo "❌ 错误: APK文件不存在 - $APK_PATH"
    exit 1
fi

# 检查YAML文件是否存在
if [ ! -f "$YAML_PATH" ]; then
    echo "❌ 错误: YAML文件不存在 - $YAML_PATH"
    exit 1
fi

echo "🔄 正在更新APK信息..."
echo "APK文件: $APK_FILE"
echo "YAML文件: update.yaml"
echo ""

# Resolve a usable Python command across Linux/macOS/Git-Bash on Windows.
PYTHON_CMD=""
if command -v python3 >/dev/null 2>&1 && python3 -c "import sys; sys.exit(0 if sys.version_info.major >= 3 else 1)" >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1 && python -c "import sys; sys.exit(0 if sys.version_info.major >= 3 else 1)" >/dev/null 2>&1; then
    PYTHON_CMD="python"
elif command -v py >/dev/null 2>&1 && py -3 -c "import sys; sys.exit(0 if sys.version_info.major >= 3 else 1)" >/dev/null 2>&1; then
    PYTHON_CMD="py -3"
else
    echo "❌ 错误: 未找到可用的Python解释器（python3/python/py）"
    exit 1
fi

# 运行Python脚本
PYTHONIOENCODING=utf-8 $PYTHON_CMD "$SCRIPT_DIR/generate_file_info.py" "$APK_PATH" --yaml "$YAML_PATH"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ APK信息更新完成！"
    echo "💡 提示: 记得同步更新version和version_code字段"
else
    echo ""
    echo "❌ APK信息更新失败！"
    exit 1
fi 