#!/bin/bash
if [ -z "$GITHUB_WORKSPACE" ];then
    echo "GITHUB_WORKSPACE environemnt variable not set!"
    exit 1
fi
if [ "$#" -ne 1 ];then
    echo "Usage: ${0} [x86|x86_64|armhf|aarch64]"
    echo "Example: ${0} x86_64"
    exit 1
fi
set -e
set -o pipefail
set -x
source $GITHUB_WORKSPACE/build/lib.sh
init_lib $1

build_openssh() {
    fetch "https://github.com/openssh/openssh-portable.git" "${BUILD_DIRECTORY}/openssh-portable" git
    cd "${BUILD_DIRECTORY}/openssh-portable"
    git checkout V_9_1_P1
    git clean -fdx
    autoreconf -i
    
    # 注入你指定的完整极简编译参数
    CC="gcc ${GCC_OPTS}" \
        CXX="g++ ${GXX_OPTS}" \
        CXXFLAGS="-I${BUILD_DIRECTORY}/openssl -I${BUILD_DIRECTORY}/binutils-gdb/zlib" \
        ./configure \
            --prefix=/usr \
            --sysconfdir=/etc/ssh \
            --with-privsep-path=/var/empty \
            --with-ssl-engine \
            --with-ssl-dir="${BUILD_DIRECTORY}/openssl" \
            --with-zlib="${BUILD_DIRECTORY}/binutils-gdb/zlib" \
            --with-ldflags=-static \
            --host="$(get_host_triple)" \
            --with-pam=no \
            --without-xauth \
            --without-kerberos5 \
            --without-zlib-version-check \
            --disable-utmp \
            --disable-utmpx \
            --disable-wtmp \
            --disable-lastlog
            
    make -j4
    
    # 仅对需要的二进制文件进行去符号表(瘦身)操作
    strip ssh sshd ssh-keygen scp
}

main() {
    lib_build_openssl
    lib_build_zlib
    build_openssh
    
    # 检查核心文件是否成功生成
    if [ ! -f "${BUILD_DIRECTORY}/openssh-portable/ssh" -o \
         ! -f "${BUILD_DIRECTORY}/openssh-portable/sshd" -o \
         ! -f "${BUILD_DIRECTORY}/openssh-portable/ssh-keygen" -o \
         ! -f "${BUILD_DIRECTORY}/openssh-portable/scp" ];then
        echo "[-] Building OpenSSH ${CURRENT_ARCH} failed!"
        exit 1
    fi
    
    OPENSSH_VERSION=$(get_version "${BUILD_DIRECTORY}/openssh-portable/ssh -V 2>&1 | awk '{print \$1}' | sed 's/,//g'")
    version_number=$(echo "$OPENSSH_VERSION" | cut -d"-" -f2 | cut -d"_" -f2)
    
    # 仅复制你强制保留的组件，不再打包其他冗余文件
    cp "${BUILD_DIRECTORY}/openssh-portable/ssh" "${OUTPUT_DIRECTORY}/ssh${OPENSSH_VERSION}"
    cp "${BUILD_DIRECTORY}/openssh-portable/sshd" "${OUTPUT_DIRECTORY}/sshd${OPENSSH_VERSION}"
    cp "${BUILD_DIRECTORY}/openssh-portable/ssh-keygen" "${OUTPUT_DIRECTORY}/ssh-keygen${OPENSSH_VERSION}"
    cp "${BUILD_DIRECTORY}/openssh-portable/scp" "${OUTPUT_DIRECTORY}/scp${OPENSSH_VERSION}"

    echo "[+] Finished building OpenSSH ${CURRENT_ARCH}"

    OPENSSH_VERSION=$(echo $OPENSSH_VERSION | sed 's/-//')
    # 修复了双引号闭合问题，确保环境变量正确传递
    echo "PACKAGED_NAME=${OPENSSH_VERSION}" >> "$GITHUB_OUTPUT"
    echo "PACKAGED_NAME_PATH=/output/*" >> "$GITHUB_OUTPUT"
    echo "PACKAGED_VERSION=${version_number}" >> "$GITHUB_OUTPUT"
}

main