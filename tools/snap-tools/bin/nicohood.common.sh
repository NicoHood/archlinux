#!/bin/bash

# Include guard
[ -n "${_NICOHOOD_COMMON}" ] && return || readonly _NICOHOOD_COMMON=1

# Print initial welcome message with version information
VERSION="1.0.3"
echo "ArchLinux install scripts ${VERSION} https://github.com/NicoHood"
echo "More information: https://wiki.archlinux.org/index.php/installation_guide"
echo ""

# Default settings
DEFAULT_SUBVOLUMES=(git vm data Documents Videos Music Downloads Pictures)

# Avoid any encoding problems
export LANG=C

# Check if messages are to be printed using color
unset ALL_OFF BOLD BLUE GREEN RED YELLOW MAGENTA CYAN
if [[ -t 2 ]]; then
    # Prefer terminal safe colored and bold text when tput is supported
    if tput setaf 0 &>/dev/null; then
        ALL_OFF="$(tput sgr0)"
        BOLD="$(tput bold)"
        BLUE="${BOLD}$(tput setaf 4)"
        GREEN="${BOLD}$(tput setaf 2)"
        RED="${BOLD}$(tput setaf 1)"
        YELLOW="${BOLD}$(tput setaf 3)"
        MAGENTA="${BOLD}$(tput setaf 5)"
        CYAN="${BOLD}$(tput setaf 6)"
    else
        ALL_OFF="\e[1;0m"
        BOLD="\e[1;1m"
        BLUE="${BOLD}\e[1;34m"
        GREEN="${BOLD}\e[1;32m"
        RED="${BOLD}\e[1;31m"
        YELLOW="${BOLD}\e[1;33m"
        MAGENTA="${BOLD}\e[1;35m"
        CYAN="${BOLD}\e[1;36m"
    fi
fi
readonly ALL_OFF BOLD BLUE GREEN RED YELLOW MAGENTA CYAN

function msg()
{
    echo "${GREEN}==>${ALL_OFF}${BOLD} ${1}${ALL_OFF}" >&2
}

function msg2()
{
    echo "${BLUE}  ->${ALL_OFF}${BOLD} ${1}${ALL_OFF}" >&2
}

function plain()
{
    echo "    ${1}" >&2
}

function warning()
{
    echo "${YELLOW}==> WARNING:${ALL_OFF}${BOLD} ${1}${ALL_OFF}" >&2
}

function error()
{
    echo "${RED}==> ERROR:${ALL_OFF}${BOLD} ${1}${ALL_OFF}" >&2
}

function die()
{
    error "${1}"
    exit 1
}

function kill_exit
{
    echo ""
    warning "Exited due to user intervention."
    exit 1
}

function abort_exit {
    warning "Aborted by user."
    exit 0
}

function command_not_found_handle
{
    die "${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${1}: command not found."
}

function check_dependency()
{
    local RET=0
    for dependency in "${@}"
    do
        if ! command -v "${dependency}" &> /dev/null; then
            error "Required dependency '${dependency}' not found."
            RET=1
        fi
    done
    return "${RET}"
}

# Trap errors
set -o errexit -o errtrace -u
trap 'die "${BASH_SOURCE[0]}: Error on or near line ${LINENO}."' ERR
trap kill_exit SIGTERM SIGINT SIGHUP

# Check if dependencies are available
# Dependencies: bash arch-install-scripts btrfs-progs dosfstools sed cryptsetup
check_dependency pacstrap arch-chroot genfstab btrfs mkfs.fat sed cryptsetup rankmirrors \
     || die "Please install the missing dependencies."
