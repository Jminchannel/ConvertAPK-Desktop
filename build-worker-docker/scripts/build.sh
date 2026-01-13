#!/bin/bash
# APK 构建主脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查错误并退出
check_error() {
    if [ $? -ne 0 ]; then
        log_error "$1"
        exit 1
    fi
}

ensure_gradle_wrapper_dist() {
    # 目标：如果 Gradle wrapper 分发包已缓存则直接复用；否则从镜像尝试下载到缓存目录，避免每次构建重新下载
    local wrapper_props=""
    for candidate in "android/gradle/wrapper/gradle-wrapper.properties" "gradle/wrapper/gradle-wrapper.properties"; do
        if [ -f "$candidate" ]; then
            wrapper_props="$candidate"
            break
        fi
    done

    if [ -z "$wrapper_props" ]; then
        log_warning "未找到 gradle-wrapper.properties，跳过 Gradle 分发包预取"
        return 0
    fi

    local dist_url_raw
    dist_url_raw="$(grep -E '^distributionUrl=' "$wrapper_props" | head -n 1 | cut -d'=' -f2-)"
    if [ -z "$dist_url_raw" ]; then
        log_warning "未找到 distributionUrl，跳过 Gradle 分发包预取"
        return 0
    fi

    # properties 里通常是 https\\://...，需要反转义
    local dist_url="${dist_url_raw//\\:/:}"
    local zip_name
    zip_name="$(basename "$dist_url")"
    local dist_name="${zip_name%.zip}"

    local gradle_user_home="${GRADLE_USER_HOME:-/root/.gradle}"
    local hash_dir
    hash_dir="$(node -e "const crypto=require('crypto');const url=process.argv[1];const hex=crypto.createHash('md5').update(url).digest('hex');console.log(BigInt('0x'+hex).toString(36));" "$dist_url" 2>/dev/null || true)"
    if [ -z "$hash_dir" ]; then
        log_warning "计算 Gradle wrapper hash 失败，跳过预取（将由 gradlew 自行下载）"
        return 0
    fi

    local target_dir="$gradle_user_home/wrapper/dists/$dist_name/$hash_dir"
    local ok_file="$target_dir/$zip_name.ok"

    if [ -f "$ok_file" ]; then
        log_info "Gradle wrapper 分发包已缓存：$dist_name/$hash_dir"
        return 0
    fi

    mkdir -p "$target_dir"

    local tmp="/tmp/$zip_name"
    rm -f "$tmp"

    local mirrors="${GRADLE_DIST_MIRRORS:-https://downloads.gradle.org/distributions https://services.gradle.org/distributions}"
    local downloaded=false

    # 先尝试 wrapper 配置里的原始地址
    if echo "$dist_url" | grep -qE '^https?://'; then
        log_info "尝试下载 Gradle 分发包: $dist_url"
        if curl -fL --connect-timeout 10 --retry 3 --retry-delay 2 -o "$tmp" "$dist_url"; then
            downloaded=true
        fi
    fi

    # 再尝试镜像列表
    if [ "$downloaded" != "true" ]; then
        for base in $mirrors; do
            local url="$base/$zip_name"
            log_info "尝试下载 Gradle 分发包: $url"
            if curl -fL --connect-timeout 10 --retry 3 --retry-delay 2 -o "$tmp" "$url"; then
                downloaded=true
                break
            fi
        done
    fi

    if [ "$downloaded" != "true" ] || [ ! -s "$tmp" ]; then
        log_warning "Gradle 分发包预取失败，将由 gradlew 自行下载（可能较慢）"
        rm -f "$tmp"
        return 0
    fi

    mv "$tmp" "$target_dir/$zip_name"
    (cd "$target_dir" && unzip -q "$zip_name")
    touch "$ok_file"
    rm -f "$target_dir/$zip_name.lck"
    rm -f "$target_dir/$zip_name"
    log_success "Gradle 分发包已写入缓存：$dist_name/$hash_dir"
    return 0
}

# ============================================
# 调试：打印所有环境变量
# ============================================
log_info "========== 环境变量调试 =========="
log_info "OUTPUT_FORMAT 原始值: '${OUTPUT_FORMAT:-未设置}'"
log_info "APP_NAME: '${APP_NAME:-未设置}'"
log_info "PACKAGE_NAME: '${PACKAGE_NAME:-未设置}'"
log_info "=================================="

# ============================================
# 步骤 0: 准备工作
# ============================================
log_info "Step 0: 准备工作..."

# 检查输入目录是否有ZIP文件
ZIP_FILE=$(find $INPUT_DIR -name "*.zip" -type f | head -n 1)

if [ -z "$ZIP_FILE" ]; then
    log_error "在 $INPUT_DIR 中没有找到ZIP文件"
    exit 1
fi

log_info "找到ZIP文件: $ZIP_FILE"

# 创建项目工作目录
PROJECT_DIR=/workspace/project
rm -rf $PROJECT_DIR
mkdir -p $PROJECT_DIR

# 解压ZIP文件
log_info "解压项目文件..."
unzip -q "$ZIP_FILE" -d $PROJECT_DIR
check_error "解压失败"

# 找到实际的项目根目录(可能在子目录中)
# 查找包含package.json的目录
PACKAGE_JSON=$(find $PROJECT_DIR -name "package.json" -type f | head -n 1)
if [ -z "$PACKAGE_JSON" ]; then
    log_error "未找到 package.json 文件"
    exit 1
fi

PROJECT_ROOT=$(dirname "$PACKAGE_JSON")
log_info "项目根目录: $PROJECT_ROOT"

cd $PROJECT_ROOT

log_success "准备工作完成"

# ============================================
# 步骤 1: 构建 Web 项目
# ============================================
log_info "Step 1: 构建 Web 项目..."

# 完整重装依赖的函数
reinstall_dependencies() {
    log_info "清理并重新安装所有依赖..."
    
    # 删除 node_modules 和 lock 文件
    rm -rf node_modules
    rm -f package-lock.json
    rm -f yarn.lock
    rm -f pnpm-lock.yaml
    
    # 重新安装
    npm install --legacy-peer-deps
    return $?
}

# 首次安装依赖
log_info "安装 npm 依赖..."
npm install --legacy-peer-deps
check_error "npm install 失败"

# 尝试构建
log_info "构建项目..."
BUILD_OUTPUT=$(npm run build 2>&1) && BUILD_SUCCESS=true || BUILD_SUCCESS=false

if [ "$BUILD_SUCCESS" = "true" ]; then
    log_success "项目构建成功"
else
    log_warning "首次构建失败，分析错误..."
    echo "$BUILD_OUTPUT"
    
    # 提取缺失的模块名
    MISSING_MODULES=""
    
    # 检查 Rollup/Vite 的 "resolve import" 错误
    ROLLUP_MISSING=$(echo "$BUILD_OUTPUT" | grep -oE 'resolve import "[^"]+"' | \
        sed 's/resolve import "\([^"]*\)"/\1/' | sort -u)
    if [ -n "$ROLLUP_MISSING" ]; then
        MISSING_MODULES="$ROLLUP_MISSING"
    fi
    
    # 检查 "Cannot find module" 错误
    CANNOT_FIND=$(echo "$BUILD_OUTPUT" | grep -oE "Cannot find module '[^']+'" | \
        sed "s/Cannot find module '\([^']*\)'/\1/" | sort -u)
    if [ -n "$CANNOT_FIND" ]; then
        MISSING_MODULES="$MISSING_MODULES $CANNOT_FIND"
    fi
    
    # 检查 "Module not found" 错误
    MODULE_NOT_FOUND=$(echo "$BUILD_OUTPUT" | grep -oE "Module not found[^']*'[^']+'" | \
        sed "s/.*'\([^']*\)'/\1/" | sort -u)
    if [ -n "$MODULE_NOT_FOUND" ]; then
        MISSING_MODULES="$MISSING_MODULES $MODULE_NOT_FOUND"
    fi
    
    if [ -n "$MISSING_MODULES" ]; then
        log_info "检测到缺失模块: $MISSING_MODULES"
        
        # 安装每个缺失的模块
        for module in $MISSING_MODULES; do
            # 提取包名（去掉子路径，如 'lodash/get' -> 'lodash'）
            PKG_NAME=$(echo "$module" | sed 's/\/.*//')
            # 过滤掉相对路径
            if [[ ! "$PKG_NAME" =~ ^\. ]] && [[ ! "$PKG_NAME" =~ ^/ ]]; then
                log_info "安装: $PKG_NAME"
                npm install "$PKG_NAME" --legacy-peer-deps --save 2>/dev/null || true
            fi
        done
        
        # 第二次尝试构建
        log_info "重新构建项目..."
        BUILD_OUTPUT2=$(npm run build 2>&1) && BUILD_SUCCESS2=true || BUILD_SUCCESS2=false
        
        if [ "$BUILD_SUCCESS2" = "true" ]; then
            log_success "项目构建成功"
        else
            log_warning "第二次构建仍失败，尝试完整重装依赖..."
            
            # 完整重装
            reinstall_dependencies
            check_error "依赖重装失败"
            
            # 第三次尝试构建
            log_info "最终构建尝试..."
            npm run build
            check_error "npm run build 失败"
        fi
    else
        # 没有检测到缺失模块，直接尝试完整重装
        log_warning "未检测到具体缺失模块，尝试完整重装依赖..."
        
        reinstall_dependencies
        check_error "依赖重装失败"
        
        # 再次构建
        log_info "重新构建项目..."
        npm run build
        check_error "npm run build 失败"
    fi
fi

# 确定输出目录
if [ -d "dist" ]; then
    WEB_DIR="dist"
elif [ -d "build" ]; then
    WEB_DIR="build"
else
    log_error "未找到构建输出目录 (dist 或 build)"
    exit 1
fi

log_success "Web 项目构建完成，输出目录: $WEB_DIR"

# ============================================
# 步骤 2: 初始化 Capacitor
# ============================================
log_info "Step 2: 初始化 Capacitor..."

# 检查是否已安装Capacitor
if ! grep -q "@capacitor/core" package.json; then
    log_info "安装 @capacitor/core..."
    npm install @capacitor/core --legacy-peer-deps
    check_error "安装 @capacitor/core 失败"
fi

if ! grep -q "@capacitor/cli" package.json; then
    log_info "安装 @capacitor/cli..."
    npm install -D @capacitor/cli --legacy-peer-deps
    check_error "安装 @capacitor/cli 失败"
fi

# 创建 capacitor.config.ts
log_info "创建 Capacitor 配置..."
cat > capacitor.config.ts << EOF
import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: '${PACKAGE_NAME}',
  appName: '${APP_NAME}',
  webDir: '${WEB_DIR}',
  server: {
    androidScheme: 'https'
  }
};

export default config;
EOF

log_success "Capacitor 初始化完成"

# ============================================
# 步骤 3: 添加 Android 平台
# ============================================
log_info "Step 3: 添加 Android 平台..."

# 检查是否已安装android平台
if ! grep -q "@capacitor/android" package.json; then
    log_info "安装 @capacitor/android..."
    npm install @capacitor/android --legacy-peer-deps
    check_error "安装 @capacitor/android 失败"
fi

# 添加Android平台
if [ ! -d "android" ]; then
    log_info "添加 Android 平台..."
    npx cap add android
    check_error "添加 Android 平台失败"
else
    log_info "Android 平台已存在"
fi

log_success "Android 平台添加完成"

# ============================================
# 步骤 4: 设置应用图标
# ============================================
log_info "Step 4: 设置应用图标..."

# 安装 @capacitor/assets
log_info "安装 @capacitor/assets..."
npm install -D @capacitor/assets --legacy-peer-deps
check_error "安装 @capacitor/assets 失败"

# 创建 assets 目录
mkdir -p assets

# 检查是否有上传的图标
if [ -f "$INPUT_DIR/logo.png" ]; then
    log_info "使用上传的图标..."
    cp "$INPUT_DIR/logo.png" assets/logo.png
else
    log_warning "未找到上传的图标，将使用默认图标"
    # 创建一个默认图标（如果没有上传）
    # 可以在这里放置一个默认图标的逻辑
fi

# 检查图标文件是否存在
if [ -f "assets/logo.png" ]; then
    log_info "生成应用图标和启动画面..."
    
    # 设置背景色（可通过环境变量自定义）
    ICON_BG_COLOR=${ICON_BG_COLOR:-"#ffffff"}
    ICON_BG_COLOR_DARK=${ICON_BG_COLOR_DARK:-"#111111"}
    SPLASH_BG_COLOR=${SPLASH_BG_COLOR:-"#ffffff"}
    SPLASH_BG_COLOR_DARK=${SPLASH_BG_COLOR_DARK:-"#111111"}
    
    npx @capacitor/assets generate --android \
        --iconBackgroundColor "$ICON_BG_COLOR" \
        --iconBackgroundColorDark "$ICON_BG_COLOR_DARK" \
        --splashBackgroundColor "$SPLASH_BG_COLOR" \
        --splashBackgroundColorDark "$SPLASH_BG_COLOR_DARK"
    check_error "图标生成失败"
    
    log_success "应用图标设置完成"
else
    log_warning "跳过图标设置（未找到 assets/logo.png）"
fi

# ============================================
# 步骤 5: 同步代码
# ============================================
log_info "Step 5: 同步代码到 Android 项目..."

npx cap sync android
check_error "代码同步失败"

log_success "代码同步完成"

# ============================================
# 步骤 6: 配置 Android 项目
# ============================================
log_info "Step 6: 配置 Android 项目..."

# 创建 local.properties
cat > android/local.properties << EOF
sdk.dir=$ANDROID_HOME
EOF

log_info "已创建 local.properties"

# 修改版本号
GRADLE_FILE="android/app/build.gradle"
if [ -f "$GRADLE_FILE" ]; then
    # 更新 versionName 和 versionCode
    sed -i "s/versionName \".*\"/versionName \"$VERSION_NAME\"/" $GRADLE_FILE
    sed -i "s/versionCode .*/versionCode $VERSION_CODE/" $GRADLE_FILE
    log_info "已更新版本信息"
fi

log_success "Android 项目配置完成"

# ============================================
# 步骤 7: 构建 Release APK
# ============================================
OUTPUT_FORMAT="${OUTPUT_FORMAT:-apk}"
OUTPUT_FORMAT="$(echo "$OUTPUT_FORMAT" | tr '[:upper:]' '[:lower:]')"
if [ "$OUTPUT_FORMAT" != "apk" ] && [ "$OUTPUT_FORMAT" != "aab" ]; then
    OUTPUT_FORMAT="apk"
fi

if [ "$OUTPUT_FORMAT" = "aab" ]; then
    log_info "Step 7: 构建 Release AAB..."
else
    log_info "Step 7: 构建 Release APK..."
fi

cd android

# 给 gradlew 执行权限
chmod +x gradlew

# 如果已缓存 Gradle wrapper 分发包就复用，否则尝试从镜像预取
ensure_gradle_wrapper_dist

# 配置国内 Maven 镜像（降低 Maven Central 卡住的概率）
GRADLE_INIT_SCRIPT="/tmp/gradle-mirrors.init.gradle"
cat > "$GRADLE_INIT_SCRIPT" << 'EOF'
allprojects {
    repositories {
        maven { url 'https://maven.aliyun.com/repository/google' }
        maven { url 'https://maven.aliyun.com/repository/central' }
        maven { url 'https://maven.aliyun.com/repository/gradle-plugin' }
        maven { url 'https://maven.aliyun.com/repository/public' }
        google()
        mavenCentral()
    }
}
EOF
GRADLE_INIT_ARGS=(--init-script "$GRADLE_INIT_SCRIPT")

# 构建 release APK（带详细日志和优化参数）
log_info "开始 Gradle 构建（可能需要几分钟下载依赖）..."

# 设置 Gradle 参数
export GRADLE_OPTS="-Xmx2g -XX:MaxMetaspaceSize=512m -XX:+HeapDumpOnOutOfMemoryError"

if [ "$OUTPUT_FORMAT" = "aab" ]; then
    # 执行构建，添加 --info 查看详细日志，--stacktrace 查看错误栈
    ./gradlew bundleRelease "${GRADLE_INIT_ARGS[@]}" \
        --no-daemon \
        --stacktrace \
        --warning-mode all \
        -Dorg.gradle.jvmargs="-Xmx2048m -XX:MaxMetaspaceSize=512m" \
        -Dorg.gradle.parallel=false \
        -Dorg.gradle.caching=false
        
    check_error "AAB 构建失败"

    # 找到生成的 AAB
    AAB_PATH=$(find . -name "*.aab" -path "*/release/*" | head -n 1)

    if [ -z "$AAB_PATH" ]; then
        log_error "未找到生成的AAB文件"
        exit 1
    fi

    log_success "AAB 构建完成: $AAB_PATH"
else
    # 执行构建，添加 --info 查看详细日志，--stacktrace 查看错误栈
    ./gradlew assembleRelease "${GRADLE_INIT_ARGS[@]}" \
        --no-daemon \
        --stacktrace \
        --warning-mode all \
        -Dorg.gradle.jvmargs="-Xmx2048m -XX:MaxMetaspaceSize=512m" \
        -Dorg.gradle.parallel=false \
        -Dorg.gradle.caching=false
        
    check_error "APK 构建失败"

    # 找到生成的 APK
    APK_PATH=$(find . -name "*.apk" -path "*/release/*" | head -n 1)

    if [ -z "$APK_PATH" ]; then
        log_error "未找到生成的APK文件"
        exit 1
    fi

    log_success "APK 构建完成: $APK_PATH"
fi

cd ..

# ============================================
# 步骤 8: 生成/使用密钥库
# ============================================
log_info "Step 8: 准备签名密钥..."

KEYSTORE_FILE="$KEYSTORE_DIR/release.keystore"

# 定义生成新keystore的函数
generate_keystore() {
    log_info "生成新的签名密钥..."
    keytool -genkeypair -v \
        -keystore "$KEYSTORE_FILE" \
        -alias "$KEY_ALIAS" \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -storepass "$KEYSTORE_PASSWORD" \
        -keypass "$KEY_PASSWORD" \
        -dname "CN=APK Builder, OU=Dev, O=Company, L=City, ST=State, C=CN"
    check_error "密钥生成失败"
    log_success "签名密钥生成完成"
}

# 检查是否复用签名密钥
if [ "$KEYSTORE_REUSED" = "true" ]; then
    log_info "使用复用的签名密钥（用于应用更新）..."
    if [ ! -f "$KEYSTORE_FILE" ]; then
        log_error "复用签名模式下密钥库文件不存在！"
        exit 1
    fi
    # 验证密码
    if ! keytool -list -keystore "$KEYSTORE_FILE" -storepass "$KEYSTORE_PASSWORD" > /dev/null 2>&1; then
        log_error "复用签名模式下密钥库密码不匹配！请检查密码配置。"
        exit 1
    fi
    log_success "复用签名密钥验证成功"
else
    # 非复用模式：如果没有密钥库则生成新的
    if [ ! -f "$KEYSTORE_FILE" ]; then
        generate_keystore
    else
        log_info "检测到现有密钥库，验证密码..."
        # 验证keystore密码是否正确
        if keytool -list -keystore "$KEYSTORE_FILE" -storepass "$KEYSTORE_PASSWORD" > /dev/null 2>&1; then
            log_success "密钥库密码验证成功"
        else
            log_warning "密钥库密码不匹配，将重新生成密钥库..."
            rm -f "$KEYSTORE_FILE"
            generate_keystore
        fi
    fi
fi

# ============================================
# 步骤 9: 对齐 APK / 准备 AAB 输出
# ============================================
if [ "$OUTPUT_FORMAT" = "aab" ]; then
    log_info "Step 9: 准备 AAB 输出..."
else
    log_info "Step 9: 对齐 APK (zipalign)..."
fi

cd android

FINAL_OUTPUT=""

if [ "$OUTPUT_FORMAT" = "aab" ]; then
    # 复制 AAB 到输出目录
    UNSIGNED_AAB="$OUTPUT_DIR/app-release-unsigned.aab"
    SIGNED_AAB="$OUTPUT_DIR/${APP_NAME}-v${VERSION_NAME}.aab"
    cp "$AAB_PATH" "$UNSIGNED_AAB"
    check_error "复制 AAB 失败"
    log_success "AAB 输出已准备"
else
    # 复制 APK 到临时位置
    UNSIGNED_APK="$OUTPUT_DIR/app-release-unsigned.apk"
    ALIGNED_APK="$OUTPUT_DIR/app-release-aligned.apk"
    SIGNED_APK="$OUTPUT_DIR/${APP_NAME}-v${VERSION_NAME}.apk"
    cp "$APK_PATH" "$UNSIGNED_APK"

    # 使用 zipalign 对齐
    zipalign -p -f -v 4 "$UNSIGNED_APK" "$ALIGNED_APK"
    check_error "APK 对齐失败"

    log_success "APK 对齐完成"
fi

# ============================================
# 步骤 10: 签名 APK / AAB
# ============================================
if [ "$OUTPUT_FORMAT" = "aab" ]; then
    log_info "Step 10: 签名 AAB (jarsigner)..."

    # AAB 使用 jarsigner（AAB 本质是 zip/jar 格式）
    jarsigner \
        -digestalg SHA-256 \
        -sigalg SHA256withRSA \
        -keystore "$KEYSTORE_FILE" \
        -storepass "$KEYSTORE_PASSWORD" \
        -keypass "$KEY_PASSWORD" \
        -signedjar "$SIGNED_AAB" \
        "$UNSIGNED_AAB" \
        "$KEY_ALIAS"
    check_error "AAB 签名失败"

    # 验证签名
    log_info "验证 AAB 签名..."
    jarsigner -verify -verbose -certs "$SIGNED_AAB"
    check_error "AAB 签名验证失败"

    log_success "AAB 签名完成"
    FINAL_OUTPUT="$SIGNED_AAB"
else
    log_info "Step 10: 签名 APK (apksigner)..."

    apksigner sign \
        --ks "$KEYSTORE_FILE" \
        --ks-key-alias "$KEY_ALIAS" \
        --ks-pass pass:"$KEYSTORE_PASSWORD" \
        --key-pass pass:"$KEY_PASSWORD" \
        --v1-signing-enabled true \
        --v2-signing-enabled true \
        --v3-signing-enabled true \
        --out "$SIGNED_APK" \
        "$ALIGNED_APK"
    check_error "APK 签名失败"

    # 验证签名
    log_info "验证 APK 签名..."
    apksigner verify --verbose "$SIGNED_APK"
    check_error "APK 签名验证失败"

    log_success "APK 签名完成"
    FINAL_OUTPUT="$SIGNED_APK"
fi

# ============================================
# 清理临时文件
# ============================================
log_info "清理临时文件..."
rm -f "$UNSIGNED_APK" "$ALIGNED_APK" "$UNSIGNED_AAB" 2>/dev/null || true

# ============================================
# 完成
# ============================================
echo ""
echo "============================================"
if [ "$OUTPUT_FORMAT" = "aab" ]; then
    log_success "🎉 AAB 构建完成!"
else
    log_success "🎉 APK 构建完成!"
fi
echo "============================================"
echo ""
echo "📦 输出文件: $FINAL_OUTPUT"
echo "📊 文件大小: $(du -h "$FINAL_OUTPUT" | cut -f1)"
echo ""
echo "============================================"
