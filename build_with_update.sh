#!/bin/bash

# 自动化Flutter APK构建和更新信息生成脚本
# 用法: ./build_with_update.sh
# 功能: 自动从pubspec.yaml读取版本信息，递增版本号，构建APK

set -e  # 遇到错误立即退出

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE_DIR="$SCRIPT_DIR/update_plugin"
PUBSPEC_FILE="$SCRIPT_DIR/pubspec.yaml"

echo "🚀 开始自动化构建流程..."

# 检查pubspec.yaml文件是否存在
if [ ! -f "$PUBSPEC_FILE" ]; then
    echo "❌ 错误: pubspec.yaml文件不存在！"
    exit 1
fi

# 1. 从pubspec.yaml读取当前版本号
echo "📖 读取当前版本信息..."
CURRENT_VERSION=$(grep '^version:' "$PUBSPEC_FILE" | sed 's/version: *//' | tr -d ' ')

if [ -z "$CURRENT_VERSION" ]; then
    echo "❌ 错误: 无法从pubspec.yaml中读取版本号！"
    exit 1
fi

echo "   当前版本: $CURRENT_VERSION"

# 2. 解析版本号并自动递增
# 处理两种格式: "1.2.3" 或 "1.2.3+4"
if [[ "$CURRENT_VERSION" == *"+"* ]]; then
    # 格式: 1.2.3+4
    VERSION_PART=$(echo "$CURRENT_VERSION" | cut -d'+' -f1)
    BUILD_PART=$(echo "$CURRENT_VERSION" | cut -d'+' -f2)
else
    # 格式: 1.2.3
    VERSION_PART="$CURRENT_VERSION"
    BUILD_PART=""
fi

# 解析主版本号 (major.minor.patch)
IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION_PART"

# 验证版本号格式
if ! [[ "$MAJOR" =~ ^[0-9]+$ ]] || ! [[ "$MINOR" =~ ^[0-9]+$ ]] || ! [[ "$PATCH" =~ ^[0-9]+$ ]]; then
    echo "❌ 错误: 版本号格式无效 ($VERSION_PART)，期望格式: major.minor.patch"
    exit 1
fi

# 递增patch版本
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"

# 计算新的versionCode (公式: major*10000 + minor*100 + patch)
NEW_VERSION_CODE=$((MAJOR * 10000 + MINOR * 100 + NEW_PATCH))

echo "📈 版本信息更新:"
echo "   $CURRENT_VERSION → $NEW_VERSION"
echo "   版本代码: $NEW_VERSION_CODE"
echo ""

# 3. 更新pubspec.yaml文件
echo "📝 更新pubspec.yaml文件..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC_FILE"
else
    # Linux
    sed -i "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC_FILE"
fi

echo "✅ 已更新pubspec.yaml版本: $NEW_VERSION"

# 4. 清理之前的构建
echo "🧹 清理之前的构建..."
flutter clean
flutter pub get

# 5. 构建APK
echo "🔨 构建APK..."
flutter build apk --release --build-name="$NEW_VERSION" --build-number="$NEW_VERSION_CODE"

# 检查构建是否成功
if [ ! -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    echo "❌ 错误: APK构建失败！"
    exit 1
fi

echo "✅ APK构建成功！"

# 6. 创建带版本号的APK文件名
APK_NAME="app_v${NEW_VERSION}.apk"
APK_PATH="$UPDATE_DIR/$APK_NAME"

# 确保update_plugin目录存在
if [ ! -d "$UPDATE_DIR" ]; then
    echo "❌ 错误: update_plugin目录不存在！"
    exit 1
fi

# 7. 复制APK到更新目录
echo "📦 复制APK到更新目录..."
cp "build/app/outputs/flutter-apk/app-release.apk" "$APK_PATH"
echo "   APK文件: $APK_NAME"

# 8. 生成文件信息
echo "📊 生成文件信息..."
cd "$UPDATE_DIR"

# 检查工具是否存在
if [ ! -f "update_apk_info.sh" ]; then
    echo "❌ 错误: update_apk_info.sh脚本不存在！"
    exit 1
fi

if [ ! -x "update_apk_info.sh" ]; then
    echo "🔧 添加执行权限..."
    chmod +x "update_apk_info.sh"
fi

# 运行文件信息生成工具
./update_apk_info.sh "$APK_NAME"

# 9. 更新版本信息到YAML文件
echo "📝 更新版本信息到YAML文件..."
cd "$SCRIPT_DIR"

YAML_FILE="update_plugin/update.yaml"

# 检查YAML文件是否存在
if [ ! -f "$YAML_FILE" ]; then
    echo "❌ 错误: update.yaml文件不存在！"
    exit 1
fi

# 使用sed命令更新版本信息（兼容macOS和Linux）
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/version: \".*\"/version: \"$NEW_VERSION\"/" "$YAML_FILE"
    sed -i '' "s/version_code: .*/version_code: $NEW_VERSION_CODE/" "$YAML_FILE"
    sed -i '' "s/build_date: \".*\"/build_date: \"$(date +%Y-%m-%d)\"/" "$YAML_FILE"
else
    # Linux
    sed -i "s/version: \".*\"/version: \"$NEW_VERSION\"/" "$YAML_FILE"
    sed -i "s/version_code: .*/version_code: $NEW_VERSION_CODE/" "$YAML_FILE"
    sed -i "s/build_date: \".*\"/build_date: \"$(date +%Y-%m-%d)\"/" "$YAML_FILE"
fi

echo "✅ 已更新版本信息: v$NEW_VERSION (code: $NEW_VERSION_CODE)"
echo "✅ 已更新构建日期: $(date +%Y-%m-%d)"

# 9.1. 计算APK的MD5并更新download_url
echo "🔐 计算APK文件MD5并更新下载链接..."

# 使用Python脚本计算MD5（更稳定，支持大文件）
PYTHON_SCRIPT="$UPDATE_DIR/generate_file_info.py"
if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "⚠️  警告: generate_file_info.py脚本不存在，跳过download_url更新"
else
    APK_MD5=$(python3 "$PYTHON_SCRIPT" "$APK_PATH" --md5-only 2>/dev/null | tr -d ' \n\r')
    
    if [ -z "$APK_MD5" ] || [ ${#APK_MD5} -ne 32 ]; then
        echo "⚠️  警告: 无法计算APK的MD5值，跳过download_url更新"
    else
        echo "   APK MD5: $APK_MD5"
        
        # 从现有的download_url中提取基础URL部分
        # 格式: https://shv-software.oss-cn-zhangjiakou.aliyuncs.com/Android-Packages/qfl-publitity/94e5df62b0224768899900fbe7b6e68e.apk
        # 需要提取: https://shv-software.oss-cn-zhangjiakou.aliyuncs.com/Android-Packages/qfl-publitity/
        CURRENT_DOWNLOAD_URL=$(grep '^  download_url:' "$YAML_FILE" | sed 's/.*download_url: *"\(.*\)".*/\1/')
        
        if [ -n "$CURRENT_DOWNLOAD_URL" ]; then
            # 提取基础URL（去掉最后的MD5.apk部分）
            # 使用正则表达式匹配并替换
            BASE_URL=$(echo "$CURRENT_DOWNLOAD_URL" | sed 's/[a-f0-9]\{32\}\.apk$//')
            
            if [ -n "$BASE_URL" ]; then
                NEW_DOWNLOAD_URL="${BASE_URL}${APK_MD5}.apk"
                
                # 更新download_url字段
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    # macOS
                    sed -i '' "s|download_url: \".*\"|download_url: \"$NEW_DOWNLOAD_URL\"|" "$YAML_FILE"
                else
                    # Linux
                    sed -i "s|download_url: \".*\"|download_url: \"$NEW_DOWNLOAD_URL\"|" "$YAML_FILE"
                fi
                
                echo "✅ 已更新download_url: $NEW_DOWNLOAD_URL"
            else
                echo "⚠️  警告: 无法从现有download_url中提取基础URL，跳过更新"
            fi
        else
            echo "⚠️  警告: 无法读取现有的download_url，跳过更新"
        fi
    fi  # 闭合 if [ -z "$APK_MD5" ] 的 else 块
fi  # 闭合 if [ ! -f "$PYTHON_SCRIPT" ] 的 else 块

# 10. 显示构建结果
echo ""
echo "🎉 构建完成！"
echo "=========================="
echo "📋 版本变更:"
echo "   pubspec.yaml: $CURRENT_VERSION → $NEW_VERSION"
echo "   版本代码: $NEW_VERSION_CODE"
echo ""
echo "📁 APK文件位置:"
echo "   原始: build/app/outputs/flutter-apk/app-release.apk"
echo "   更新: update_plugin/$APK_NAME"
echo ""
echo "📋 下一步操作:"
echo "   1. 检查 update_plugin/update.yaml 文件"
echo "   2. 更新 description 字段（更新说明）"
echo "   3. 部署APK文件到服务器（使用MD5命名的文件）"
echo "   4. 发布更新配置"
echo ""

# 11. 显示APK文件信息
APK_SIZE=$(stat -f%z "update_plugin/$APK_NAME" 2>/dev/null || stat -c%s "update_plugin/$APK_NAME" 2>/dev/null || echo "未知")
if [ "$APK_SIZE" != "未知" ]; then
    APK_SIZE_MB=$(echo "scale=2; $APK_SIZE / 1024 / 1024" | bc -l 2>/dev/null || echo "计算失败")
    echo "📊 APK文件大小: $(printf "%'d" $APK_SIZE) 字节 (${APK_SIZE_MB} MB)"
fi

echo ""
echo "💡 提示: 使用以下命令提交更改:"
echo "   git add pubspec.yaml update_plugin/update.yaml update_plugin/$APK_NAME"
echo "   git commit -m \"🚀 发布版本 v$NEW_VERSION\"" 