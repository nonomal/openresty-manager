#!/bin/bash

# OpenResty Manager one click installation script
# Supported system: CentOS/RHEL 7+, Debian 11+, Ubuntu 18+, Fedora 32+, etc

info() {
    echo -e "\033[32m[OpenResty Manager] $*\033[0m"
}

warning() {
    echo -e "\033[33m[OpenResty Manager] $*\033[0m"
}

abort() {
    echo -e "\033[31m[OpenResty Manager] $*\033[0m"
    exit 1
}

if [[ $EUID -ne 0 ]]; then
    abort "This script must be run with root privileges"
fi

OS_ARCH=$(uname -m)
case "$OS_ARCH" in
    x86_64|arm*|aarch64)
    ;;
    *)
    abort "Unsupported CPU arch: $OS_ARCH"
    ;;
esac

if [ -f /etc/os-release ]; then
    source /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
    OS_NAME=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    OS_VERSION=$(lsb_release -sr)
else
    abort "Unable to detect operating system"
fi

normalize_version() {
    local version=$1
    version=$(echo "$version" | tr -d '[:alpha:]_-' | sed 's/\.\+/./g')
    IFS='.' read -ra segments <<< "$version"

    while [ ${#segments[@]} -lt 4 ]; do
        segments+=(0)
    done

    printf "%04d%04d%04d%04d" \
        "${segments[0]}" \
        "${segments[1]}" \
        "${segments[2]}" \
        "${segments[3]}"
}

NEW_OS_VERSION=$(normalize_version "$OS_VERSION")

install_dependencies() {
    case $OS_NAME in
        ubuntu)
            apt-get update
            apt-get -y install software-properties-common
            add-apt-repository ppa:maxmind/ppa
            apt-get -y install --no-install-recommends wget gnupg ca-certificates lsb-release libmaxminddb0 curl tar
            ;;
        debian)
            apt-get update
            apt-get -y install --no-install-recommends wget gnupg ca-certificates libmaxminddb0 curl tar
            ;;
        centos|rocky|oracle|rhel|amazon|alinux|tlinux|mariner)
            yum install -y yum-utils wget libmaxminddb curl tar
            ;;
        fedora)
            dnf install -y dnf-plugins-core wget libmaxminddb curl tar
            ;;
        sles|opensuse)
            zypper install -y wget libmaxminddb curl tar
            ;;
        alpine)
            apk add wget libmaxminddb curl tar
            ;;
        *)
            abort "Unsupported Linux distributions: $OS_NAME"
            ;;
    esac
}

check_ports() {
    if [ $(command -v ss) ]; then
        for port in 80 443 777 34567; do
            if ss -tln "( sport = :${port} )" | grep -q LISTEN; then
                abort "Port ${port} is occupied, please close it and try again"
            fi
        done
	fi
}

add_repository() {
    case $OS_NAME in
        ubuntu)
            local v2=$(normalize_version "22")
            local v3=$(normalize_version "18")
            if [ "$NEW_OS_VERSION" -ge "$v2" ]; then
                wget -O - https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/openresty.gpg
                if [ "$OS_ARCH" = "x86_64" ]; then
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/ubuntu $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/openresty.list > /dev/null
                else
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/arm64/ubuntu $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/openresty.list > /dev/null
                fi
            elif [ "$NEW_OS_VERSION" -lt "$v3" ]; then
                abort "The operating system version is too low"
            else
                wget -O - https://openresty.org/package/pubkey.gpg | apt-key add -
                if [ "$OS_ARCH" = "x86_64" ]; then
                    echo "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/openresty.list
                else
                    echo "deb http://openresty.org/package/arm64/ubuntu $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/openresty.list
                fi
            fi
            apt-get update
            ;;
        debian)
            local v2=$(normalize_version "12")
            if [ "$NEW_OS_VERSION" -ge "$v2" ]; then
                wget -O - https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/openresty.gpg
            else
                wget -O - https://openresty.org/package/pubkey.gpg | apt-key add -
            fi
            codename=`grep -Po 'VERSION="[0-9]+ \(\K[^)]+' /etc/os-release`
            if [ "$OS_ARCH" = "x86_64" ]; then                
                echo "deb http://openresty.org/package/debian $codename openresty" | tee /etc/apt/sources.list.d/openresty.list
            else
                echo "deb http://openresty.org/package/arm64/debian $codename openresty" | tee /etc/apt/sources.list.d/openresty.list
            fi
            apt-get update
            ;;
        centos|rhel|alinux|tlinux|rocky|mariner)
            local v2=$(normalize_version "9")
            if [ "$NEW_OS_VERSION" -ge "$v2" ]; then
                wget -O /etc/yum.repos.d/openresty.repo "https://openresty.org/package/${OS_NAME}/openresty2.repo"
            else
                wget -O /etc/yum.repos.d/openresty.repo "https://openresty.org/package/${OS_NAME}/openresty.repo"
            fi
            yum check-update
            ;;
        fedora)
            dnf config-manager --add-repo https://openresty.org/package/fedora/openresty.repo
            ;;
        amazon|oracle)
            yum-config-manager --add-repo "https://openresty.org/package/${OS_NAME}/openresty.repo"
            ;;
        sles)
            rpm --import https://openresty.org/package/pubkey.gpg
            zypper ar -g --refresh --check "https://openresty.org/package/sles/openresty.repo"
            zypper mr --gpgcheck-allow-unsigned-repo openresty
            ;;
        opensuse)
            zypper ar -g --refresh --check https://openresty.org/package/opensuse/openresty.repo
            zypper --gpg-auto-import-keys refresh
            ;;
        alpine)
            wget -O '/etc/apk/keys/admin@openresty.com-5ea678a6.rsa.pub' 'http://openresty.org/package/admin@openresty.com-5ea678a6.rsa.pub'
            . /etc/os-release
            MAJOR_VER=`echo $VERSION_ID | sed 's/\.[0-9]\+$//'`
            echo "http://openresty.org/package/alpine/v$MAJOR_VER/main" | tee -a /etc/apk/repositories
            apk update
            ;;
        *)
            abort "Unsupported Linux distributions"
            ;;
    esac
}

install_openresty() {
    case $OS_NAME in
        debian|ubuntu)
            apt-get install -y openresty
            ;;
        centos|rhel|amazon|alinux|tlinux|rocky|oracle|mariner)
            yum install -y openresty
            ;;
        fedora)
            dnf install -y openresty
            ;;
        sles|opensuse)
            zypper install -y openresty
            ;;
        alpine)
            apk add openresty
            ;;
    esac
    if [ $? -ne "0" ]; then
        abort "Installation of OpenResty failed, please refer to https://openresty.org/en/linux-packages.html"
    fi
    systemctl stop openresty > /dev/null 2>&1
    systemctl disable openresty > /dev/null 2>&1
}

install_docker() {
    if [ ! $(command -v docker) ]; then
        warning "Docker Engine not detected, we will automatically install it for you. The process is slow, please be patient ..."
        curl https://om.uusec.com/install-docker.sh -o /tmp/install-docker.sh
        sh /tmp/install-docker.sh
        if [ $? -ne "0" ]; then
            abort "Automatic installation of Docker Engine failed. Please manually install it before executing this script"
        fi
        systemctl enable docker && systemctl daemon-reload && systemctl restart docker
    fi
}

install_openresty_manager() {
    if [ "$OS_ARCH" = "x86_64" ]; then                
        curl https://download.uusec.com/om.tgz -o /tmp/om.tgz
    else
        curl https://download.uusec.com/om_arm64.tgz -o /tmp/om.tgz
    fi
    mkdir -p /opt && tar -zxf /tmp/om.tgz -C /opt/ && /opt/om/oms -s install && /opt/om/oms -s start
    if [ $? -ne "0" ]; then
        abort "Installation of OpenResty Manager failed"
    fi
}

allow_firewall_ports() {
    if [ ! -f "/opt/om/.fw" ];then
        echo "" > /opt/om/.fw
        if [ $(command -v firewall-cmd) ]; then
            firewall-cmd --permanent --add-port={80,443,34567}/tcp > /dev/null 2>&1
            firewall-cmd --reload > /dev/null 2>&1
        elif [ $(command -v ufw) ]; then
            for port in 80 443 34567; do ufw allow $port/tcp > /dev/null 2>&1; done
            ufw reload > /dev/null 2>&1
        fi
    fi
}

main() {
    info "Detected system: ${OS_NAME} ${OS_VERSION} ${OS_ARCH}"
    
    warning "Install dependencies ..."
    install_dependencies

    warning "Check for port conflicts ..."
    check_ports

    if [ ! $(command -v openresty) ]; then
        warning "Add OpenResty repository ..."
        add_repository
        
        warning "Install OpenResty ..."
        install_openresty
    fi

    install_docker

    if [ ! -e "/opt/om" ]; then
        warning "Install OpenResty Manager ..."
        install_openresty_manager
    else
        abort 'The directory "/opt/om" already exists, please confirm to remove it and try again'
    fi

    warning "Add firewall ports exception ..."
    allow_firewall_ports

    info "Congratulations on the successful installation"
}

main
