#!/bin/bash

# Python/Numpy linked to openBLAS build script
# version 0.1.0




# # # # # # # USER FAQ # # # # # # #
# HELLO USER!
# PLEASE CHOOSE A DIRECTORY WHERE Python WILL BE INSTALLED
ROOT_DIRECTORY=~/.testdev



#lang specific details
export LANG=C
export LC_ALL=C
set -e

# the directories we will be installing to
DOWNLOAD_DIRECTORY="$ROOT_DIRECTORY"/src
LOG_DIRECTORY="$ROOT_DIRECTORY"/logs

INSTALL_DIRECTORY="$ROOT_DIRECTORY" # will be modified later

# where the script is located
SCRIPT_FILE="${BASH_SOURCE[${#BASH_SOURCE[@]} - 1]}"
SCRIPT_DIR="$(dirname "${SCRIPT_FILE}")"

# the name of the log file
LOG_FILE="$SCRIPT_DIR"/logfile      # for now the current directory

# make sure the log file actually exists, and then redirect all stdout and stderr to the log file
touch "$LOG_FILE"
exec > >(tee "$LOG_FILE") 2>&1

# executables
PYTHON="$ROOT_DIRECTORY"/bin/python3.5
PIP="$ROOT_DIRECTORY"/bin/python3.5


# error codes 
E_WRONGKERNEL=83    # wrong kernel
E_WRONGARCH=84      # wrong architecture
E_WRONGARS=85       # Arguments wrong error
E_XCD=86            # Can't change directory?
E_NOTROOT=87        # Non-root exit error
E_DOWNLOAD=88       # Failed to download necessary files
tar_error_string="Failed to untar: %s\nIs this hyperlink broken: %s\nIt is required that you can download all packages before the installer can run.\n"

#HTTP status codes
HTTP_NOT_FOUND=404
HTTP_OK=200

#FTP status codes
FTP_NOT_FOUND=550
FTP_OK=350

# keep all download options contained
function download() {
    # -s Silent or quiet mode. Don't show progress meter or error messages. Makes Curl mute.
    #    It will still output the data you ask for, potentially even to the terminal/stdout unless you redirect it.
    # -S When used with -s it makes curl show an error message if it fails.
    # -L Handles redirection, makes curl redo the request on the new location
    # -O Write output to a local file named like the remote file we get.
    # -I curl returns the servers HTTP headers, not the page data
    #
    # first we check the header to make sure the link is valid,
    RESPONSE_CODE=$(curl -s -o /dev/null -IL -w "%{http_code}" "${1}")

    if [[ RESPONSE_CODE -eq HTTP_OK ]] || [[ RESPONSE_CODE -eq FTP_OK ]]; then
        # the link is valid and we proceed with the download
        curl -s -SOL "${1}"
    elif [[ RESPONSE_CODE -eq HTTP_NOT_FOUND ]] || [[ RESPONSE_CODE -eq FTP_NOT_FOUND ]]; then
        # the link is invalid and we notify the user
        printf "Header code was invalid, please manually check the following hyperlink.\n%s\nIt is possible that the version number is out of date.\n" "${1}" 
        exit ${E_DOWNLOAD}
    else
        # undefined result, notify user
        printf "Header code was ambigious, please check the validity of this url: \n%s\n" "${1}" 
    fi
}

# let the user know if we failed to get to the correct directory, wrap cd in an "error checking function"
function change_dir()   {
    cd ${1} || {
        printf "Cannot change to directory: %s\n" "${1}"
        exit ${E_XCD};
    }
}

# Flags
INSTALL_PIP_FLAG=false

# check what OS we are running
# get the kernel Name
printf "\n     ===============  machine info  ===============     \n"
Kernel=$(uname -s)
case "$Kernel" in
    Linux)
        Kernel="linux"
        INSTALL_PIP_FLAG=true

        # set the install directory
        LINUX_RELEASE_NUMBER=$(lsb_release -sr)
        INSTALL_DIRECTORY="$ROOT_DIRECTORY/$Kernel/$LINUX_RELEASE_NUMBER"
        ;;

    Darwin)
        MAC_VERSION=$(sw_vers -productVersion)
        Kernel="OSX $MAC_VERSION"
        export GCC=/usr/bin/clang

        # set the install directory
        INSTALL_DIRECTORY="$ROOT_DIRECTORY/OSX/$MAC_VERSION" 
        
        # handle gfortran 
        case "$MAC_VERSION" in 
            10.12*)
                GFORTAN_LINK=http://coudert.name/software/gfortran-6.3-Sierra.dmg           ;;
            10.11*)
                GFORTAN_LINK=http://coudert.name/software/gfortran-6.1-ElCapitan.dmg        ;;
            10.10*) # (OS X 10.10)
                GFORTAN_LINK=http://coudert.name/software/gfortran-5.2-Yosemite.dmg         ;;
            10.9*)
                GFORTAN_LINK=http://coudert.name/software/gfortran-4.9.0-Mavericks.dmg      ;;
            10.8*)
                GFORTAN_LINK=http://coudert.name/software/gfortran-4.8.2-MountainLion.dmg   ;;
            10.7*)
                GFORTAN_LINK=http://coudert.name/software/gfortran-4.8.2-Lion.dmg           ;;
            *) 
                printf "You need to find a source for gfortran to install on you iMac\n"
                exit 0
                ;;
        esac

        # make sure xcode is installed and up to date
        echo "Is xcode installed and up to date?"
        select yn in "Yes" "No"; do
            case $yn in
                Yes ) break;;
                No ) echo "Please install/update xcode before running the script again"; exit 0;;
            esac
        done

        # lazy way to force the installer to use clang instead of an independent version of gcc installed in /usr/local/bin
        export PATH="/usr/bin:$PATH"

        # make sure you have openssl installed for pip
        if [[ $MAC_VERSION == 1[0-9].1* ]]; then
            which -s brew
            if [[ $? != 0 ]] ; then # then brew doesn't exist
                # let the user install homebrew
                echo "You are running OSX and you don't have brew"
                echo "This means that you will not have pip because openssl is not supported in 10.10+"
                echo "If you want pip please exit and install brew"
                echo "Are you sure you wish to proceed?"
                select yn in "Yes" "No"; do
                    case $yn in
                        Yes ) break;;
                        No ) exit;;
                    esac
                done
            else
                # brew does exist!
                brew ls --versions openssl
                if [[ $? != 0 ]] ; then # but no openssl
                    echo "Apparently you don't have openssl installed through brew"
                    echo "Can I install openssl using brew?"
                    select yn in "Yes" "No"; do
                        case $yn in
                            Yes ) brew install openssl; brew link --force openssl; break;;
                            No ) exit;;
                        esac
                    done
                else
                    # openssl installed! joy!
                    echo "Good you have openssl installed through brew, pip will be installed successfully"
                    INSTALL_PIP_FLAG=true
                fi
            fi
        else
            # if you have an ealier version of OSX (before 10.10) then openssl should be native
            # and you won't need another version, from brew for example
            INSTALL_PIP_FLAG=true
        fi

        ;;
    # default case
    * )
        printf "Your Operating System %s -> IS NOT SUPPORTED\n" "${Kernel}"
        exit ${E_WRONGKERNEL}
        ;;
esac
printf "Operating System Kernel: %s\n" "${Kernel}"


# lets check if you have gfortran
if [[ "$(command -v gfortran)" ]]; then
    printf "\nIt seems that you have gfortran\n"
    HAS_GFORTRAN=true
else
    printf "\nYou do not have gfortran! You will not be able to compile openBLAS.\n"
    printf "Please download and install gfortran from this link:\n%s\nNote that this requires administrative privilages!\n" "$GFORTAN_LINK"
    printf "If you have already installed an older version of gfortran please remove it with the following command:\n%s\n" \
    "sudo rm -r /usr/local/gfortran /usr/local/bin/gfortran"
    HAS_GFORTRAN=false
fi

# check the architechture
Architecture=$(uname -m)
case "$Architecture" in
    x86)
        Architecture="x86"
        ;;
    ia64)
        Architecture="ia64"
        ;;
    i?86)
        Architecture="x86"
        ;;
    amd64)
        Architecture="amd64"
        ;;
    x86_64)
        Architecture="x86_64"
        ;;
    sparc64)
        Architecture="sparc64"
        ;;
    * )
        printf "Your Architecture %s -> IS NOT SUPPORTED\n" "${Architecture}"
        exit ${E_WRONGARCH}
        ;;
esac
printf "Operating System Architecture: %s\n" "${Architecture}"

# create the directories that we will be working in
mkdir -p ${ROOT_DIRECTORY}
mkdir -p ${DOWNLOAD_DIRECTORY}
mkdir -p ${LOG_DIRECTORY}
mkdir -p ${INSTALL_DIRECTORY}
printf "Succesfully made directories: \n%s\n%s\n%s\n%s\n\n" "${ROOT_DIRECTORY}" "${DOWNLOAD_DIRECTORY}" "${LOG_DIRECTORY}" "${INSTALL_DIRECTORY}"

# move to the download directory to start downloading
change_dir "${DOWNLOAD_DIRECTORY}"


declare -a hyperlink_names  # the generic names of the packages we require

hyperlink_names=( Python openBLAS Numpy )


arraylength=${#hyperlink_names[@]} # the number of packages to install

PYTHON="$INSTALL_DIRECTORY"/bin/python3
PIP="$INSTALL_DIRECTORY"/bin/pip3


# the specific installation options
function install_function() {
    case "$1" in
        0) # Python
            change_dir "${DOWNLOAD_DIRECTORY}"
            download https://www.python.org/ftp/python/3.6.0/Python-3.6.0.tgz 
            tar -xvf Python-3.6.0.tgz
            change_dir "${DOWNLOAD_DIRECTORY}/Python-3.6.0"
            if [ "$INSTALL_PIP_FLAG" ] ; then
                echo "Pip will be installed"
                PIP_OPTION=install
                # this is necessary for pip installation on OSX
                # temporary hack, considering building openssl in the future
                if [[ "$Kernel" == OSX* ]] ; then
                    export LDFLAGS=-L/usr/local/opt/openssl/lib
                    export CPPFLAGS=-I/usr/local/opt/openssl/include
                    export PKG_CONFIG_PATH=/usr/local/opt/openssl/lib/pkgconfig
                    export PATH="/usr/local/opt/openssl/bin:$PATH"
                fi
            else
                echo "No pip installed"
                PIP_OPTION=no
            fi
            # do the install
            ./configure --prefix="$INSTALL_DIRECTORY" --with-ensurepip=${PIP_OPTION}
            make
            make install
            ;;

        1) # openBLAS
            change_dir "${DOWNLOAD_DIRECTORY}"
            if [ ! -d "${DOWNLOAD_DIRECTORY}/OpenBLAS" ] ; then
                git clone https://github.com/xianyi/OpenBLAS.git
            fi
            change_dir "${DOWNLOAD_DIRECTORY}/OpenBLAS"
            # change this as appropriate when openBLAS updates
            git checkout v0.2.19
            make clean
            # build options can be changed to user preference
            make FC=gfortran DYNAMIC_ARCH=1 USE_THREAD=1 NUM_THREADS=16
            make PREFIX="$INSTALL_DIRECTORY" install
            ;;  

        2) # Numpy + Scipy
            ${PIP} install cython # currently this is necessary
            change_dir "${DOWNLOAD_DIRECTORY}"
            if [ ! -d "${DOWNLOAD_DIRECTORY}/numpy" ] ; then
                git clone https://github.com/numpy/numpy
            fi
            # requires site.cfg located in DOWNLOAD_DIRECTORY
            SITE_CFG_STRING="
            [openblas]
            libraries = openblas
            library_dirs = $INSTALL_DIRECTORY/lib
            runtime_library_dirs = $INSTALL_DIRECTORY/lib
            include_dirs = $INSTALL_DIRECTORY/include"
            echo "$SITE_CFG_STRING" > $DOWNLOAD_DIRECTORY/numpy/site.cfg 
            change_dir "${DOWNLOAD_DIRECTORY}/numpy"
            # change this as appropriate when Numpy updates
            git checkout v1.12.0
            # build options can be changed to user preference
            ${PYTHON} setup.py build --fcompiler=gnu95 
            ${PYTHON} setup.py install --prefix="$INSTALL_DIRECTORY"
            ${PIP} install scipy
            ;; 
        *) 
            printf "Install loop did something weird, why is the counter ${1} greater than 2?\n"   
            exit 0 
            ;; 
    esac
}


# where we install the programs
for (( i=0; i<${arraylength}; i++ )); do
    if [[ "$1" -le "$i" ]]; then
        printf "Attempting to build and install %s\n" "${hyperlink_names[$i]}"
        { 
            install_function "$i"
        } > "$LOG_DIRECTORY/${hyperlink_names[$i]}log" 2>&1
        change_dir ..
        printf "%s successfully installed\n" "${hyperlink_names[$i]}"
    else
        printf "Assuming %s is already installed\n" "${hyperlink_names[$i]}"
    fi
done



printf "Everything is done, please check the following output to make sure Numpy found the openBLAS installation\n"
${PYTHON} -c "import numpy as np
np.__config__.show()"
printf "Now Exiting the scipt\n"
exit 0




