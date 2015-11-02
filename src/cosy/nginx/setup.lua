return [==[
  #! /bin/bash

  ##
  ## This script sets up a CosyVerif client
  ##  - it detects which package could suits to your OS/Arch
  ##  - it downloads the package from the cosy server
  ##  - it installs the package onto your machine
  ##

  red='\033[0;31m'
  green='\033[0;32m'
  nc='\033[0m'

  tempwd=$(mktemp -d)
  log=$(mktemp)

  for i in "$@"
  do
    case ${i} in
      -f=*|--package-uri=*)
        package_uri="${i#*=}"
        package_uri=${package_uri%/}
        shift # past argument=value
      ;;
      -r=*|--root-uri=*)
        root_uri="${i#*=}"
        root_uri=${root_uri%/}
        shift # past argument=value
      ;;
      -p=*|--prefix=*)
        prefix="${i#*=}"
        prefix=${prefix%/}
        shift # past argument=value
      ;;
      -h|--help)
        echo "Usage: "
        echo "  install [--prefix=PREFIX] [--root-uri=<URI> | --package-uri=<URI>]"
        exit 1
      ;;
      *)
        echo "Usage: "
        echo "  install [--prefix=PREFIX] [--root-uri=<URI> | --package-uri=<URI>]"
        exit 1
      ;;
    esac
  done

  prefix=${prefix:-"/usr/local/"}

  if [ ! -z "${root_uri}" ] && [ ! -z "${package_uri}" ]; then
    echo -e "${red}Error: cannot set both '--root-uri' and '--package-uri'.${nc}"
    exit 1
  elif [ -z "${root_uri}" ] && [ -z "${package_uri}" ]; then
    root_uri="ROOT_URI"
  fi

  function fix_string ()
  {
    echo "$1" \
      | sed -e 's/^[[:space:]]+/ /' \
      | sed -e 's/^[[:space:]]*//' \
      | sed -e 's/[[:space:]]*$//' \
      | tr '/' '-' \
      | tr '[:upper:]' '[:lower:]'
  }

  if [ ! -z "${root_uri}" ]; then
    os=$(fix_string "$(uname -s)")
    arch=$(fix_string "$(uname -m)")
    package_uri="${root_uri}/setup/${arch}/${os}/client.tar.gz"
  fi

  echo -e "Temporary directory: ${green}${tempwd}${nc}"
  echo -e "Log file           : ${green}${log}${nc}"
  echo -e "Prefix             : ${green}${prefix}${nc}"
  echo -e "Package URI        : ${green}${package_uri}${nc}"

  cd "${tempwd}"

  function download ()
  {
    echo -e "Downloading package ${green}${package_uri}${nc}."
    {
      if command -v curl; then
        curl --location --output "client.tar.gz" "${package_uri}"
        return
      elif command -v wget; then
        wget --output-document="client.tar.gz" "${package_uri}"
        return
      fi
    } >> "${log}" 2>&1
    echo -e "${red}Error: neither curl nor wget is available.${nc}"
    exit 1;
  }

  function install ()
  {
    echo -e "Installing package to ${green}${prefix}${nc}."
    {
      mkdir -p "${prefix}"
      tar xf  "client.tar.gz" \
              --preserve-permissions \
              --strip-components=1 \
              --directory "${prefix}"
    } >> "${log}" 2>&1
  }

  function fix ()
  {
    echo -e "Fixing COSY_PREFIX in ${green}${prefix}/bin/cosy-path${nc}."
    sed -i  "s|export COSY_PREFIX=.*|export COSY_PREFIX=\"${prefix}\"|" \
            "${prefix}/bin/cosy-path" \
            >> "${log}" 2>&1
  }

  function error ()
  {
    echo -e "${red}An error happened.${nc}"
    echo -e "Please read log file: ${red}${log}${nc}."
    cat "${log}"
    exit 1
  }

  trap error ERR
  download
  install
  fix
  ${prefix}/bin/cosy --server="ROOT_URI" --help > /dev/null 2>&1

  echo "You can now try the following commands:"
  echo "- ${prefix}/bin/cosy            : to run the cosy client"
  echo "- ${prefix}/bin/cosy-version    : to get version number"
  echo "- ${prefix}/bin/cosy-uninstall  : to uninstall cosy"
]==]